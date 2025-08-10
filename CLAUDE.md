# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository demonstrates Istio service mesh integration with Keycloak for request-level authentication and authorization in Kubernetes. It includes a Spring Boot demo application (book-info) that showcases JWT-based security patterns using Istio's RequestAuthentication and AuthorizationPolicy resources.

## Architecture

**Core Components:**
- **Spring Boot Application**: Simple REST API for book management with `/getbooks` (GET) and `/addbook` (POST) endpoints
- **MySQL Database**: Data persistence layer for book information  
- **Istio Service Mesh**: Handles request-level authentication, authorization, and traffic management
- **Keycloak**: Identity and access management (IAM) provider for JWT token issuance and validation
- **Kind Cluster**: Local Kubernetes development environment with MetalLB load balancer

**Security Flow:**
1. Users authenticate with Keycloak to obtain JWT tokens
2. Istio RequestAuthentication validates JWT tokens against Keycloak's JWKS endpoint
3. Istio AuthorizationPolicy enforces role-based access control using JWT claims
4. Fine-grained authorization supports user/admin roles with different endpoint permissions

## Development Commands

### Cluster Management
```bash
# Create Kind cluster with multiple workers
kind create cluster --config kind.yml

# Delete cluster  
kind delete cluster --name istio-testing
```

### Building and Running
```bash
# Build Spring Boot application
./mvnw clean package

# Run application locally
./mvnw spring-boot:run -Dspring-boot.run.profiles=dev

# Run tests
./mvnw test
```

### Istio Operations
```bash
# Install Istio with demo profile
istioctl install --set values.pilot.env.EXTERNAL_ISTIOD=false --set profile=demo -y

# Verify installation
istioctl verify-install

# Analyze configuration
istioctl analyze

# Check proxy configuration  
istioctl proxy-config cluster <pod-name>
```

### Application Deployment
```bash
# Deploy database first (wait for readiness)
kubectl apply -f istio-keycloak/app/database.yaml
kubectl wait --for=condition=ready pod -l app=book-info-db --timeout=300s

# Deploy application
kubectl apply -f istio-keycloak/app/app.yaml

# Deploy Istio networking
kubectl apply -f istio-keycloak/istio-manifests/ingressGateway.yaml
kubectl apply -f istio-keycloak/istio-manifests/virtualService.yaml
```

### Keycloak Setup
```bash
# Deploy Keycloak
kubectl apply -f keycloak.yaml

# Get Keycloak external IP
kubectl get svc -l app=keycloak -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
```

### Security Configuration
```bash
# Apply request authentication
kubectl apply -f istio-keycloak/istio-manifests/requestAuthentication.yaml

# Apply authorization policies
kubectl apply -f istio-keycloak/istio-manifests/authorizationPolicy.yaml
```

## Key Configuration Files

**Istio Manifests:**
- `ingressGateway.yaml`: External traffic entry point
- `virtualService.yaml`: Traffic routing rules  
- `requestAuthentication.yaml`: JWT validation configuration
- `authorizationPolicy.yaml`: Role-based access control rules

**Application Manifests:**
- `app.yaml`: Spring Boot deployment with Istio sidecar injection
- `database.yaml`: MySQL deployment with persistent storage

**Keycloak Configuration:**
- Realm: `Istio`
- Client: `Istio` (OpenID Connect)
- Roles: `admin`, `user`
- Users: `book-admin` (admin role), `book-user` (user role)

## Testing Endpoints

### Generate JWT Token
```bash
# For admin user
curl -X POST -d "client_id=Istio" -d "username=book-admin" -d "password=admin123" -d "grant_type=password" "http://$KEYCLOAK_IP:8080/realms/Istio/protocol/openid-connect/token"

# For regular user  
curl -X POST -d "client_id=Istio" -d "username=book-user" -d "password=user123" -d "grant_type=password" "http://$KEYCLOAK_IP:8080/realms/Istio/protocol/openid-connect/token"
```

### API Access
```bash
# View books (any authenticated user)
curl -X GET -H "Authorization: Bearer $JWT_TOKEN" "http://$LB_IP/getbooks"

# Add book (admin only)
curl -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -d '{"isbn": 123456789, "title": "Test Book", "synopsis": "Test", "authorname": "Author", "price": 10.99}' "http://$LB_IP/addbook"
```

## Important Notes

- **IP Addresses**: Configuration files contain hardcoded IPs (172.19.0.6.nip.io) that need updating for your environment
- **Passwords**: Default passwords are used for demo purposes - change for production
- **TLS**: Current setup uses HTTP - enable TLS for production environments
- **Sidecar Injection**: Enabled via `sidecar.istio.io/inject: "true"` label on application pods
- **Role Extraction**: Authorization policies use `request.auth.claims[realm_access][roles]` to extract roles from JWT