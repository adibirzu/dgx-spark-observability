#!/bin/sh
set -eu

grep -q 'disabled by default' oci/prometheus-federation.example.md
grep -q 'disabled by default' oci/log-analytics.example.md
grep -q 'match\[\]' oci/metric-allowlist.example.yml
if rg -n -i 'prompt|completion|authorization|api_key' oci/metric-allowlist.example.yml; then
  echo "OCI allowlist includes sensitive metric content" >&2
  exit 1
fi
