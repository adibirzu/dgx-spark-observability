# PRD: Engine Performance Observability

## Outcome

One authenticated Grafana workspace compares active vLLM, llama.cpp, Ollama, and LiteLLM workloads across both GB10 nodes, with GPU/RAM/host context and no data exfiltration.

## Requirements

- Scrape native private vLLM and llama.cpp metrics; enable llama.cpp `--metrics`.
- Use official DCGM Exporter and node-exporter on both GB10s.
- Collect only Ollama health and loaded-model state directly; obtain Ollama request timing/token performance only through LiteLLM.
- Show throughput, request latency, queue, cache, errors, model/load state, GPU utilization/memory/temperature/power/clocks/errors, CPU/RAM/disk/network.
- Allow only `engine`, `model_alias`, `node`, `status`, and bounded finish reason labels.
- Reject remote write, external telemetry URLs, payload-sensitive labels, and unsafe bindings in static tests.

## Acceptance

Both nodes and every enabled engine display performance or an explicit stale/unavailable condition; no metrics, logs, or dashboards contain content, user identity, headers, endpoints, or credentials.
