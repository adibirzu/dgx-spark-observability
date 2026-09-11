#!/bin/sh
set -eu

for dashboard in grafana/dashboards/*.json; do
  jq -e '.dashboard.title and (.dashboard.templating.list[] | select(.name == "node"))' "$dashboard" >/dev/null
  jq -e '.dashboard.panels | length > 0' "$dashboard" >/dev/null
done
