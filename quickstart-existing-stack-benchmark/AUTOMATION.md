# LLM-D Benchmark Automation

This directory contains automation scripts that simplify running benchmarks against existing LLM-D stacks.

## 🚀 Quick Start

### 1. Configure Your Benchmark (Interactive)
```bash
./configure-benchmark.sh interactive
```

This will walk you through setting up:
- Service endpoint URL
- Model name
- Test scenarios
- QPS (queries per second) values

### 2. Run the Complete Benchmark
```bash
./run-benchmark.sh
```

This fully automated script will:
- ✅ Clean up old resources
- ✅ Set up the benchmark environment
- ✅ Apply DNS workarounds
- ✅ Execute the benchmark
- ✅ Run analysis
- ✅ Collect results to local directory

Results will be saved to `~/benchmark-results-TIMESTAMP/`

## 📋 Configuration Scripts

### Show Current Configuration
```bash
./configure-benchmark.sh show
```

### Update Service Endpoint
```bash
./configure-benchmark.sh update-service \
  --url "http://your-service.namespace.svc.cluster.local:8000" \
  --stack-name "my-model-v1"
```

### Update Model Settings
```bash
./configure-benchmark.sh update-model \
  --model-name "microsoft/DialoGPT-medium" \
  --scenarios "long-input" \
  --qps-values "0.1 0.25 0.5"
```

### Discover Services in Your Cluster
```bash
./configure-benchmark.sh discover --namespace llm-d
```

### Test Service Connectivity
```bash
./configure-benchmark.sh test --url "http://your-service:8000"
```

## 🎯 Benchmark Execution Options

### Basic Run
```bash
./run-benchmark.sh
```

### Verbose Output
```bash
./run-benchmark.sh -v
```

### Custom Timeout (2 hours)
```bash
./run-benchmark.sh -t 7200
```

### Analysis Only (if benchmark already completed)
```bash
./run-benchmark.sh --analysis-only
```

### Skip Initial Cleanup
```bash
./run-benchmark.sh --skip-cleanup
```

## 📊 Understanding Results

After a successful run, results are organized as:

```
~/benchmark-results-TIMESTAMP/
├── analysis/                    # Generated plots and statistics
│   ├── latency_analysis.png
│   ├── throughput_analysis.png
│   └── stats.txt
└── raw-data/                   # Raw benchmark data
    ├── LMBench_long_input_output_0.1.csv
    ├── LMBench_long_input_output_0.25.csv
    └── LMBench_long_input_output_0.5.csv
```

### Key Metrics in Results

The CSV files contain these important performance metrics:

| Metric | Description | vLLM Equivalent |
|--------|-------------|-----------------|
| `ttft` | Time to First Token (ms) | `mean_ttft_ms` |
| `generation_time` | Time to generate all tokens | Total generation latency |
| `generation_tokens` | Number of tokens generated | Output token count |
| `prompt_tokens` | Input tokens processed | Input token count |
| `finish_time` - `launch_time` | Total request time | End-to-end latency |

## 🛠️ Common Usage Patterns

### For Different Models
1. Configure for your model:
   ```bash
   ./configure-benchmark.sh update-model --model-name "your/model-name"
   ```

2. Update service endpoint:
   ```bash
   ./configure-benchmark.sh update-service --url "http://your-service:8000"
   ```

3. Run benchmark:
   ```bash
   ./run-benchmark.sh
   ```

### For Load Testing
Use higher QPS values:
```bash
./configure-benchmark.sh update-model --qps-values "0.5 1.0 2.0 5.0"
```

### For Latency Testing
Use lower QPS values:
```bash
./configure-benchmark.sh update-model --qps-values "0.05 0.1 0.2"
```

### For Different Prompt Lengths
```bash
# Short prompts
./configure-benchmark.sh update-model --scenarios "short-input"

# Long prompts  
./configure-benchmark.sh update-model --scenarios "long-input"
```

## 🚨 Troubleshooting

### Issue: "Service not found" or DNS errors
```bash
# Check available services
./configure-benchmark.sh discover --namespace YOUR_NAMESPACE

# Test connectivity
./configure-benchmark.sh test --url "http://your-service:8000"
```

### Issue: Empty result files
This usually means the service wasn't accessible. Check:
1. Service is running: `kubectl get pods -n YOUR_NAMESPACE`
2. Service endpoint is correct
3. DNS workaround is applied (automatic in run-benchmark.sh)

### Issue: Job timeout
Increase timeout for large models:
```bash
./run-benchmark.sh -t 7200  # 2 hours
```

### Issue: Permission errors
The automation handles most permission issues, but if you see file access errors:
```bash
kubectl delete namespace llm-d-benchmark
./run-benchmark.sh  # Will recreate everything
```

## 🔧 Advanced Configuration

### Custom Test Scenarios
Edit `resources/benchmark-workload-configmap.yaml` directly for:
- Custom test duration
- Number of concurrent users
- Custom prompt datasets

### Multiple Model Testing
Run benchmarks sequentially:
```bash
for model in "model1" "model2" "model3"; do
  ./configure-benchmark.sh update-model --model-name "$model"
  ./run-benchmark.sh
done
```

### Continuous Monitoring
Set up a cron job for regular benchmarking:
```bash
# Add to crontab for daily benchmarks at 2 AM
0 2 * * * cd /path/to/llm-d-benchmark/quickstart-existing-stack-benchmark && ./run-benchmark.sh
```

## 📈 Interpreting Performance Data

### Good Performance Indicators
- TTFT < 100ms for real-time applications
- Consistent generation times across requests
- High tokens/second throughput
- Low variance in latency metrics

### Performance Bottleneck Signs
- TTFT increasing significantly with load
- High variance in generation times
- Throughput plateauing at low QPS values
- Service timeout errors at moderate load

The automation scripts handle all the complexity of the benchmark setup, so you can focus on analyzing the performance characteristics of your LLM deployment!