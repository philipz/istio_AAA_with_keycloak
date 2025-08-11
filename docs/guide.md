# Istio 服務網格安全防護指南

本指南基於本專案的實際實施經驗，描述了在 Istio 平台中採用 **mTLS + JWT 雙重認證模式** 的完整安全架構，這是目前在 Istio 中防止惡意程式入侵擴散最有效的深度防禦策略。

## 🏗️ 專案架構概述

```
┌─────────────────┐    mTLS+JWT    ┌─────────────────┐    mTLS+JWT    ┌─────────────────┐
│   Client Apps   │ ──────────────→│  Istio Gateway  │──────────────→│ Greeting Service│
└─────────────────┘                └─────────────────┘                │  (REST API)     │
                                            │                        └─────────────────┘
                                            │                                 │
                                            ▼                                 │ mTLS+JWT
                                   ┌─────────────────┐                        │
                                   │    Keycloak     │                        ▼
                                   │  (JWT Issuer)   │                ┌─────────────────┐
                                   └─────────────────┘                │   Book Service  │
                                                                      │  (Backend API)  │
                                                                      └─────────────────┘
                                                                              │
                                                                              ▼
                                                                      ┌─────────────────┐
                                                                      │   MySQL DB      │
                                                                      │  (Data Store)   │
                                                                      └─────────────────┘
```

**服務調用流程**：
1. **Client → Gateway**: 用戶端透過 JWT token 請求 Greeting Service
2. **Gateway → Greeting**: Istio Gateway 路由請求到 Greeting Service (REST API 層)
3. **Greeting → Book**: Greeting Service 透過 mTLS + JWT 雙重認證調用 Book Service
4. **Book → MySQL**: Book Service 處理業務邏輯並存取資料庫

**專案實施背景**：
- **架構**: Spring Boot 3.5.4 + Istio Service Mesh + Keycloak + Kind Kubernetes
- **應用場景**: 圖書管理系統的請求級身份驗證與授權
- **核心特性**: mTLS + JWT 雙重認證、細粒度授權策略、GraalVM Native Image 支持
- **安全特色**: 防入侵橫向擴散、Spring Boot Actuator 端口分離、JWT Audiences 控制

## 推薦方案：mTLS + JWT 雙重認證架構

### 核心設計原理

**第一層防護：mTLS基礎身份驗證**
Istio自動將所有代理間的流量升級為相互TLS，確保服務間通訊的基礎安全。

**第二層防護：JWT應用層授權**
JWT認證可以與mTLS認證結合使用，當JWT用作代表終端調用者的憑證，且被請求的服務需要證明它是代表終端調用者被調用時。

### 技術實施架構

```yaml
# 1. 強制mTLS模式 - 基礎傳輸層安全
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT  # 強制所有服務間通訊使用mTLS

---
# 2. JWT請求認證 - 應用層身份驗證
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: jwt-auth
  namespace: production
spec:
  selector:
    matchLabels:
      app: payment-service
  jwtRules:
  - issuer: "https://identity-server.internal"
    jwksUri: "https://identity-server.internal/.well-known/jwks.json"
    audiences:
    - "payment-api"
    forwardOriginalToken: true

---
# 3. 細粒度授權政策 - 防止橫向攻擊
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: payment-service-authz
  namespace: production
spec:
  selector:
    matchLabels:
      app: payment-service
  action: ALLOW
  rules:
  # 只允許特定服務在特定條件下存取
  - from:
    - source:
        principals: ["cluster.local/ns/api-gateway/sa/gateway-service"]
    when:
    - key: request.auth.claims[role]
      values: ["payment-processor"]
    - key: request.headers[x-request-context]
      values: ["authenticated-transaction"]
  # 限制存取的API端點
  - to:
    - operation:
        methods: ["POST"]
        paths: ["/api/v1/payments/process"]
    when:
    - key: source.ip
      values: ["10.0.0.0/8"]  # 只允許內部網路
```

### 本專案安全架構實現

基於實際部署的 Greeting Service → Book Service 調用鏈安全配置：

```yaml
# 本專案實際配置 - mTLS 強制模式
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT

---
# 本專案實際配置 - JWT 請求認證 (Book Service)
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: book-info-request-authentication
spec:
  selector:
    matchLabels:
      app: book-info
  jwtRules:
  - issuer: "http://keycloak.172.19.0.6.nip.io/realms/Istio"
    jwksUri: "http://keycloak.172.19.0.6.nip.io/realms/Istio/protocol/openid-connect/certs"
    audiences: ["client", "api-client"]

---
# 本專案實際配置 - 服務間調用授權策略
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: book-info-enhanced-auth
spec:
  selector:
    matchLabels:
      app: book-info
  action: ALLOW
  rules:
  # 允許 Greeting Service 透過 mTLS + JWT 調用 Book Service
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/greeting-service"]
        requestPrincipals: ["*"]
    to:
    - operation:
        methods: ["GET"]
        paths: ["/getbooks", "/getbookbytitle*"]
    when:
    - key: request.auth.claims[azp]
      values: ["client", "api-client"]
  
  # 只有 admin 角色可以新增書籍
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/greeting-service"]
        requestPrincipals: ["*"]
    to:
    - operation:
        methods: ["POST"]
        paths: ["/addbook*"]
    when:
    - key: request.auth.claims[realm_access][roles]
      values: ["admin"]
    - key: request.auth.claims[azp]
      values: ["client", "api-client"]
```

### 關鍵防護機制

**1. 服務身份綁定與權限隔離**
```yaml
# 基於SPIFFE身份的細粒度控制
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: zero-trust-policy
spec:
  rules:
  - from:
    - source:
        principals: ["spiffe://cluster.local/ns/orders/sa/order-service"]
    to:
    - operation:
        methods: ["GET"]
        paths: ["/api/v1/inventory/check"]
    when:
    # 時間窗口限制
    - key: request.time.hour
      values: ["9", "10", "11", "12", "13", "14", "15", "16", "17"]
    # JWT Claims驗證
    - key: request.auth.claims[transaction_id]
      notValues: [""]
```

**2. 動態威脅檢測與隔離**
```yaml
# 基於行為的DENY政策
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: threat-isolation
spec:
  action: DENY
  rules:
  # 阻止異常高頻請求
  - when:
    - key: request.headers[x-request-rate]
      values: ["high"]
  # 阻止可疑的JWT Claims
  - when:
    - key: request.auth.claims[sub]
      values: ["suspicious-*"]
  # 阻止非預期的服務調用模式
  - from:
    - source:
        principals: ["spiffe://cluster.local/ns/frontend/sa/web-app"]
    to:
    - operation:
        paths: ["/internal/*"]  # 前端服務不應存取內部API
```

### 為什麼選擇這個方案？

**1. 針對入侵擴散的深度防禦**

當服務A被入侵但仍保有有效的mTLS身份時，JWT層提供額外驗證，確保請求確實代表合法的終端用戶或業務上下文。

**2. Istio原生整合優勢**

PeerAuthentication強制執行mTLS認證，而RequestAuthentication提供對傳入請求認證的細粒度控制，支援JWT驗證和API密鑰認證等機制。

**3. 實時威脅響應能力**
```yaml
# 緊急隔離機制
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: emergency-lockdown
  annotations:
    security.istio.io/incident-response: "active"
spec:
  action: DENY
  rules:
  - from:
    - source:
        principals: ["spiffe://cluster.local/ns/compromised/sa/suspicious-service"]
  # 可在檢測到威脅時立即部署
```

### 與其他方案的比較

| 方案 | 入侵防護能力 | Istio整合度 | 實施複雜度 | 防護深度 |
|------|-------------|-------------|------------|----------|
| **純mTLS** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **純JWT** | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| **mTLS+JWT** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **SPIFFE/SPIRE** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |

### 實際部署建議

**階段1：基礎環境準備**（1週）
```bash
# 建立 Kind 集群
kind create cluster --config istio-keycloak/kind.yml

# 安裝 Istio
istioctl install --set profile=demo -y
```

**階段2：應用與身份服務部署**（1-2週）
```bash
# 部署 MySQL 資料庫
kubectl apply -f istio-keycloak/app/database.yaml

# 部署 Book Service (Backend API)
kubectl apply -f istio-keycloak/app/app.yaml

# 部署 Greeting Service (REST API 層)
kubectl apply -f AuthorizationPolicy/greeting-service-account.yaml

# 部署 Keycloak (Identity Provider)
kubectl apply -f keycloak/keycloak.yaml
kubectl apply -f keycloak/keycloak-gateway.yaml
```

**階段3：安全策略實施**（1-2週）
```bash
# 啟用 mTLS
kubectl apply -f PeerAuthentication/

# 配置 JWT 認證
kubectl apply -f istio-keycloak/istio-manifests/requestAuthentication.yaml

# 部署授權策略
kubectl apply -f istio-keycloak/istio-manifests/authorizationPolicy.yaml
```

**監控與應急響應**
```yaml
# 配置安全監控
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: security-monitoring
spec:
  metrics:
  - providers:
    - name: prometheus
  - overrides:
    - match:
        metric: ALL_METRICS
      tagOverrides:
        source_workload:
          value: "%{SOURCE_WORKLOAD}"
        jwt_claims:
          value: "%{REQUEST_AUTH_CLAIMS}"
```

## 專案實際部署經驗

### 關鍵配置文件

基於本專案的實施，以下是核心配置：

```yaml
# PeerAuthentication - 強制 mTLS
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
```

```yaml
# RequestAuthentication - JWT 驗證
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: book-info-request-authentication
spec:
  selector:
    matchLabels:
      app: book-info
  jwtRules:
  - issuer: "http://keycloak.172.19.0.6.nip.io/realms/Istio"
    jwksUri: "http://keycloak.172.19.0.6.nip.io/realms/Istio/protocol/openid-connect/certs"
    audiences: ["client", "api-client"]
```

### 實際遇到的問題與解決方案

#### 1. AuthorizationPolicy OR 邏輯安全漏洞

**問題**：發現了嚴重的安全問題，OR 邏輯導致 JWT-only 請求被允許通過

**解決方案**：修改為 AND 邏輯，確保同時需要 mTLS 和 JWT 認證

#### 2. Spring Boot Actuator 健康檢查衝突

**問題**：Actuator 端點被 OAuth2 安全配置阻擋，導致應用 CrashLoopBackOff

**解決方案**：將 Actuator 分離到獨立端口 9000

```properties
management.server.port=9000
```

#### 3. ServiceAccount 名稱不匹配

**問題**：AuthorizationPolicy 引用的 ServiceAccount 不存在

**解決方案**：確保 ServiceAccount 名稱與 Deployment 中的 serviceAccountName 一致

### GraalVM Native Image 支持

本專案已配置 GraalVM Native Image 支持，實現更輕量的容器鏡像：

```xml
<profile>
  <id>native</id>
  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
        <configuration>
          <image>
            <builder>paketobuildpacks/builder-jammy-buildpackless-tiny</builder>
            <buildpacks>
              <buildpack>paketobuildpacks/oracle</buildpack>
              <buildpack>paketobuildpacks/java-native-image</buildpack>
            </buildpacks>
          </image>
        </configuration>
      </plugin>
    </plugins>
  </build>
</profile>
```

### JWT Audiences 安全控制

**重要發現**：`audiences` 參數是防止 token 濫用的關鍵安全控制

```yaml
audiences: ["client", "api-client"]  # 限制 token 使用範圍
```

如果省略此參數，將導致任何來自同一 Issuer 的 JWT 都能通過驗證，增加橫向攻擊風險。

## 部署指令參考

```bash
# 1. 部署基礎設施
kind create cluster --config kind.yml
istioctl install --set profile=demo -y

# 2. 部署應用
kubectl apply -f istio-keycloak/app/database.yaml
kubectl apply -f istio-keycloak/app/app.yaml

# 3. 配置安全策略
kubectl apply -f authorization-policy-enhanced.yaml
kubectl apply -f PeerAuthentication/request-authentication-enhanced.yaml

# 4. 部署 ServiceAccount
kubectl apply -f greeting-service-account.yaml

# 5. Native Image 建置
./mvnw spring-boot:build-image -Pnative -DskipTests
```

## 監控與驗證

```bash
# 檢查 mTLS 狀態
istioctl proxy-status

# 驗證 JWT 配置
istioctl proxy-config listeners <pod-name> --port 15006

# 檢查授權決策
kubectl logs -l app=istiod -n istio-system | grep authorization
```

**總結**：基於本專案的實際實施經驗，mTLS + JWT 雙重認證確實是防止服務入侵橫向擴散的最佳選擇。通過正確配置 AND 邏輯、ServiceAccount 管理、JWT Audiences 控制和 Spring Boot 端口分離，可以構建一個真正安全、可靠的微服務架構。配合 Istio 的 AuthorizationPolicy，實現了毫秒級的動態威脅隔離，是企業級微服務安全的理想選擇。