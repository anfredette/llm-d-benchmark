#!/bin/bash

# Example: Complete LLM-D Benchmark Workflow
# This script demonstrates how to configure and run a benchmark in one go

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 LLM-D Benchmark - Complete Example Workflow${NC}"
echo

# Example configuration - modify these values for your setup
SERVICE_URL="http://llm-d-inference-gateway-istio.llm-d.svc.cluster.local:80"
STACK_NAME="llm-d-qwen-0-6b"
MODEL_NAME="Qwen/Qwen3-0.6B"
QPS_VALUES="0.5 1.0 5.0 10.0"
SCENARIOS="long-input"
# Alternative scenario options:
# SCENARIOS="short-input"    # For shorter input/output tests
# SCENARIOS="sharegpt"       # For ShareGPT dataset tests

echo -e "${GREEN}Step 1: Configuring benchmark parameters...${NC}"
echo "  Service URL: $SERVICE_URL"
echo "  Stack Name: $STACK_NAME"
echo "  Model Name: $MODEL_NAME"
echo "  Test Scenarios: $SCENARIOS"
echo "  QPS Values: $QPS_VALUES"
echo

# Configure the benchmark
$SCRIPT_DIR/configure-benchmark.sh update-service \
  --url "$SERVICE_URL" \
  --stack-name "$STACK_NAME"

$SCRIPT_DIR/configure-benchmark.sh update-model \
  --model-name "$MODEL_NAME" \
  --scenarios "$SCENARIOS" \
  --qps-values "$QPS_VALUES"

echo -e "${GREEN}Step 2: Running complete benchmark...${NC}"
echo

# Run the benchmark with verbose output
$SCRIPT_DIR/run-benchmark.sh -v

echo
echo -e "${GREEN}✅ Complete workflow finished!${NC}"
echo -e "${BLUE}💡 Tip: Check the results directory printed above for performance data${NC}"