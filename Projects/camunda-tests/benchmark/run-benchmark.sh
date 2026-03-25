#!/bin/bash
#
# Huawei CCE Storage Benchmark Runner
# Usage: FIO_IMAGE=swr.../fio:3.38 ./run-benchmark.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="fio-benchmark"
RESULTS_DIR="${SCRIPT_DIR}/fio-results-$(date +%Y%m%d-%H%M%S)"

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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for required environment variable
if [ -z "$FIO_IMAGE" ]; then
    log_warn "FIO_IMAGE environment variable is not set."
    echo ""
    read -p "Enter FIO Image path (e.g., swr.tr-west-1.myhuaweicloud.com/myproject/fio:3.38): " FIO_IMAGE
    if [ -z "$FIO_IMAGE" ]; then
        log_error "FIO_IMAGE is required. Exiting."
        exit 1
    fi
    export FIO_IMAGE
fi

log_info "Using FIO Image: $FIO_IMAGE"
log_info "Results will be saved to: $RESULTS_DIR"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Check kubectl connectivity
log_info "Checking Kubernetes connectivity..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi
log_success "Kubernetes cluster is accessible."

# Create namespace
log_info "Creating namespace: $NAMESPACE"
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Apply PVCs
log_info "Creating PVCs..."
envsubst < "${SCRIPT_DIR}/01-pvcs.yaml" | kubectl apply -f -

# Wait for PVCs to be bound
log_info "Waiting for PVCs to be bound (timeout: 5 minutes)..."
PVCS=("fio-pvc-efs-performance" "fio-pvc-efs-standard" "fio-pvc-nfs-rw")
for pvc in "${PVCS[@]}"; do
    log_info "  Waiting for $pvc..."
    if ! kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/"$pvc" -n "$NAMESPACE" --timeout=300s 2>/dev/null; then
        log_warn "$pvc is not bound yet. Checking status..."
        kubectl get pvc "$pvc" -n "$NAMESPACE" -o wide
    else
        log_success "  $pvc is Bound."
    fi
done

# Show PVC status
log_info "PVC Status:"
kubectl get pvc -n "$NAMESPACE"
echo ""

# Function to run a benchmark job
run_benchmark() {
    local job_file=$1
    local job_name=$2
    local log_file="${RESULTS_DIR}/${job_name}.txt"

    log_info "Starting benchmark: $job_name"
    log_info "  Job file: $job_file"

    # Delete existing job if any
    kubectl delete job "$job_name" -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1

    # Apply job with envsubst
    envsubst < "${SCRIPT_DIR}/${job_file}" | kubectl apply -f -

    # Wait for pod to be created
    log_info "  Waiting for pod to start..."
    sleep 5

    # Get pod name
    local pod_name
    for i in {1..30}; do
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$pod_name" ]; then
            break
        fi
        sleep 2
    done

    if [ -z "$pod_name" ]; then
        log_error "  Failed to get pod name for job $job_name"
        return 1
    fi

    log_info "  Pod: $pod_name"

    # Wait for pod to be running or completed
    log_info "  Waiting for pod to be running..."
    kubectl wait --for=condition=Ready pod/"$pod_name" -n "$NAMESPACE" --timeout=300s 2>/dev/null || true

    # Stream logs (follow until completion)
    log_info "  Streaming logs to: $log_file"
    kubectl logs -f "$pod_name" -n "$NAMESPACE" 2>&1 | tee "$log_file"

    # Check job status
    local job_status
    job_status=$(kubectl get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)

    if [ "$job_status" == "True" ]; then
        log_success "  Benchmark $job_name completed successfully!"
    else
        log_warn "  Benchmark $job_name may have issues. Check logs."
    fi

    echo ""
}

# Run benchmarks sequentially
echo ""
echo "=============================================="
echo "   Huawei CCE Storage Benchmark Suite"
echo "=============================================="
echo ""

JOBS=(
    "02-job-efs-performance.yaml:fio-bench-efs-performance"
    "03-job-efs-standard.yaml:fio-bench-efs-standard"
    "04-job-nfs-rw.yaml:fio-bench-nfs-rw"
)

for job_entry in "${JOBS[@]}"; do
    IFS=':' read -r job_file job_name <<< "$job_entry"
    run_benchmark "$job_file" "$job_name"
done

# Summary
echo ""
echo "=============================================="
echo "   Benchmark Complete!"
echo "=============================================="
echo ""
log_info "Results saved to: $RESULTS_DIR"
echo ""
ls -la "$RESULTS_DIR"
echo ""

# Show quick summary from logs
log_info "Quick Summary:"
echo ""
for result_file in "$RESULTS_DIR"/*.txt; do
    if [ -f "$result_file" ]; then
        filename=$(basename "$result_file")
        echo "--- $filename ---"
        grep -E "(IOPS=|BW=|lat.*avg=|clat percentiles)" "$result_file" | head -20 || echo "  (no summary data found)"
        echo ""
    fi
done

log_info "To cleanup: ./cleanup.sh"
