# Unified Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a private-by-default Grafana and Prometheus monitoring bundle for a two-node GB10 deployment, including safe deployment and rollback tooling.

**Architecture:** Both nodes run a lightweight exporter compose stack bound to the private metrics network. The primary monitoring node runs the Grafana and Prometheus stack; the peer retains the same rendered configuration as a disabled standby. A host-local deployment script applies only reviewed placeholders from ignored environment files, while static tests reject public bindings, credentials, and raw endpoint data.

**Tech Stack:** Docker Compose, Prometheus, Grafana, node_exporter, DCGM Exporter, cAdvisor, POSIX shell, jq, rg.

**Spec:** `docs/superpowers/specs/2026-09-11-unified-monitoring-deployment-design.md`

## Global Constraints

- Never commit credentials, private keys, `.env` files, raw addresses, Tailnet names, OCIDs, logs, backup archives, dashboard IDs, prompts, or completions.
- Exporters and Prometheus bind only to loopback or the private metrics network; Grafana is the sole operator-facing service.
- Grafana requires authentication and has anonymous access disabled.
- The peer monitoring configuration is synchronized but disabled; promotion is manual and must not change vLLM, LiteLLM, or model volumes.
- OCI Monitoring federation and OCI Log Analytics are independent opt-in modules and must not be required for local monitoring.
- Every service change has a validation command and a rollback step.

---

### Task 1: Add repository safety gate and configuration fixtures

**Files:**
- Create: `scripts/verify-repo.sh`
- Create: `scripts/secret-scan.sh`
- Create: `tests/test-repository-safety.sh`
- Create: `tests/fixtures/allowed.env.example`

**Interfaces:**
- Consumes: repository root path as `$1` to `scripts/verify-repo.sh`.
- Produces: exit `0` only when tracked paths and content are safe; exit `1` and the offending path otherwise.

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$root/scripts/secret-scan.sh" "$root/tests/fixtures/allowed.env.example"
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM
printf '%s\n' 'TOKEN=example-value-that-must-be-rejected' > "$fixture_dir/rejected-secret.txt"
if "$root/scripts/secret-scan.sh" "$fixture_dir/rejected-secret.txt"; then
  echo "scanner accepted a credential fixture" >&2
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-repository-safety.sh`

Expected: FAIL because `scripts/secret-scan.sh` does not exist.

- [ ] **Step 3: Write the minimal safety scripts**

```sh
#!/bin/sh
set -eu
target=${1:?usage: secret-scan.sh PATH}
if rg -n -i '(sk-[a-z0-9]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|PASSWORD=[^$]|TOKEN=[^$]|[a-z0-9-]+\.tail[a-z0-9]+\.ts\.net)' "$target"; then
  exit 1
fi
```

`verify-repo.sh` must run `git diff --check`, scan all tracked files, and reject `.env` except `.env.example`, `private/`, `backups/`, `*.key`, `*.pem`, `*.tar*`, `*.zip`, and any raw inventory directory.

- [ ] **Step 4: Verify green**

Run: `sh tests/test-repository-safety.sh && sh scripts/verify-repo.sh`

Expected: PASS; only the rejected fixture triggers the scanner.

- [ ] **Step 5: Commit**

```bash
git add scripts tests
git commit -m "feat: add observability safety verification"
```

### Task 2: Add private exporter topology and tests

**Files:**
- Create: `compose/exporters.compose.example.yaml`
- Create: `exporters/node-exporter.args.example`
- Create: `exporters/dcgm-exporter.env.example`
- Create: `exporters/metrics-proxy.example.yaml`
- Create: `tests/test-exporter-topology.sh`

**Interfaces:**
- Consumes: `METRICS_BIND_ADDRESS` and image tags from ignored `.env` at deployment time.
- Produces: host, GPU, container, vLLM, LiteLLM, and backup-status metrics that are reachable only on the private metrics network.

- [ ] **Step 1: Write the failing exposure test**

```sh
#!/bin/sh
set -eu
file=compose/exporters.compose.example.yaml
grep -q '127.0.0.1\|${METRICS_BIND_ADDRESS}' "$file"
if rg -n '0\.0\.0\.0:|ports:.*[0-9]' "$file"; then
  echo "exporter topology may publish a public port" >&2
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-exporter-topology.sh`

Expected: FAIL because the exporter topology is absent.

- [ ] **Step 3: Add minimal exporter configuration**

Use Compose services for node_exporter, DCGM Exporter, cAdvisor, and a small metrics proxy. Every listener must use `${METRICS_BIND_ADDRESS}`; the proxy has explicit allowlisted `/metrics`, `/healthz`, vLLM, LiteLLM, and backup-result metric routes. Include `read_only: true`, dropped Linux capabilities, no privileged mode, and host mounts only where the named exporter requires them.

- [ ] **Step 4: Verify green**

Run: `docker compose -f compose/exporters.compose.example.yaml config && sh tests/test-exporter-topology.sh`

Expected: Compose renders with a local example environment and the exposure test passes.

- [ ] **Step 5: Commit**

```bash
git add compose exporters tests/test-exporter-topology.sh
git commit -m "feat: add private exporter topology"
```

### Task 3: Add Prometheus scrape, rule, and federation configuration

**Files:**
- Create: `prometheus/prometheus.example.yml`
- Create: `prometheus/alerts.example.yml`
- Create: `prometheus/recording.example.yml`
- Create: `prometheus/web.example.yml`
- Create: `tests/test-prometheus-config.sh`

**Interfaces:**
- Consumes: ignored `prometheus/targets.private.yml` rendered from the reviewed example.
- Produces: local retained metrics, target health, recording rules, alert rules, and an allowlisted `/federate` endpoint for optional OCI scraping.

- [ ] **Step 1: Write the failing configuration test**

```sh
#!/bin/sh
set -eu
config=prometheus/prometheus.example.yml
grep -q 'rule_files:' "$config"
grep -q 'targets.private.yml' "$config"
grep -q 'external_labels:' "$config"
grep -q 'federate' prometheus/web.example.yml
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-prometheus-config.sh`

Expected: FAIL because the Prometheus files do not exist.

- [ ] **Step 3: Add minimal Prometheus files**

Create scrape jobs named `node`, `gpu`, `containers`, `vllm`, `litellm`, and `backup`. Define recording rules for request error ratio, GPU-memory pressure, and backup age. Define alerts for target down, model unavailable, high GPU temperature, storage pressure, and stale backup. Restrict federation matching to those named metric families; do not include log payloads or high-cardinality request labels.

- [ ] **Step 4: Verify green**

Run: `promtool check config prometheus/prometheus.example.yml && promtool check rules prometheus/alerts.example.yml prometheus/recording.example.yml && sh tests/test-prometheus-config.sh`

Expected: all config and rule checks pass.

- [ ] **Step 5: Commit**

```bash
git add prometheus tests/test-prometheus-config.sh
git commit -m "feat: add Prometheus monitoring contract"
```

### Task 4: Add Grafana provisioning and four dashboard contracts

**Files:**
- Create: `grafana/provisioning/datasources/prometheus.example.yaml`
- Create: `grafana/provisioning/dashboards/dashboards.example.yaml`
- Create: `grafana/dashboards/fleet-overview.json`
- Create: `grafana/dashboards/serving-path.json`
- Create: `grafana/dashboards/gateway-path.json`
- Create: `grafana/dashboards/recovery-export.json`
- Create: `tests/test-grafana-dashboards.sh`

**Interfaces:**
- Consumes: Prometheus datasource name `Prometheus` and dashboard variables `node` and `interval`.
- Produces: four provisioned dashboards that state no-data, stale, and down behavior rather than rendering missing series as zero.

- [ ] **Step 1: Write the failing dashboard test**

```sh
#!/bin/sh
set -eu
for dashboard in grafana/dashboards/*.json; do
  jq -e '.dashboard.title and .dashboard.templating.list[] | select(.name == "node")' "$dashboard" >/dev/null
  jq -e '.dashboard.panels | length > 0' "$dashboard" >/dev/null
done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-grafana-dashboards.sh`

Expected: FAIL because no dashboard JSON exists.

- [ ] **Step 3: Add dashboard JSON and provisioning**

Fleet overview begins with target health, model readiness, GPU/unified-memory pressure, storage pressure, and backup freshness. Serving path shows request load, throughput, latency, cache behavior, and restart/rank annotations. Gateway path shows request classification, latency, and upstream health without request body data. Recovery/export shows backup status, retention, and disabled/healthy OCI-module state. Use a node variable and visible no-data panels in every dashboard.

- [ ] **Step 4: Verify green**

Run: `sh tests/test-grafana-dashboards.sh && jq empty grafana/dashboards/*.json`

Expected: all four dashboard contracts and JSON documents validate.

- [ ] **Step 5: Commit**

```bash
git add grafana tests/test-grafana-dashboards.sh
git commit -m "feat: add unified Grafana dashboards"
```

### Task 5: Add authenticated primary stack, standby rendering, and operations scripts

**Files:**
- Create: `compose/monitoring-primary.compose.example.yaml`
- Create: `compose/monitoring-standby.compose.example.yaml`
- Create: `scripts/render-monitoring.sh`
- Create: `scripts/deploy-monitoring.sh`
- Create: `scripts/status-monitoring.sh`
- Create: `scripts/rollback-monitoring.sh`
- Create: `docs/operations.md`
- Create: `tests/test-deployment-safety.sh`

**Interfaces:**
- Consumes: an ignored mode-0600 `.env`, ignored private targets file, and protected backup location supplied by an operator.
- Produces: a primary Grafana/Prometheus stack, an inactive standby rendering, explicit authentication checks, and a named-only rollback procedure.

- [ ] **Step 1: Write the failing deployment-safety test**

```sh
#!/bin/sh
set -eu
primary=compose/monitoring-primary.compose.example.yaml
grep -q 'GF_AUTH_ANONYMOUS_ENABLED=false' "$primary"
grep -q '127.0.0.1\|${GRAFANA_BIND_ADDRESS}' "$primary"
if rg -n '0\.0\.0\.0:' "$primary"; then
  echo "primary compose may expose Grafana publicly" >&2
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-deployment-safety.sh`

Expected: FAIL because the primary compose file is absent.

- [ ] **Step 3: Add minimal operational tooling**

The render script must refuse missing files, permissive `.env` modes, wildcard bindings, and unreviewed target paths. The deploy script runs `docker compose config`, starts only the named monitoring services, waits for Prometheus and Grafana readiness, checks rejected and accepted Grafana authentication behavior without printing a password, and verifies no direct exporter/Prometheus listener is reachable from the management LAN. The rollback script stops only the named stack and restores only an operator-supplied, checksum-verified protected archive.

- [ ] **Step 4: Verify green**

Run: `sh tests/test-deployment-safety.sh && sh scripts/verify-repo.sh`

Expected: safe bindings, disabled anonymous access, and repository verification pass.

- [ ] **Step 5: Commit**

```bash
git add compose scripts docs/operations.md tests/test-deployment-safety.sh
git commit -m "feat: add safe monitoring deployment tooling"
```

### Task 6: Add optional OCI templates and full acceptance suite

**Files:**
- Create: `oci/prometheus-federation.example.md`
- Create: `oci/log-analytics.example.md`
- Create: `oci/metric-allowlist.example.yml`
- Create: `tests/test-oci-boundaries.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: a named OCI context and protected credentials only after explicit operator enablement.
- Produces: documentation and allowlists that make OCI modules separately testable without changing local monitoring.

- [ ] **Step 1: Write the failing OCI-boundary test**

```sh
#!/bin/sh
set -eu
grep -q 'disabled by default' oci/prometheus-federation.example.md
grep -q 'disabled by default' oci/log-analytics.example.md
grep -q 'match\[\]' oci/metric-allowlist.example.yml
if rg -n 'prompt|completion|authorization|api_key' oci/metric-allowlist.example.yml; then
  echo "OCI allowlist includes sensitive metric content" >&2
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-oci-boundaries.sh`

Expected: FAIL because the OCI templates are absent.

- [ ] **Step 3: Add OCI templates and operator guide**

Document Management Agent federation preflight, metric allowlists, fixed dimensions, and independent redacted Log Analytics onboarding. Update the README with the local-first deployment order, no-public-exposure statement, full test command, and recovery reference.

- [ ] **Step 4: Run full acceptance**

Run: `sh tests/test-repository-safety.sh && sh tests/test-exporter-topology.sh && sh tests/test-prometheus-config.sh && sh tests/test-grafana-dashboards.sh && sh tests/test-deployment-safety.sh && sh tests/test-oci-boundaries.sh && sh scripts/verify-repo.sh && git diff --check`

Expected: every safety, configuration, dashboard, deployment, and OCI boundary test passes with no whitespace errors.

- [ ] **Step 5: Commit**

```bash
git add oci README.md tests/test-oci-boundaries.sh
git commit -m "docs: add optional OCI monitoring integration"
```
