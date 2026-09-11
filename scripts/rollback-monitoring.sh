#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
env_file=${1:?usage: rollback-monitoring.sh PRIVATE_ENV_FILE}
docker compose --env-file "$env_file" -f "$root/compose/monitoring-primary.compose.example.yaml" down
