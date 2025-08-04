#!/bin/bash

# LLM-D Benchmark Automation Script
# Automates the complete benchmark process including setup, execution, and result collection

set -e  # Exit on any error

# Configuration
NAMESPACE="llm-d-benchmark"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_BENCHMARK=3600  # 1 hour timeout for benchmark
TIMEOUT_ANALYSIS=600    # 10 minutes timeout for analysis

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Function to wait for job completion
wait_for_job() {
    local job_name=$1
    local timeout=$2
    local start_time=$(date +%s)
    
    log_info "Waiting for job '$job_name' to complete (timeout: ${timeout}s)..."
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $timeout ]; then
            log_error "Job '$job_name' timed out after ${timeout} seconds"
            return 1
        fi
        
        local status=$(kubectl get job $job_name -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        local failed=$(kubectl get job $job_name -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
        
        if [ "$status" = "True" ]; then
            log_success "Job '$job_name' completed successfully"
            return 0
        elif [ "$failed" = "True" ]; then
            log_error "Job '$job_name' failed"
            kubectl logs job/$job_name -n $NAMESPACE --tail=50
            return 1
        fi
        
        echo -n "."
        sleep 10
    done
}

# Function to check if kubectl is available and cluster is accessible
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to clean up old resources
cleanup_old_resources() {
    log_info "Cleaning up old resources..."
    
    # Delete old jobs
    kubectl delete jobs --all -n $NAMESPACE 2>/dev/null || true
    
    # Delete results retriever pod if it exists
    kubectl delete pod results-retriever -n $NAMESPACE 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# Function to setup namespace and resources
setup_resources() {
    log_info "Setting up namespace and resources..."
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        kubectl create namespace $NAMESPACE
        log_success "Created namespace '$NAMESPACE'"
    else
        log_info "Namespace '$NAMESPACE' already exists"
    fi
    
    # Apply resources
    if [ -d "$SCRIPT_DIR/resources" ]; then
        kubectl apply -k "$SCRIPT_DIR/resources/"
        log_success "Applied benchmark resources"
    else
        log_error "Resources directory not found at $SCRIPT_DIR/resources/"
        exit 1
    fi
    
    # Apply DNS workaround (REQUIRED)
    if [ -f "$SCRIPT_DIR/inference-gateway-service-fix.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/inference-gateway-service-fix.yaml"
        log_success "Applied DNS workaround service"
    else
        log_error "DNS workaround file not found at $SCRIPT_DIR/inference-gateway-service-fix.yaml"
        exit 1
    fi
}

# Function to run the benchmark
run_benchmark() {
    log_info "Starting benchmark job..."
    
    if [ -f "$SCRIPT_DIR/benchmark-job.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/benchmark-job.yaml"
        log_success "Benchmark job submitted"
        
        # Wait for job to complete
        if wait_for_job "benchmark-run" $TIMEOUT_BENCHMARK; then
            log_success "Benchmark completed successfully"
        else
            log_error "Benchmark failed or timed out"
            exit 1
        fi
    else
        log_error "Benchmark job file not found at $SCRIPT_DIR/benchmark-job.yaml"
        exit 1
    fi
}

# Function to run analysis
run_analysis() {
    log_info "Starting analysis job..."
    
    if [ -f "$SCRIPT_DIR/analysis-job.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/analysis-job.yaml"
        log_success "Analysis job submitted"
        
        # Wait for analysis job to complete
        local analysis_job=$(kubectl get jobs -n $NAMESPACE -o name | grep analysis | head -1 | cut -d'/' -f2)
        if [ -n "$analysis_job" ]; then
            if wait_for_job "$analysis_job" $TIMEOUT_ANALYSIS; then
                log_success "Analysis completed successfully"
            else
                log_warning "Analysis failed or timed out, but continuing with result collection"
            fi
        else
            log_warning "Could not find analysis job, but continuing with result collection"
        fi
    else
        log_error "Analysis job file not found at $SCRIPT_DIR/analysis-job.yaml"
        exit 1
    fi
}

# Function to discover actual directory name
discover_result_directory() {
    log_info "Discovering result directory structure..."
    
    # List available directories
    local directories=$(kubectl exec results-retriever -n $NAMESPACE -- ls -1 /requests/ 2>/dev/null | grep -v "analysis" || true)
    
    if [ -z "$directories" ]; then
        log_error "No result directories found"
        return 1
    fi
    
    log_info "Available result directories:"
    echo "$directories" | while read dir; do
        log_info "  - $dir"
    done >&2  # Send logs to stderr to avoid capturing in result
    
    # Return the first directory (assuming single model benchmark)
    echo "$directories" | head -1
}

# Function to collect results
collect_results() {
    log_info "Setting up results retriever and collecting results..."
    
    # Create results retriever pod
    if [ -f "$SCRIPT_DIR/retrieve.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/retrieve.yaml"
        
        # Wait for pod to be ready
        kubectl wait --for=condition=Ready pod/results-retriever -n $NAMESPACE --timeout=60s
        log_success "Results retriever pod is ready"
    else
        log_error "Retrieve pod file not found at $SCRIPT_DIR/retrieve.yaml"
        exit 1
    fi
    
    # Create local results directory
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local results_dir="$HOME/benchmark-results-$timestamp"
    mkdir -p "$results_dir/raw-data"
    log_info "Created local results directory: $results_dir"
    
    # Copy analysis results
    log_info "Copying analysis results..."
    if kubectl cp $NAMESPACE/results-retriever:/requests/analysis/ "$results_dir/" 2>/dev/null; then
        log_success "Analysis results copied"
    else
        log_warning "Could not copy analysis results (may not exist)"
    fi
    
    # Discover and copy raw benchmark data
    log_info "Copying raw benchmark data..."
    local result_dir=$(discover_result_directory)
    
    if [ -n "$result_dir" ]; then
        log_info "Copying data from directory: $result_dir"
        if kubectl cp "$NAMESPACE/results-retriever:/requests/$result_dir/" "$results_dir/raw-data/"; then
            log_success "Raw benchmark data copied"
        else
            log_error "Failed to copy raw benchmark data"
            exit 1
        fi
    else
        log_error "Could not determine result directory name"
        exit 1
    fi
    
    # Clean up retriever pod
    kubectl delete pod results-retriever -n $NAMESPACE
    log_success "Cleaned up results retriever pod"
    
    echo
    log_success "Results copied to: $results_dir"
    
    # Verify results
    verify_results "$results_dir"
    
    echo "$results_dir"  # Return the results directory path
}

# Function to verify results
verify_results() {
    local results_dir=$1
    
    log_info "Verifying benchmark results..."
    
    # Count CSV lines (should be > headers only)
    local csv_files="$results_dir/raw-data/*.csv"
    if ls $csv_files &> /dev/null; then
        local total_lines=$(grep -h "," $csv_files 2>/dev/null | wc -l || echo "0")
        log_info "Total data lines in CSV files: $total_lines"
        
        if [ "$total_lines" -gt "0" ]; then
            log_success "Benchmark collected real performance data"
            
            # Show sample data
            log_info "Sample performance data:"
            head -3 $csv_files | head -5
        else
            log_warning "CSV files contain only headers - benchmark may have failed to collect data"
            log_warning "This usually indicates a service connectivity issue"
        fi
    else
        log_warning "No CSV files found in results"
    fi
    
    # Check for analysis results
    if [ -d "$results_dir/analysis" ]; then
        local plot_count=$(find "$results_dir/analysis" -name "*.png" 2>/dev/null | wc -l)
        log_info "Analysis plots found: $plot_count"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -v, --verbose        Enable verbose output"
    echo "  -t, --timeout N      Set benchmark timeout in seconds (default: $TIMEOUT_BENCHMARK)"
    echo "  --skip-cleanup       Skip initial cleanup of old resources"
    echo "  --analysis-only      Run only analysis on existing benchmark results"
    echo
    echo "Examples:"
    echo "  $0                   Run complete benchmark with default settings"
    echo "  $0 -v -t 7200        Run with verbose output and 2-hour timeout"
    echo "  $0 --analysis-only   Run only the analysis step"
}

# Parse command line arguments
VERBOSE=false
SKIP_CLEANUP=false
ANALYSIS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            set -x  # Enable verbose bash execution
            shift
            ;;
        -t|--timeout)
            TIMEOUT_BENCHMARK="$2"
            shift 2
            ;;
        --skip-cleanup)
            SKIP_CLEANUP=true
            shift
            ;;
        --analysis-only)
            ANALYSIS_ONLY=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting LLM-D Benchmark Automation"
    log_info "Working directory: $SCRIPT_DIR"
    log_info "Target namespace: $NAMESPACE"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    if [ "$ANALYSIS_ONLY" = true ]; then
        log_info "Running analysis-only mode"
        run_analysis
        local results_dir=$(collect_results)
        log_success "Analysis completed. Results in: $results_dir"
        exit 0
    fi
    
    # Full benchmark run
    if [ "$SKIP_CLEANUP" = false ]; then
        cleanup_old_resources
    fi
    
    setup_resources
    run_benchmark
    run_analysis
    local results_dir=$(collect_results)
    
    echo
    log_success "🎉 Benchmark automation completed successfully!"
    log_success "📊 Results location: $results_dir"
    echo
    log_info "Next steps:"
    log_info "  - Review benchmark data in: $results_dir/raw-data/"
    log_info "  - Check analysis plots in: $results_dir/analysis/"
    log_info "  - Verify key metrics: TTFT, throughput, latency"
}

# Change to script directory
cd "$SCRIPT_DIR"

# Run main function
main "$@"