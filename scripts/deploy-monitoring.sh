#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
env_file=${1:?usage: deploy-monitoring.sh PRIVATE_ENV_FILE}
"$root/scripts/render-monitoring.sh" "$env_file"
docker compose --env-file "$env_file" -f "$root/compose/monitoring-primary.compose.example.yaml" config >/dev/null
docker compose --env-file "$env_file" -f "$root/compose/monitoring-primary.compose.example.yaml" up -d prometheus grafana
