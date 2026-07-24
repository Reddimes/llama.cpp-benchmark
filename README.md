# llama.cpp-benchmark

A professional, high-fidelity benchmarking suite for LLM performance metrics.

## 🚀 Features

- **Real-time Master Dashboard:** A professional, non-flickering, single-table dashboard that tracks all planned iterations in real-time.
- **Advanced UI:** Uses `tput` to update rows in-place, providing a stable, high-density monitoring experience.
- **Granular Metrics:** Track `MODEL`, `TASK`, `ITER`, `STATUS`, `DUR(s)` (2 decimal precision), `TPS` (Tokens Per Second), and `TOKENS` in a clean, wide-column layout.
- **Silent Execution:** Specialist scripts operate in "Silent Mode," passing machine-readable status updates back to the orchestrator to prevent `stdout` collision and UI flicker.
- **Flexible Tasking:** Choose between Coding, Reasoning, Creative, and Math tasks, or run the full suite.

## 📋 Dashboard Layout

| Column | Width | Description |
| :--- | :--- | :--- |
| **MODEL** | 75 chars | The name of the model being benchmarked. |
| **TASK** | 12 chars | The specific reasoning/coding task type. |
| **ITER** | 5 chars | Current iteration number. |
| **STATUS** | 10 chars | Current state (`QUEUED`, `RUNNING`, `SUCCESS`, `FAILED`). |
| **DUR(s)** | 10 chars | Total execution duration (2 decimal places). |
| **TPS** | 10 chars | Tokens Per Second. |
| **TOKENS** | 8 chars | Total tokens processed. |

## 🛠️ Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/llama.cpp-benchmark.git
   cd llama.cpp-benchmark
   ```

2. Ensure you have `bash` and `curl` installed.

## ⚙️ Configuration

You can override the default LLM provider URL using the `MODEL_API_URL` environment variable.

```bash
MODEL_API_URL="http://192.168.1.50:8000/v1/models" ./run_benchmarks.sh
```

## 🚀 Usage
...
Run the orchestrator to start the benchmark suite:

```bash
chmod +x run_benchmarks.sh
./run_benchmarks.sh
```

You will be prompted to:
1. Select models from your provider.
2. Set iterations and target output size.
3. Choose task types (Coding, Reasoning, Creative, Math, or All).

## 📊 Results

All benchmark results are automatically saved in the `benchmark_logs/` directory in CSV format for further analysis.

## ⚖️ License

This project is licensed under the MIT License.
