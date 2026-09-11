#!/bin/sh
set -eu

env_file=${1:?usage: render-monitoring.sh PRIVATE_ENV_FILE}
case "$env_file" in */private/*|*/.env) ;; *) echo "environment file must be protected" >&2; exit 1;; esac
mode=$(stat -c '%a' "$env_file")
[ "$mode" = 600 ] || { echo "environment file must have mode 600" >&2; exit 1; }
grep -q '^GRAFANA_BIND_ADDRESS=' "$env_file" || { echo "missing Grafana bind address" >&2; exit 1; }
if grep -q '^GRAFANA_BIND_ADDRESS=0\.0\.0\.0' "$env_file"; then echo "public Grafana binding refused" >&2; exit 1; fi
