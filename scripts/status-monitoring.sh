#!/bin/sh
set -eu

docker compose -f "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/compose/monitoring-primary.compose.example.yaml" ps
