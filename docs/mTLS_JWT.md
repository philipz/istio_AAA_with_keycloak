# Istio mTLS + JWT 雙重認證配置分析與最佳實踐

## 概述

本文檔記錄了在 Istio service mesh 中實施 mTLS + JWT 雙重認證時遇到的關鍵配置問題，以及正確的解決方案。這些問題在生產環境中可能導致意外的安全漏洞。

## 問題分析

### 🚨 發現的安全問題

在 `authorization-policy-enhanced.yaml` 中發現了一個嚴重的邏輯錯誤，導致授權策略無法按預期工作：

```yaml
# 有問題的配置 - OR 邏輯導致安全漏洞
- from:
  - source:
      principals: ["cluster.local/ns/default/sa/greeting-service"]  # 條件 A
  - source:
      requestPrincipals: ["*"]                                     # 條件 B
```

### 問題根因分析

**邏輯運算**: 條件 A **OR** 條件 B
- **條件 A**: `principals: ["cluster.local/ns/default/sa/greeting-service"]` 
  - ❌ **失敗**: ServiceAccount `greeting-service` 不存在
- **條件 B**: `requestPrincipals: ["*"]`
  - ✅ **成功**: 任何有效的 JWT Token 都會通過

**結果**: 由於 OR 邏輯，任何持有有效 JWT 的請求都可以訪問 `/getbooks`，完全繞過了 mTLS 身份驗證要求。

### 實際測試結果

```bash
# 檢查 ServiceAccount 狀態
$ kubectl get serviceaccounts -n default
NAME      SECRETS   AGE
default   0         2d23h

# greeting-service ServiceAccount 不存在！

# 檢查 greeting pod 實際使用的 SA
$ kubectl get pods -l app=greeting -o jsonpath='{.items[0].spec.serviceAccountName}'
default

# API 測試結果：仍可正常訪問 /getbooks
# 原因：requestPrincipals: ["*"] 允許任何有效 JWT
```

## 安全影響評估

### 🔴 高風險場景

1. **繞過 mTLS 驗證**: 攻擊者只需要有效的 JWT Token，無需通過 Service Identity 驗證
2. **橫向移動風險**: 任何被入侵且持有 JWT 的服務都可以訪問受保護的 API
3. **身份偽造**: 無法確保請求來自預期的服務身份

### 🟡 中風險場景

1. **審計困難**: 無法通過 Service Account 追蹤請求來源
2. **權限擴散**: JWT-only 認證可能導致權限過度分配

## 正確的配置方案

### 方案 1: 真正的 mTLS + JWT 雙重認證 (推薦)

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: book-info-enhanced-auth
  namespace: default
spec:
  selector:
    matchLabels:
      app: book-info
  action: ALLOW
  rules:
  # Rule 1: 同時要求 mTLS 身份和 JWT 認證 (AND 邏輯)
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/default"]  # mTLS 身份
        requestPrincipals: ["*"]                             # JWT 認證
    to:
    - operation:
        methods: ["GET"]
        paths: ["/getbooks", "/getbookbytitle*"]
    when:
    - key: request.auth.claims[azp]
      values: ["client", "api-client"]
```

**關鍵差異**: 
- `principals` 和 `requestPrincipals` 在**同一個 source 塊**中 → **AND 邏輯**
- 必須同時滿足 mTLS 身份驗證和 JWT 認證

### 方案 2: 建立專用 ServiceAccount

```bash
# 1. 建立專用的 ServiceAccount
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: greeting-service
  namespace: default
EOF

# 2. 更新 greeting deployment 使用專用 SA
kubectl patch deployment greeting-deployment -p '{"spec":{"template":{"spec":{"serviceAccountName":"greeting-service"}}}}'
```

```yaml
# 3. 使用專用 ServiceAccount 的授權策略
- from:
  - source:
      principals: ["cluster.local/ns/default/sa/greeting-service"]
      requestPrincipals: ["*"]
```

### 方案 3: 基於 JWT Claims 的細粒度控制

```yaml
# 基於 service identity claim 的控制
- from:
  - source:
      requestPrincipals: ["*"]
    when:
    - key: request.auth.claims[sub]
      values: ["greeting-service"]
    - key: request.auth.claims[azp]
      values: ["client", "api-client"]
    - key: request.auth.claims[iss]
      values: ["http://keycloak.172.19.0.6.nip.io/realms/Istio"]
```

## 最佳實踐建議

### 1. 設計原則

```yaml
# ✅ 正確：AND 邏輯 - 同時要求 mTLS 和 JWT
- from:
  - source:
      principals: ["cluster.local/ns/default/sa/service-a"]
      requestPrincipals: ["*"]

# ❌ 錯誤：OR 邏輯 - 只要滿足其中一個條件
- from:
  - source:
      principals: ["cluster.local/ns/default/sa/service-a"]
  - source:
      requestPrincipals: ["*"]
```

### 2. ServiceAccount 管理

```yaml
# 為每個服務建立專用的 ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: greeting-service
  namespace: default
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: book-info-service
  namespace: default
```

### 3. 分層安全策略

```yaml
# Layer 1: Default DENY 策略
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: default-deny
  namespace: default
spec:
  action: DENY
  rules:
  - {}

---
# Layer 2: 明確的 ALLOW 策略
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: explicit-allow
  namespace: default
spec:
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/trusted-service"]
        requestPrincipals: ["*"]
```

### 4. JWT Claims 驗證

```yaml
# 多層 JWT 驗證
when:
- key: request.auth.claims[iss]
  values: ["https://trusted-identity-provider.com"]
- key: request.auth.claims[aud]
  values: ["book-info-api"]
- key: request.auth.claims[azp]
  values: ["client", "api-client"]
- key: request.auth.claims[exp]
  notValues: [""]  # 確保 token 有過期時間
```

## 驗證和測試

### 1. 配置驗證

```bash
# 檢查 AuthorizationPolicy 語法
kubectl apply --dry-run=client -f authorization-policy-enhanced.yaml

# 檢查 Istio 配置
istioctl analyze

# 驗證 mTLS 狀態
istioctl authn tls-check pod-name.namespace
```

### 2. 功能測試

```bash
# 測試 1: 有效的 mTLS + JWT
kubectl exec pod-with-valid-sa -c istio-proxy -- \
  curl -H "Authorization: Bearer $VALID_JWT" \
  http://book-info.default.svc.cluster.local/getbooks

# 測試 2: 只有 JWT，無有效 mTLS 身份（應該被拒絕）
kubectl exec pod-with-wrong-sa -c istio-proxy -- \
  curl -H "Authorization: Bearer $VALID_JWT" \
  http://book-info.default.svc.cluster.local/getbooks

# 測試 3: 只有 mTLS，無 JWT（應該被拒絕）
kubectl exec pod-with-valid-sa -c istio-proxy -- \
  curl http://book-info.default.svc.cluster.local/getbooks
```

### 3. 監控和日誌

```bash
# 檢查授權決策日誌
kubectl logs -l app=istiod -n istio-system | grep -i "authorization"

# 檢查 Envoy 存取日誌
kubectl logs pod-name -c istio-proxy | grep -E "(RBAC|JWT|authz)"
```

## 故障排除

### 常見問題和解決方案

| 問題 | 症狀 | 解決方案 |
|------|------|----------|
| OR 邏輯意外行為 | JWT-only 請求被允許 | 將 `principals` 和 `requestPrincipals` 放在同一個 `source` 中 |
| ServiceAccount 不存在 | `principals` 條件失敗 | 建立對應的 ServiceAccount 或使用 `default` |
| JWT 驗證失敗 | 403 錯誤 | 檢查 `issuer`, `jwksUri`, `audience` 配置 |
| mTLS 未啟用 | `principals` 無效 | 確認 `PeerAuthentication` 設定為 `STRICT` 模式 |

### 調試指令

```bash
# 檢查 pod 的實際 ServiceAccount
kubectl get pods pod-name -o jsonpath='{.spec.serviceAccountName}'

# 檢查 AuthorizationPolicy 狀態
kubectl describe authorizationpolicy policy-name

# 檢查 Istio proxy 配置
istioctl proxy-config authz pod-name

# 檢查 mTLS 狀態
istioctl proxy-status

# 檢查 JWT 配置
istioctl proxy-config listeners pod-name --port 15006 -o json | jq '.[] | .filter_chains[0].filters[0].typed_config.http_filters[] | select(.name == "envoy.filters.http.jwt_authn")'
```

## 總結

mTLS + JWT 雙重認證是 Istio 服務網格中實現深度防禦的關鍵策略。正確配置需要注意：

1. **邏輯運算符**: 理解 AND 與 OR 邏輯的差異
2. **ServiceAccount 管理**: 確保相應的 SA 存在且正確配置
3. **分層安全**: 從 DENY-all 開始，明確定義 ALLOW 規則
4. **全面測試**: 驗證各種攻擊場景和邊界條件

通過遵循這些最佳實踐，可以構建一個真正安全、可審計的服務間通信架構。


## JWT Audiences 深入分析

### 什麼是 JWT Audiences

JWT 中的 `audiences` (aud) 參數用於標識 token 的**預期接收者**，是 JWT 規範 (RFC 7519) 中的標準聲明。

在本專案的配置中：
```yaml
audiences: ["client", "api-client"]  # 需要參考如何在 Keycloak 中配置aud
```

### 安全重要性

1. **Token 專用性驗證**: 確保 JWT token 只能用於指定的接收者
2. **API 邊界控制**: 限制 token 只能用於特定的 API 端點或服務群組
3. **橫向攻擊防護**: 防止為其他服務發放的 JWT 被用於訪問 book-info 服務

### 缺少 Audiences 的風險

如果在 RequestAuthentication 中省略 `audiences` 參數：

```yaml
# 不安全的配置
jwtRules:
- issuer: "http://keycloak.172.19.0.6.nip.io/realms/Istio"
  jwksUri: "http://keycloak.172.19.0.6.nip.io/realms/Istio/protocol/openid-connect/certs"
  # 沒有 audiences 驗證
```

**安全風險**:
1. **Token 濫用**: 任何來自同一 Issuer 的有效 JWT 都會被接受
2. **權限邊界模糊**: 失去服務間的 token 隔離
3. **橫向攻擊**: 攻擊者可以使用為其他應用發放的 token 訪問當前服務

### 測試驗證

```bash
# 測試正確的 audience
curl -H "Authorization: Bearer $TOKEN_WITH_CORRECT_AUD" \
     "http://book-info/getbooks"
# 預期：成功

# 測試錯誤的 audience  
curl -H "Authorization: Bearer $TOKEN_WITH_WRONG_AUD" \
     "http://book-info/getbooks"
# 預期：403 Forbidden

# 測試無 audience 的 token
curl -H "Authorization: Bearer $TOKEN_WITHOUT_AUD" \
     "http://book-info/getbooks"  
# 預期：403 Forbidden（如果配置了 audience 驗證）
```

## 專案實施總結

本專案通過以下關鍵配置實現了真正的 mTLS + JWT 雙重認證：

### 核心安全配置

1. **mTLS 強制模式**：
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
spec:
  mtls:
    mode: STRICT
```

2. **JWT 驗證配置**：
```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
spec:
  jwtRules:
  - issuer: "http://keycloak.172.19.0.6.nip.io/realms/Istio"
    audiences: ["client", "api-client"]  # 關鍵安全控制
```

3. **AND 邏輯授權策略**：
```yaml
- from:
  - source:
      principals: ["cluster.local/ns/default/sa/greeting-service"]  # mTLS
      requestPrincipals: ["*"]                                     # JWT
```

### 解決的關鍵問題

1. **OR 邏輯安全漏洞**: 修正為 AND 邏輯確保雙重認證
2. **ServiceAccount 管理**: 建立專用 SA 並確保名稱一致
3. **Spring Boot 配置衝突**: Actuator 端口分離避免 OAuth2 衝突
4. **JWT Audiences 控制**: 實現服務間 token 隔離

### 性能優化特性

- **GraalVM Native Image**: 支持更輕量的容器鏡像
- **Spring Boot 3.5.4**: 最新版本性能優化
- **端口分離**: Actuator (9000) 與應用 (8080) 端口分離

## 延伸閱讀

* [如何在 Keycloak 中配置 aud](https://dev.to/metacosmos/how-to-configure-audience-in-keycloak-kp4)
* [Istio M2M API 權限管制設計](./istio_m2m.md)
* [Istio 服務網格安全防護指南](./guide.md)
* [GraalVM Native Image 官方文檔](https://www.graalvm.org/latest/reference-manual/native-image/)
* [Spring Boot 3.5.4 發布說明](https://github.com/spring-projects/spring-boot/releases)