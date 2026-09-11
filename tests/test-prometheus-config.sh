#!/bin/sh
set -eu

config=prometheus/prometheus.example.yml
grep -q 'rule_files:' "$config"
grep -q 'targets.private.yml' "$config"
grep -q 'external_labels:' "$config"
grep -q 'federate' prometheus/web.example.yml
