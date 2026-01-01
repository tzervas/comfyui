# Benchmarking

This repo is designed for **real deployments** (homelab ingress + desktop GPU worker). Benchmark results are inherently environment-specific.

## Ollama latency benchmark (via ingress)

Runs multiple `POST /ollama/api/generate` requests and reports average latency.

- Homelab ingress:

```bash
./tools/tests/benchmark-ollama.sh --env-file .env.homelab --iterations 10
```

- Single-node GPU:

```bash
./tools/tests/benchmark-ollama.sh --env-file .env.single-node-gpu --iterations 10
```

Notes:
- If the model is not pulled yet, `generate` may fail; pull a model first (or set `OLLAMA_TEST_MODEL` in your env file).
- For more stable results, run multiple rounds and discard the first run (warm caches).

## Capture results

Recommended minimal capture for a report:

- Host CPU model + RAM
- GPU model + driver version
- `docker version` and `docker compose version`
- Model name tested
- Iterations and average latency
