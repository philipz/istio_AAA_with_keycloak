# Istio Machine to Machine (M2M) API 權限管制設計

## 概述

本文檔描述了在 Istio 服務網格中實現 Machine to Machine (M2M) API 權限管制的完整設計方案。基於本專案的實際實施經驗，結合身份認證、授權策略和相互 TLS 來確保 API 的安全訪問。

**專案背景**: 本專案基於 Spring Boot 3.5.4 + Istio + Keycloak，實現了圖書管理系統的 M2M 安全架構，包含 mTLS + JWT 雙重認證機制。

## 1. 身份認證 (Authentication)

### 使用 JWT Token 進行 M2M 認證

```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: m2m-auth
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  jwtRules:
  - issuer: "http://keycloak.172.19.0.6.nip.io/realms/Istio"
    jwksUri: "http://keycloak.172.19.0.6.nip.io/realms/Istio/protocol/openid-connect/certs"
    audiences: ["api-client"]
```

## 2. 授權策略 (Authorization Policy)

### 基於 Service Account 的 M2M 授權

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: m2m-api-policy
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/api-client"]
    to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/api/v1/*"]
```

### 基於 JWT Claims 的細粒度控制

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: m2m-jwt-policy
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  action: ALLOW
  rules:
  - from:
    - source:
        requestPrincipals: ["*"]
    to:
    - operation:
        methods: ["GET"]
        paths: ["/api/v1/read/*"]
    when:
    - key: request.auth.claims[scope]
      values: ["read"]
  - from:
    - source:
        requestPrincipals: ["*"]
    to:
    - operation:
        methods: ["POST", "PUT", "DELETE"]
        paths: ["/api/v1/write/*"]
    when:
    - key: request.auth.claims[scope]
      values: ["write"]
```

## 3. 相互 TLS (Mutual TLS)

### 啟用嚴格模式確保安全通信

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
```

## 4. 完整的 M2M API 權限管制架構

### 步驟 1: 配置 Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-client
  namespace: default
```

### 步驟 2: 配置 API 服務

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
spec:
  template:
    metadata:
      labels:
        app: api-service
        sidecar.istio.io/inject: "true"
    spec:
      serviceAccountName: api-service
      containers:
      - name: api-service
        image: your-api-service:latest
```

### 步驟 3: 配置認證策略

```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: m2m-jwt-auth
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  jwtRules:
  - issuer: "http://keycloak.172.19.0.6.nip.io/realms/Istio"
    jwksUri: "http://keycloak.172.19.0.6.nip.io/realms/Istio/protocol/openid-connect/certs"
    audiences: ["api-client"]
    forwardOriginalToken: true
```

### 步驟 4: 配置授權策略

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: m2m-api-authorization
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  action: ALLOW
  rules:
  # 允許來自特定 Service Account 的請求
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/api-client"]
    to:
    - operation:
        methods: ["GET"]
        paths: ["/api/v1/public/*"]
  
  # 基於 JWT Claims 的授權
  - from:
    - source:
        requestPrincipals: ["*"]
    to:
    - operation:
        methods: ["POST", "PUT"]
        paths: ["/api/v1/data/*"]
    when:
    - key: request.auth.claims[role]
      values: ["data-writer"]
  
  # 拒絕未認證的請求
  - from:
    - source:
        notRequestPrincipals: ["*"]
    to:
    - operation:
        paths: ["/api/v1/*"]
  action: DENY
```

## 5. 最佳實踐

### 1. 使用最小權限原則

```yaml
# 從拒絕所有開始，逐步開放權限
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-all-default
spec:
  action: DENY
  rules:
  - {}
```

### 2. 實施 API 版本控制

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-version-control
spec:
  selector:
    matchLabels:
      app: api-service
  action: ALLOW
  rules:
  - to:
    - operation:
        paths: ["/api/v1/*"]
    when:
    - key: request.headers[api-version]
      values: ["v1"]
```

### 3. 監控和審計

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: audit-policy
spec:
  selector:
    matchLabels:
      app: api-service
  action: ALLOW
  rules:
  - to:
    - operation:
        methods: ["GET"]
        paths: ["/api/v1/audit/*"]
    when:
    - key: request.auth.claims[audit]
      values: ["true"]
```

## 6. 關鍵考量點

1. **相互 TLS 依賴**: 使用 `principals` 和 `requestPrincipals` 時必須啟用相互 TLS
2. **JWT Token 管理**: 確保 JWT token 的安全發放和驗證
3. **Service Account 管理**: 為每個 M2M 客戶端分配專用的 Service Account
4. **權限粒度**: 根據業務需求設計適當的權限粒度
5. **監控和日誌**: 實施完整的審計日誌和監控

## 7. 實施步驟

1. **準備階段**
   - 設計 API 權限矩陣
   - 定義 Service Account 和角色
   - 配置 JWT 發放服務

2. **部署階段**
   - 部署相互 TLS 配置
   - 部署認證策略
   - 部署授權策略
   - 測試和驗證

3. **監控階段**
   - 實施審計日誌
   - 配置監控告警
   - 定期安全審查

## 8. 故障排除

### 常見問題

1. **JWT Token 驗證失敗**
   - 檢查 issuer 和 jwksUri 配置
   - 驗證 token 格式和簽名

2. **授權策略不生效**
   - 確認相互 TLS 已啟用
   - 檢查 selector 標籤匹配
   - 驗證 principals 配置

3. **Service Account 權限問題**
   - 確認 Service Account 存在
   - 檢查 RBAC 配置
   - 驗證命名空間權限

## 9. 專案實際配置範例

基於本專案的實際實施，以下是關鍵配置文件：

### RequestAuthentication 配置

```yaml
# PeerAuthentication/request-authentication-enhanced.yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: book-info-request-authentication
  namespace: default
spec:
  selector:
    matchLabels:
      app: book-info
  jwtRules:
  - issuer: "http://keycloak.172.19.0.6.nip.io/realms/Istio"
    jwksUri: "http://keycloak.172.19.0.6.nip.io/realms/Istio/protocol/openid-connect/certs"
    audiences: ["client", "api-client"]  # 詳見 JWT Audiences 最佳實踐
    forwardOriginalToken: true
```

### AuthorizationPolicy 配置

```yaml
# authorization-policy-enhanced.yaml (mTLS + JWT 雙重認證)
- from:
  - source:
      principals: ["cluster.local/ns/default/sa/greeting-service"]  # mTLS 身份
      requestPrincipals: ["*"]                                     # JWT 認證
  to:
  - operation:
      methods: ["GET"]
      paths: ["/getbooks", "/getbookbytitle*"]
  when:
  - key: request.auth.claims[azp]
    values: ["client", "api-client"]
```

### ServiceAccount 配置

```yaml
# greeting-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: greeting-service
  namespace: default
  labels:
    app: greeting
```

### Spring Boot 配置

```properties
# src/main/resources/application.properties
management.server.port=9000  # Actuator 分離至獨立端口
spring.security.oauth2.client.provider.keycloak.issuer-uri=http://keycloak.172.19.0.6.nip.io/realms/Istio
```

## 10. JWT Audiences 最佳實踐

### Audiences 參數重要性

JWT 中的 `audiences` 參數是關鍵的安全控制機制：

```yaml
audiences: ["client", "api-client"]
```

**用途**:
- 確保 JWT token 只能用於指定的接收者
- 防止 token 在不同服務間的濫用
- 實現服務間的 token 隔離

**如果省略 audiences 的風險**:
- 任何來自同一 Issuer 的有效 JWT 都會被接受
- 失去服務間的 token 邊界控制
- 增加橫向攻擊的風險

## 11. 已知問題與解決方案

### OR 邏輯安全漏洞

**問題**: AuthorizationPolicy 中的 OR 邏輯可能導致安全漏洞

```yaml
# ❌ 錯誤配置 - OR 邏輯
- from:
  - source:
      principals: ["cluster.local/ns/default/sa/greeting-service"]  # 條件 A
  - source:
      requestPrincipals: ["*"]                                     # 條件 B
```

**解決方案**: 使用 AND 邏輯

```yaml
# ✅ 正確配置 - AND 邏輯
- from:
  - source:
      principals: ["cluster.local/ns/default/sa/greeting-service"]  # mTLS + JWT
      requestPrincipals: ["*"]
```

### Spring Boot Actuator 配置衝突

**問題**: Actuator 端點被 OAuth2 安全配置阻擋
**解決方案**: 分離 Actuator 到獨立端口 (9000)

這個架構提供了完整且經過實戰驗證的 M2M API 權限管制解決方案，結合了 Istio 的身份認證、授權和相互 TLS 功能，確保 API 的安全訪問。

## 延伸閱讀

- [如何在 Keycloak 中配置 aud](https://dev.to/metacosmos/how-to-configure-audience-in-keycloak-kp4)
- [Istio mTLS + JWT 雙重認證分析](./mTLS_JWT.md)
- [專案實施指南](./guide.md)