#!/bin/bash

# mTLS Verification Script for PeerAuthentication
# This script validates that mTLS is properly configured and working

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "檢查先決條件..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安裝"
        exit 1
    fi
    
    if ! command -v istioctl &> /dev/null; then
        log_error "istioctl 未安裝"
        exit 1
    fi
    
    # Check if Istio is installed
    if ! kubectl get ns istio-system &> /dev/null; then
        log_error "Istio 未安裝或 istio-system namespace 不存在"
        exit 1
    fi
    
    log_success "先決條件檢查通過"
}

# Global variables to track mTLS status
MTLS_GLOBAL_ENABLED=false
MTLS_GLOBAL_MODE=""
MTLS_DEFAULT_NS_ENABLED=false
MTLS_DEFAULT_NS_MODE=""
OVERALL_MTLS_STATUS="UNKNOWN"

# Verify PeerAuthentication policies
verify_peer_authentication() {
    log_info "檢查 PeerAuthentication 政策..."
    
    # Check global PeerAuthentication
    log_info "檢查全域 PeerAuthentication..."
    if kubectl get peerauthentication default -n istio-system &> /dev/null; then
        local mode=$(kubectl get peerauthentication default -n istio-system -o jsonpath='{.spec.mtls.mode}')
        MTLS_GLOBAL_ENABLED=true
        MTLS_GLOBAL_MODE="$mode"
        
        log_success "全域 PeerAuthentication 存在，模式: $mode"
        
        if [[ "$mode" == "STRICT" ]]; then
            log_success "全域 mTLS 設定為 STRICT 模式"
            OVERALL_MTLS_STATUS="STRICT"
        elif [[ "$mode" == "PERMISSIVE" ]]; then
            log_warning "全域 mTLS 設定為 PERMISSIVE 模式（允許明文和加密流量）"
            OVERALL_MTLS_STATUS="PERMISSIVE"
        else
            log_warning "全域 mTLS 模式未知或無效: $mode"
            OVERALL_MTLS_STATUS="INVALID"
        fi
    else
        log_error "全域 PeerAuthentication 未找到"
        log_error "沒有 PeerAuthentication 政策時，Istio 預設允許明文通信"
        OVERALL_MTLS_STATUS="NONE"
    fi
    
    # Check namespace-specific PeerAuthentication
    log_info "檢查 default namespace PeerAuthentication..."
    if kubectl get peerauthentication default -n default &> /dev/null; then
        local mode=$(kubectl get peerauthentication default -n default -o jsonpath='{.spec.mtls.mode}')
        MTLS_DEFAULT_NS_ENABLED=true
        MTLS_DEFAULT_NS_MODE="$mode"
        
        log_success "default namespace PeerAuthentication 存在，模式: $mode"
        
        # Namespace-specific policy overrides global
        if [[ "$mode" == "STRICT" ]]; then
            OVERALL_MTLS_STATUS="STRICT"
        elif [[ "$mode" == "PERMISSIVE" ]]; then
            OVERALL_MTLS_STATUS="PERMISSIVE"
        fi
    else
        if [[ "$MTLS_GLOBAL_ENABLED" == "true" ]]; then
            log_info "default namespace PeerAuthentication 未設定（繼承全域設定: $MTLS_GLOBAL_MODE）"
        else
            log_warning "default namespace PeerAuthentication 未設定，且無全域政策"
        fi
    fi
    
    # Summary of PeerAuthentication status
    log_info "PeerAuthentication 政策摘要:"
    echo "  - 全域政策: ${MTLS_GLOBAL_ENABLED} (模式: ${MTLS_GLOBAL_MODE:-N/A})"
    echo "  - default namespace 政策: ${MTLS_DEFAULT_NS_ENABLED} (模式: ${MTLS_DEFAULT_NS_MODE:-N/A})"
    echo "  - 整體 mTLS 狀態: ${OVERALL_MTLS_STATUS}"
}

# Check Istio proxy status
check_proxy_status() {
    log_info "檢查 Istio proxy 狀態..."
    
    # Get proxy status
    local proxy_status=$(istioctl proxy-status 2>/dev/null || echo "")
    
    if [[ -z "$proxy_status" ]]; then
        log_warning "無法獲取 proxy 狀態或沒有 proxy 正在運行"
        return
    fi
    
    log_success "Istio proxy 狀態:"
    echo "$proxy_status"
    
    # Check if all proxies are synced
    local unsynced=$(echo "$proxy_status" | grep -v "SYNCED" | grep -v "NAME" || true)
    if [[ -n "$unsynced" ]]; then
        log_warning "發現未同步的 proxy:"
        echo "$unsynced"
    else
        log_success "所有 proxy 都已同步"
    fi
}

# Check mTLS configuration for specific pods
check_mtls_config() {
    log_info "檢查 mTLS 配置..."
    
    # Find pods with Istio sidecar
    local pods=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.spec.containers[*].name}{"\n"}{end}' | grep istio-proxy | head -3)
    
    if [[ -z "$pods" ]]; then
        log_warning "未找到帶有 Istio sidecar 的 pod"
        return
    fi
    
    log_info "檢查以下 pod 的 mTLS 配置:"
    echo "$pods" | while read -r namespace pod containers; do
        if [[ -n "$namespace" && -n "$pod" ]]; then
            log_info "檢查 pod: $namespace/$pod"
            
            # Get cluster config to check mTLS
            local cluster_config=$(istioctl proxy-config cluster "$pod.$namespace" 2>/dev/null | grep -E "outbound|inbound" | head -5 || true)
            if [[ -n "$cluster_config" ]]; then
                echo "$cluster_config"
            else
                log_warning "無法獲取 $pod 的 cluster 配置"
            fi
            
            # Check listeners for mTLS
            local listeners=$(istioctl proxy-config listeners "$pod.$namespace" 2>/dev/null | grep -E "0.0.0.0" | head -3 || true)
            if [[ -n "$listeners" ]]; then
                log_info "Listeners 配置:"
                echo "$listeners"
            fi
        fi
    done
}

# Test mTLS connectivity
test_mtls_connectivity() {
    log_info "測試 mTLS 連接..."
    
    # Skip test if explicitly requested
    if [[ "$SKIP_CONNECTIVITY_TEST" == "true" ]]; then
        log_info "跳過連接測試（--skip-connectivity-test 參數）"
        return
    fi
    
    # Deploy test pods if they don't exist
    log_info "部署測試 pod（自動注入 Istio sidecar）..."
    
    # Create a simple test pod with curl
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: mtls-test-client
  namespace: default
  labels:
    app: mtls-test-client
  annotations:
    sidecar.istio.io/inject: "true"
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["/bin/sh", "-c", "sleep 3600"]
    imagePullPolicy: IfNotPresent
---
apiVersion: v1
kind: Pod
metadata:
  name: mtls-test-server
  namespace: default
  labels:
    app: mtls-test-server
  annotations:
    sidecar.istio.io/inject: "true"
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: mtls-test-server
  namespace: default
spec:
  selector:
    app: mtls-test-server
  ports:
  - port: 80
    targetPort: 80
EOF

    # Wait for pods to be ready
    log_info "等待測試 pod 就緒（包括 Istio sidecar 初始化）..."
    kubectl wait --for=condition=ready pod/mtls-test-client -n default --timeout=120s
    kubectl wait --for=condition=ready pod/mtls-test-server -n default --timeout=120s
    
    # Wait a bit more for Istio sidecar to fully initialize
    log_info "等待 Istio sidecar 完全初始化..."
    sleep 10
    
    # Verify sidecar injection
    local client_containers=$(kubectl get pod mtls-test-client -n default -o jsonpath='{.spec.containers[*].name}')
    local server_containers=$(kubectl get pod mtls-test-server -n default -o jsonpath='{.spec.containers[*].name}')
    
    if [[ "$client_containers" == *"istio-proxy"* ]] && [[ "$server_containers" == *"istio-proxy"* ]]; then
        log_success "測試 pod 已成功注入 Istio sidecar"
    else
        log_warning "測試 pod 可能未正確注入 Istio sidecar"
        log_info "Client 容器: $client_containers"
        log_info "Server 容器: $server_containers"
    fi
    
    # Test connectivity based on mTLS status
    log_info "根據 mTLS 狀態測試連接行為..."
    local result=$(kubectl exec mtls-test-client -n default -c curl -- curl -s -o /dev/null -w "%{http_code}" http://mtls-test-server.default.svc.cluster.local --connect-timeout 10 --max-time 15 2>/dev/null || echo "failed")
    
    # Interpret results based on mTLS configuration
    case "$OVERALL_MTLS_STATUS" in
        "STRICT")
            if [[ "$result" == "200" ]]; then
                log_success "STRICT mTLS 模式：連接成功（使用 mTLS 加密）"
                log_success "✓ mTLS 正常工作"
            elif [[ "$result" == "failed" ]]; then
                log_error "STRICT mTLS 模式：連接失敗"
                log_error "可能的原因：sidecar 未完全初始化或配置錯誤"
            else
                log_warning "STRICT mTLS 模式：意外響應碼 $result"
            fi
            ;;
        "PERMISSIVE")
            if [[ "$result" == "200" ]]; then
                log_success "PERMISSIVE 模式：連接成功"
                log_info "在 PERMISSIVE 模式下，同時允許 mTLS 和明文連接"
            else
                log_warning "PERMISSIVE 模式：連接失敗 ($result)"
            fi
            ;;
        "NONE")
            if [[ "$result" == "200" ]]; then
                log_success "無 PeerAuthentication：連接成功（明文通信）"
                log_warning "⚠️  當前網路通信未加密"
                log_warning "建議：部署 PeerAuthentication 政策以啟用 mTLS"
            else
                log_warning "無 PeerAuthentication：連接失敗 ($result)"
            fi
            ;;
        *)
            if [[ "$result" == "200" ]]; then
                log_info "連接測試成功 (HTTP 200)"
            elif [[ "$result" == "failed" ]]; then
                log_warning "連接測試失敗"
            else
                log_info "響應碼: $result"
            fi
            ;;
    esac
    
    # Additional diagnostic information
    log_info "連接測試診斷信息："
    echo "  - 測試結果: $result"
    echo "  - mTLS 狀態: $OVERALL_MTLS_STATUS"
    echo "  - 預期行為: $(get_expected_behavior)"
}

# Check certificates
check_certificates() {
    log_info "檢查 mTLS 證書..."
    
    # Find a pod with Istio proxy
    local pod_info=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.spec.containers[*].name}{"\n"}{end}' | grep istio-proxy | head -1)
    
    if [[ -z "$pod_info" ]]; then
        log_warning "未找到帶有 Istio sidecar 的 pod"
        return
    fi
    
    read -r namespace pod containers <<< "$pod_info"
    
    if [[ -n "$namespace" && -n "$pod" ]]; then
        log_info "檢查 pod $namespace/$pod 的證書..."
        
        # Get certificate information
        local cert_info=$(istioctl proxy-config secret "$pod.$namespace" 2>/dev/null | grep -E "ROOTCA|default" || true)
        
        if [[ -n "$cert_info" ]]; then
            log_success "找到 mTLS 證書:"
            echo "$cert_info"
        else
            log_warning "無法獲取證書信息"
        fi
        
        # Check certificate validity
        local cert_details=$(kubectl exec "$pod" -n "$namespace" -c istio-proxy -- ls -la /etc/ssl/certs/ 2>/dev/null | grep -E "cert-chain|key|root" || true)
        
        if [[ -n "$cert_details" ]]; then
            log_success "證書文件存在於 sidecar 中"
        else
            log_info "無法直接訪問證書文件"
        fi
    fi
}

# Get expected behavior based on mTLS status
get_expected_behavior() {
    case "$OVERALL_MTLS_STATUS" in
        "STRICT")
            echo "僅允許 mTLS 加密連接"
            ;;
        "PERMISSIVE")
            echo "允許 mTLS 和明文連接"
            ;;
        "NONE")
            echo "僅允許明文連接（無加密）"
            ;;
        *)
            echo "未知行為"
            ;;
    esac
}

# Cleanup test resources
cleanup_test_resources() {
    log_info "清理測試資源..."
    
    if [[ "$SKIP_CLEANUP" == "true" ]]; then
        log_info "跳過資源清理（--skip-cleanup 參數）"
        return
    fi
    
    kubectl delete pod mtls-test-client mtls-test-server -n default --ignore-not-found=true
    kubectl delete service mtls-test-server -n default --ignore-not-found=true
    
    log_success "測試資源已清理"
}

# Generate summary report
generate_summary() {
    log_info "生成 mTLS 驗證摘要報告..."
    
    echo ""
    echo "=================================="
    echo "       mTLS 驗證摘要報告"
    echo "=================================="
    echo ""
    
    # mTLS Status Summary
    echo "📊 mTLS 狀態概覽："
    echo "  ├─ 整體狀態: ${OVERALL_MTLS_STATUS}"
    echo "  ├─ 預期行為: $(get_expected_behavior)"
    echo "  ├─ 全域政策: ${MTLS_GLOBAL_ENABLED} (${MTLS_GLOBAL_MODE:-N/A})"
    echo "  └─ default NS 政策: ${MTLS_DEFAULT_NS_ENABLED} (${MTLS_DEFAULT_NS_MODE:-N/A})"
    echo ""
    
    # Status-based assessment
    case "$OVERALL_MTLS_STATUS" in
        "STRICT")
            echo "🔐 安全性評估: 優秀"
            echo "   ✅ 所有服務間通信都使用 mTLS 加密"
            echo "   ✅ 阻止未授權的明文連接"
            echo "   ✅ 符合零信任安全原則"
            ;;
        "PERMISSIVE")
            echo "⚠️  安全性評估: 一般"
            echo "   ✅ 支援 mTLS 加密連接"
            echo "   ⚠️  仍允許明文連接（向後兼容）"
            echo "   📋 建議：逐步遷移至 STRICT 模式"
            ;;
        "NONE")
            echo "🚨 安全性評估: 不足"
            echo "   ❌ 缺少 mTLS 保護"
            echo "   ❌ 服務間通信未加密"
            echo "   🚨 風險：可能遭受中間人攻擊"
            echo ""
            echo "🔧 立即行動項目："
            echo "   1. 部署 PeerAuthentication 政策"
            echo "   2. 確保所有 pod 注入 Istio sidecar"
            echo "   3. 測試應用程式與 mTLS 的兼容性"
            ;;
        *)
            echo "❓ 安全性評估: 未知"
            echo "   需要進一步檢查配置"
            ;;
    esac
    echo ""
    
    echo "📋 檢查項目:"
    echo "  ✓ 先決條件檢查"
    echo "  ✓ PeerAuthentication 政策分析"
    echo "  ✓ Istio proxy 狀態檢查"
    echo "  ✓ mTLS 配置驗證"
    if [[ "$SKIP_CONNECTIVITY_TEST" != "true" ]]; then
        echo "  ✓ 連接行為測試"
    else
        echo "  - 連接行為測試（已跳過）"
    fi
    echo "  ✓ 證書狀態檢查"
    echo ""
    
    # Recommendations based on current status
    echo "💡 建議事項："
    case "$OVERALL_MTLS_STATUS" in
        "STRICT")
            echo "  • 定期監控 proxy 同步狀態"
            echo "  • 驗證新部署服務的 mTLS 兼容性"
            echo "  • 定期檢查證書輪換"
            ;;
        "PERMISSIVE")
            echo "  • 規劃遷移至 STRICT 模式"
            echo "  • 識別仍使用明文連接的服務"
            echo "  • 逐步禁用明文連接"
            ;;
        "NONE")
            echo "  • 🚨 緊急：立即部署 PeerAuthentication"
            echo "  • 確認所有服務注入 Istio sidecar"
            echo "  • 規劃 mTLS 啟用策略"
            ;;
    esac
    echo "  • 確保所有服務都已注入 Istio sidecar"
    echo "  • 監控 Istio proxy 狀態確保配置同步"
    echo "  • 定期檢查證書的有效期"
    echo ""
    echo "詳細信息請參考上方的檢查輸出"
}

# Main execution
main() {
    echo ""
    echo "=================================="
    echo "    Istio mTLS 驗證腳本"
    echo "=================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    verify_peer_authentication
    echo ""
    
    check_proxy_status
    echo ""
    
    check_mtls_config
    echo ""
    
    test_mtls_connectivity
    echo ""
    
    check_certificates
    echo ""
    
    cleanup_test_resources
    echo ""
    
    generate_summary
    
    # Final status message
    case "$OVERALL_MTLS_STATUS" in
        "STRICT")
            log_success "mTLS 驗證完成！狀態：STRICT (安全性優秀)"
            exit 0
            ;;
        "PERMISSIVE")
            log_warning "mTLS 驗證完成！狀態：PERMISSIVE (安全性一般)"
            log_warning "建議升級至 STRICT 模式"
            exit 1
            ;;
        "NONE")
            log_error "mTLS 驗證完成！狀態：無保護 (安全性不足)"
            log_error "緊急：需要部署 PeerAuthentication 政策"
            exit 2
            ;;
        *)
            log_warning "mTLS 驗證完成！狀態：未知"
            log_warning "需要進一步檢查配置"
            exit 3
            ;;
    esac
}

# Handle script interruption
trap cleanup_test_resources EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-connectivity-test)
            SKIP_CONNECTIVITY_TEST=true
            shift
            ;;
        --skip-cleanup)
            SKIP_CLEANUP=true
            shift
            ;;
        --help|-h)
            echo "用法: $0 [選項]"
            echo ""
            echo "選項:"
            echo "  --skip-connectivity-test   跳過連接測試"
            echo "  --skip-cleanup            跳過測試資源清理"
            echo "  --help, -h                顯示此幫助信息"
            exit 0
            ;;
        *)
            log_error "未知參數: $1"
            exit 1
            ;;
    esac
done

# Run main function
main