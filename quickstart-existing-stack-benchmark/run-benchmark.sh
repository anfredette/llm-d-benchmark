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
        
        # Wait for analysis job to complete with better detection
        local analysis_job=""
        local job_wait_attempts=0
        local max_job_wait_attempts=6
        
        # Wait for analysis job to appear
        while [ $job_wait_attempts -lt $max_job_wait_attempts ] && [ -z "$analysis_job" ]; do
            analysis_job=$(kubectl get jobs -n $NAMESPACE -o name 2>/dev/null | grep analysis | head -1 | cut -d'/' -f2 || true)
            if [ -z "$analysis_job" ]; then
                log_info "Waiting for analysis job to be created... (attempt $((job_wait_attempts + 1))/$max_job_wait_attempts)"
                sleep 5
                job_wait_attempts=$((job_wait_attempts + 1))
            fi
        done
        
        if [ -n "$analysis_job" ]; then
            log_info "Found analysis job: $analysis_job"
            if wait_for_job "$analysis_job" $TIMEOUT_ANALYSIS; then
                log_success "Analysis completed successfully"
                # Additional wait to ensure all files are written
                log_info "Waiting for analysis files to be fully written..."
                sleep 10
            else
                log_warning "Analysis failed or timed out, but continuing with result collection"
            fi
        else
            log_warning "Could not find analysis job after $max_job_wait_attempts attempts, but continuing with result collection"
        fi
    else
        log_error "Analysis job file not found at $SCRIPT_DIR/analysis-job.yaml"
        exit 1
    fi
}



# Function to collect results
collect_results() {
    log_info "Setting up results retriever and collecting results..."
    
    # Create results retriever pod (using exact working commands from cheat sheet)
    if [ -f "$SCRIPT_DIR/retrieve.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/retrieve.yaml"
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
    
    # Copy analysis results (plots and stats)
    log_info "Copying analysis results..."
    if kubectl cp $NAMESPACE/results-retriever:/requests/analysis/ "$results_dir/" 2>/dev/null; then
        log_success "Analysis results copied"
    else
        log_warning "Could not copy analysis results (may not exist)"
    fi
    
    # Copy raw benchmark data - using exact working pattern from cheat sheet
    log_info "Copying raw benchmark data..."
    log_info "Checking what directories exist first:"
    kubectl exec results-retriever -n $NAMESPACE -- ls -la /requests/
    
    # Use the common directory name for Qwen models (as documented in cheat sheet)
    log_info "Copying data from directory: llm-d-3b-instruct"
    if kubectl cp $NAMESPACE/results-retriever:/requests/llm-d-3b-instruct/ "$results_dir/raw-data/"; then
        log_success "Raw benchmark data copied"
    else
        log_error "Failed to copy raw benchmark data from llm-d-3b-instruct directory"
        exit 1
    fi
    
    echo
    log_success "Results copied to: $results_dir"
    
    # Verify results (using exact commands from cheat sheet)
    log_info "Verifying successful benchmark run:"
    log_info "Total requests should be > 0:"
    grep -h "," "$results_dir/raw-data"/*.csv | wc -l
    log_info "Sample performance data:"
    head -3 "$results_dir/raw-data/LMBench_long_input_output_0.1.csv"
    
    echo "$results_dir"  # Return the results directory path
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