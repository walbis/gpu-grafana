#!/bin/bash
#
# Huawei CCE Storage Benchmark Cleanup
# Removes all benchmark resources
#

set -e

NAMESPACE="fio-benchmark"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo ""
echo "=============================================="
echo "   Huawei CCE Storage Benchmark Cleanup"
echo "=============================================="
echo ""

# Check if namespace exists
if kubectl get ns "$NAMESPACE" > /dev/null 2>&1; then
    log_info "Deleting namespace: $NAMESPACE"
    log_info "This will remove all PVCs, Jobs, and Pods in the namespace."
    echo ""

    # Show what will be deleted
    log_info "Resources to be deleted:"
    kubectl get all,pvc -n "$NAMESPACE" 2>/dev/null || true
    echo ""

    # Delete namespace
    kubectl delete ns "$NAMESPACE" --ignore-not-found

    # Wait for namespace deletion
    log_info "Waiting for namespace deletion..."
    for i in {1..60}; do
        if ! kubectl get ns "$NAMESPACE" > /dev/null 2>&1; then
            break
        fi
        sleep 2
    done

    log_success "Namespace $NAMESPACE deleted."
else
    log_warn "Namespace $NAMESPACE does not exist. Nothing to clean up."
fi

echo ""
log_info "Cleanup complete!"
log_info "Note: Result files in ./fio-results-* directories are preserved."
