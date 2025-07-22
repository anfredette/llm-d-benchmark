# LLM-D Benchmark Cheat Sheet

## 🚀 Quick Run (Same Qwen Model)

```bash
# 1. Set up environment
cd ~/llm-d-benchmark/quickstart-existing-stack-benchmark

# 2. Clean up any old jobs
kubectl delete jobs --all -n llm-d-benchmark

# 3. Run the benchmark
kubectl apply -f benchmark-job.yaml

# 4. Monitor progress
kubectl logs -f job/benchmark-run -n llm-d-benchmark

# 5. Run analysis when benchmark completes
kubectl apply -f analysis-job.yaml

# 6. Copy results
mkdir -p ~/benchmark-results-$(date +%Y%m%d-%H%M%S)
kubectl cp llm-d-benchmark/results-retriever:/requests/analysis/ ~/benchmark-results-$(date +%Y%m%d-%H%M%S)/
kubectl cp llm-d-benchmark/results-retriever:/requests/llm-d-qwen-0-6b/ ~/benchmark-results-$(date +%Y%m%d-%H%M%S)/raw-data/
```

## 🔄 For Different Models

### Step 1: Update Model Configuration

Edit `resources/benchmark-workload-configmap.yaml`:
```yaml
data:
  llmdbench_workload.yaml: |
    model_name: "YOUR_MODEL_NAME"  # e.g., "microsoft/DialoGPT-medium"
    scenarios: "long-input"
    qps_values: "0.1 0.25 0.5"     # Adjust QPS as needed
```

### Step 2: Update Environment Variables

Edit `benchmark-job.yaml` environment section:
```yaml
env:
- name: LLMDBENCH_HARNESS_STACK_ENDPOINT_URL
  value: "http://YOUR-SERVICE-NAME.YOUR-NAMESPACE.svc.cluster.local:PORT"
- name: LLMDBENCH_HARNESS_STACK_NAME
  value: "your-model-stack-name"    # Used for result folder naming
```

### Step 3: Find Your Service Details

```bash
# Find your model's service
kubectl get svc -n YOUR_MODEL_NAMESPACE

# Test DNS resolution from benchmark namespace
kubectl run dns-test --image=busybox --rm -i --restart=Never -n llm-d-benchmark \
  -- nslookup YOUR-SERVICE-NAME.YOUR-NAMESPACE.svc.cluster.local
```

## 📊 Key Configuration Files

### `resources/benchmark-env.yaml`
- Sets benchmark environment variables
- **Key variable:** `LLMDBENCH_HARNESS_STACK_ENDPOINT_URL`

### `resources/benchmark-workload-configmap.yaml`  
- Defines model name and test scenarios
- **Key fields:** `model_name`, `qps_values`

### `benchmark-job.yaml`
- Main benchmark job definition
- **Key sections:** `env` variables, `volumeMounts`

## 🛠️ Troubleshooting

### Issue: "Connection error" or DNS resolution fails
```bash
# Check if service exists and get correct name
kubectl get svc -n YOUR_NAMESPACE | grep gateway

# Test DNS from benchmark namespace  
kubectl run dns-test --image=busybox --rm -i --restart=Never -n llm-d-benchmark \
  -- nslookup YOUR-SERVICE.YOUR-NAMESPACE.svc.cluster.local
```

### Issue: "Job already exists" 
```bash
# Clean up old jobs
kubectl delete job benchmark-run lmbenchmark-evaluate-* -n llm-d-benchmark
```

### Issue: Empty result files (headers only)
- Check model service is responding: `kubectl logs -f job/lmbenchmark-evaluate-* -n llm-d-benchmark`
- Verify model name matches what's served at `/v1/models` endpoint

### Issue: Permission denied when moving files
- This is expected - the evaluation job completes successfully, orchestrator fails on file moves
- Results are still valid in `/requests/your-stack-name/` directory

## 📋 Verification Commands

```bash
# Check job status
kubectl get jobs -n llm-d-benchmark

# Check pods
kubectl get pods -n llm-d-benchmark  

# Verify results were collected
kubectl exec results-retriever -n llm-d-benchmark -- ls -la /requests/YOUR-STACK-NAME/

# Check result file sizes (should be > 100 bytes if data collected)
kubectl exec results-retriever -n llm-d-benchmark -- ls -lh /requests/YOUR-STACK-NAME/

# Preview results
kubectl exec results-retriever -n llm-d-benchmark -- head /requests/YOUR-STACK-NAME/LMBench_long_input_output_0.1.csv
```

## ⚙️ Advanced Configuration

### Custom QPS Values
Edit the `qps_values` in workload config:
```yaml
qps_values: "0.05 0.1 0.2 0.5 1.0"  # Test more load points
```

### Different Test Scenarios  
```yaml
scenarios: "short-input"     # For shorter prompts
# or
scenarios: "long-input"      # For long prompts (default)
```

### Custom Test Duration
Add to workload config:
```yaml
test_duration: "120"         # 120 seconds per QPS level
num_users: "20"              # Number of concurrent users
```

## 🎯 Expected Results

- **CSV files** with actual data (>1KB each if successful)
- **Analysis plots**: latency_analysis.png, throughput_analysis.png  
- **Statistics**: Performance summary in stats.txt
- **Key metrics**: TTFT (Time to First Token), generation time, tokens/second 