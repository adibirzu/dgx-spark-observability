#!/bin/sh
set -eu

primary=compose/monitoring-primary.compose.example.yaml
grep -q 'GF_AUTH_ANONYMOUS_ENABLED=false' "$primary"
grep -q 'GRAFANA_BIND_ADDRESS' "$primary"
if rg -n '0\.0\.0\.0:' "$primary"; then
  echo "primary compose may expose Grafana publicly" >&2
  exit 1
fi
