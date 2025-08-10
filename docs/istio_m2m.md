# Istio Machine to Machine (M2M) API 權限管制設計

## 概述

在 Istio 架構下實現 Machine to Machine (M2M) 的 API 權限管制，主要結合身份認證、授權策略和相互 TLS 來確保 API 的安全訪問。

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

這個架構提供了完整的 M2M API 權限管制解決方案，結合了 Istio 的身份認證、授權和相互 TLS 功能，確保 API 的安全訪問。

[About Aud](https://dev.to/metacosmos/how-to-configure-audience-in-keycloak-kp4)