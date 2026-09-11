#!/bin/sh
set -eu

grep -q 'job_name: vllm' prometheus/prometheus.example.yml
grep -q 'job_name: llamacpp' prometheus/prometheus.example.yml
grep -q 'job_name: ollama' prometheus/prometheus.example.yml
grep -q 'job_name: litellm' prometheus/prometheus.example.yml
grep -q -- '--metrics' compose/llamacpp.compose.example.yaml
grep -q 'ollama_state' exporters/ollama-state-exporter.example.sh
grep -q 'engine="vllm"' prometheus/recording.example.yml
grep -q '"title":"Local LLM Engine Performance"' grafana/dashboards/engine-performance.json
grep -q 'vllm:kv_cache_usage_perc' grafana/dashboards/engine-performance.json
if rg -n -i 'remote_write|prompt|completion|authorization|api_key|user_name|ip_address' prometheus exporters/ollama-state-exporter.example.sh; then
  echo "sensitive or external telemetry setting" >&2
  exit 1
fi
