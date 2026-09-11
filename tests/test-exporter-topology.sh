#!/bin/sh
set -eu

file=compose/exporters.compose.example.yaml
grep -q 'METRICS_BIND_ADDRESS' "$file"
if rg -n '0\.0\.0\.0:|ports:.*[0-9]' "$file"; then
  echo "exporter topology may publish a public port" >&2
  exit 1
fi
