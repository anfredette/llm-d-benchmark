#!/bin/bash

# LLM-D Benchmark Configuration Script
# Helps configure benchmark parameters for different models and services

set -e

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to show current configuration
show_current_config() {
    log_info "Current Benchmark Configuration:"
    echo
    
    if [ -f "$SCRIPT_DIR/resources/benchmark-env.yaml" ]; then
        echo "Environment Configuration:"
        grep -E "LLMDBENCH_HARNESS_STACK_" "$SCRIPT_DIR/resources/benchmark-env.yaml" | sed 's/^  /  /'
        echo
    fi
    
    if [ -f "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml" ]; then
        echo "Workload Configuration:"
        grep -E "model_name|scenarios|qps_values" "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml" | sed 's/^    /  /'
        echo
    fi
}

# Function to update service endpoint
update_service_endpoint() {
    local service_url=$1
    local stack_name=$2
    
    log_info "Updating service endpoint configuration..."
    
    # Update environment config
    if [ -f "$SCRIPT_DIR/resources/benchmark-env.yaml" ]; then
        # Create backup
        cp "$SCRIPT_DIR/resources/benchmark-env.yaml" "$SCRIPT_DIR/resources/benchmark-env.yaml.bak"
        
        # Update the service URL
        sed -i "s|LLMDBENCH_HARNESS_STACK_ENDPOINT_URL:.*|LLMDBENCH_HARNESS_STACK_ENDPOINT_URL: \"$service_url\"|" "$SCRIPT_DIR/resources/benchmark-env.yaml"
        
        # Update stack name if provided
        if [ -n "$stack_name" ]; then
            sed -i "s|LLMDBENCH_HARNESS_STACK_NAME:.*|LLMDBENCH_HARNESS_STACK_NAME: \"$stack_name\"|" "$SCRIPT_DIR/resources/benchmark-env.yaml"
        fi
        
        log_success "Service endpoint updated"
    else
        log_error "Environment configuration file not found"
        exit 1
    fi
}

# Function to update model configuration
update_model_config() {
    local model_name=$1
    local scenarios=$2
    local qps_values=$3
    
    log_info "Updating model configuration..."
    
    if [ -f "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml" ]; then
        # Create backup
        cp "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml" "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml.bak"
        
        # Update model name
        if [ -n "$model_name" ]; then
            sed -i "s|model_name:.*|model_name: \"$model_name\"|" "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml"
        fi
        
        # Update scenarios
        if [ -n "$scenarios" ]; then
            sed -i "s|scenarios:.*|scenarios: \"$scenarios\"|" "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml"
        fi
        
        # Update QPS values
        if [ -n "$qps_values" ]; then
            sed -i "s|qps_values:.*|qps_values: \"$qps_values\"|" "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml"
        fi
        
        log_success "Model configuration updated"
    else
        log_error "Workload configuration file not found"
        exit 1
    fi
}

# Function to discover services in cluster
discover_services() {
    local namespace=$1
    
    log_info "Discovering services in namespace '$namespace'..."
    
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        log_error "Namespace '$namespace' not found"
        return 1
    fi
    
    echo
    echo "Available services:"
    kubectl get svc -n "$namespace" -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,PORTS:.spec.ports[*].port
    echo
    
    echo "Suggested service URLs:"
    kubectl get svc -n "$namespace" -o custom-columns=NAME:.metadata.name,PORTS:.spec.ports[*].port --no-headers | while read name port; do
        if [ -n "$port" ] && [ "$port" != "<none>" ]; then
            echo "  http://$name.$namespace.svc.cluster.local:$port"
        fi
    done
}

# Function to test service connectivity
test_service() {
    local service_url=$1
    
    log_info "Testing service connectivity: $service_url"
    
    # Create a test pod to check connectivity
    kubectl run connectivity-test --image=curlimages/curl --rm -i --restart=Never -n llm-d-benchmark \
        --command -- curl -s --connect-timeout 10 "$service_url/v1/models" > /tmp/test_result 2>&1 &
    
    local curl_pid=$!
    sleep 15
    
    if kill -0 $curl_pid 2>/dev/null; then
        kill $curl_pid
        log_warning "Service test timed out - service may be slow to respond"
    else
        wait $curl_pid
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            log_success "Service is accessible"
            echo "Available models:"
            cat /tmp/test_result | head -10
        else
            log_error "Service is not accessible"
            cat /tmp/test_result
        fi
    fi
    
    rm -f /tmp/test_result
}

# Function for interactive configuration
interactive_config() {
    log_info "Interactive Benchmark Configuration"
    echo
    
    # Get current values
    local current_url=$(grep "LLMDBENCH_HARNESS_STACK_ENDPOINT_URL:" "$SCRIPT_DIR/resources/benchmark-env.yaml" 2>/dev/null | cut -d'"' -f2 || echo "")
    local current_stack=$(grep "LLMDBENCH_HARNESS_STACK_NAME:" "$SCRIPT_DIR/resources/benchmark-env.yaml" 2>/dev/null | cut -d'"' -f2 || echo "")
    local current_model=$(grep "model_name:" "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml" 2>/dev/null | cut -d'"' -f2 || echo "")
    local current_scenarios=$(grep "scenarios:" "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml" 2>/dev/null | cut -d'"' -f2 || echo "")
    local current_qps=$(grep "qps_values:" "$SCRIPT_DIR/resources/benchmark-workload-configmap.yaml" 2>/dev/null | cut -d'"' -f2 || echo "")
    
    echo "Current configuration:"
    echo "  Service URL: $current_url"
    echo "  Stack Name: $current_stack"
    echo "  Model Name: $current_model"
    echo "  Scenarios: $current_scenarios"
    echo "  QPS Values: $current_qps"
    echo
    
    # Service URL
    read -p "Enter service URL [$current_url]: " new_url
    new_url=${new_url:-$current_url}
    
    # Stack name
    read -p "Enter stack name for results [$current_stack]: " new_stack
    new_stack=${new_stack:-$current_stack}
    
    # Model name
    read -p "Enter model name [$current_model]: " new_model
    new_model=${new_model:-$current_model}
    
    # Scenarios
    echo
    echo "Available scenarios: short-input, long-input"
    read -p "Enter scenarios [$current_scenarios]: " new_scenarios
    new_scenarios=${new_scenarios:-$current_scenarios}
    
    # QPS values
    echo
    echo "Example QPS values: '0.1 0.25 0.5' or '0.05 0.1 0.2 0.5 1.0'"
    read -p "Enter QPS values [$current_qps]: " new_qps
    new_qps=${new_qps:-$current_qps}
    
    # Apply changes
    update_service_endpoint "$new_url" "$new_stack"
    update_model_config "$new_model" "$new_scenarios" "$new_qps"
    
    echo
    log_success "Configuration updated successfully!"
    
    # Ask if user wants to test the service
    read -p "Test service connectivity? (y/N): " test_choice
    if [[ $test_choice =~ ^[Yy]$ ]]; then
        test_service "$new_url"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  show                 Show current configuration"
    echo "  interactive          Interactive configuration mode"
    echo "  update-service       Update service endpoint"
    echo "  update-model         Update model configuration"
    echo "  discover             Discover services in a namespace"
    echo "  test                 Test service connectivity"
    echo
    echo "Options for update-service:"
    echo "  --url URL            Service URL"
    echo "  --stack-name NAME    Stack name for results"
    echo
    echo "Options for update-model:"
    echo "  --model-name NAME    Model name"
    echo "  --scenarios LIST     Test scenarios (short-input, long-input)"
    echo "  --qps-values LIST    QPS values (space-separated)"
    echo
    echo "Options for discover:"
    echo "  --namespace NAME     Kubernetes namespace to search"
    echo
    echo "Options for test:"
    echo "  --url URL            Service URL to test"
    echo
    echo "Examples:"
    echo "  $0 show"
    echo "  $0 interactive"
    echo "  $0 update-service --url 'http://my-service.default.svc.cluster.local:8000' --stack-name 'my-model-v1'"
    echo "  $0 update-model --model-name 'microsoft/DialoGPT-medium' --scenarios 'long-input' --qps-values '0.1 0.25 0.5'"
    echo "  $0 discover --namespace llm-d"
    echo "  $0 test --url 'http://my-service.default.svc.cluster.local:8000'"
}

# Parse command line arguments
case "${1:-}" in
    show)
        show_current_config
        ;;
    interactive)
        interactive_config
        ;;
    update-service)
        shift
        URL=""
        STACK_NAME=""
        
        while [[ $# -gt 0 ]]; do
            case $1 in
                --url)
                    URL="$2"
                    shift 2
                    ;;
                --stack-name)
                    STACK_NAME="$2"
                    shift 2
                    ;;
                *)
                    log_error "Unknown option: $1"
                    show_usage
                    exit 1
                    ;;
            esac
        done
        
        if [ -z "$URL" ]; then
            log_error "Service URL is required"
            exit 1
        fi
        
        update_service_endpoint "$URL" "$STACK_NAME"
        ;;
    update-model)
        shift
        MODEL_NAME=""
        SCENARIOS=""
        QPS_VALUES=""
        
        while [[ $# -gt 0 ]]; do
            case $1 in
                --model-name)
                    MODEL_NAME="$2"
                    shift 2
                    ;;
                --scenarios)
                    SCENARIOS="$2"
                    shift 2
                    ;;
                --qps-values)
                    QPS_VALUES="$2"
                    shift 2
                    ;;
                *)
                    log_error "Unknown option: $1"
                    show_usage
                    exit 1
                    ;;
            esac
        done
        
        update_model_config "$MODEL_NAME" "$SCENARIOS" "$QPS_VALUES"
        ;;
    discover)
        shift
        NAMESPACE=""
        
        while [[ $# -gt 0 ]]; do
            case $1 in
                --namespace)
                    NAMESPACE="$2"
                    shift 2
                    ;;
                *)
                    log_error "Unknown option: $1"
                    show_usage
                    exit 1
                    ;;
            esac
        done
        
        if [ -z "$NAMESPACE" ]; then
            log_error "Namespace is required"
            exit 1
        fi
        
        discover_services "$NAMESPACE"
        ;;
    test)
        shift
        TEST_URL=""
        
        while [[ $# -gt 0 ]]; do
            case $1 in
                --url)
                    TEST_URL="$2"
                    shift 2
                    ;;
                *)
                    log_error "Unknown option: $1"
                    show_usage
                    exit 1
                    ;;
            esac
        done
        
        if [ -z "$TEST_URL" ]; then
            log_error "Service URL is required"
            exit 1
        fi
        
        test_service "$TEST_URL"
        ;;
    ""|--help|-h)
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac