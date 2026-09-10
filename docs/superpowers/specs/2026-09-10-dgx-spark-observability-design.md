# DGX Spark Observability — Design

## Purpose

Provide a reusable, public-safe observability bundle for a two-node NVIDIA DGX
Spark deployment. It must show GPU and host health, local-model serving state,
and request performance in Grafana, while allowing an operator to opt into OCI
Monitoring metric export and OCI Log Analytics log collection independently.

## Non-goals

- Provision or mutate an OCI tenancy automatically.
- Commit credentials, real host names, addresses, OCIDs, prompts, API keys,
  model caches, or screenshots containing them.
- Expose exporter, Prometheus, or Grafana services to the public Internet.
- Replace the existing per-node Spark Dashboard; the bundle complements it with
  retained, cross-node observability.

## Architecture

Each Spark runs four low-overhead collectors:

1. **DCGM Exporter** exposes GPU health, temperature, power, clock, utilization,
   memory, and error signals.
2. **node_exporter** exposes host CPU, memory, filesystem, and network signals.
3. **cAdvisor** exposes Docker container lifecycle and resource signals.
4. **LLM adapters** expose vLLM native Prometheus metrics, poll Ollama's local
   API for loaded-model and timing state, and optionally scrape a LiteLLM Proxy.

Prometheus runs on the designated control Spark. It scrapes private QSFP
addresses, retains local history, evaluates alert rules, and serves a curated
`/federate` endpoint. Grafana reads only Prometheus and is the authenticated
management-LAN user interface. The existing Spark Dashboard may remain bound to
the management LAN for live, per-host debugging.

## OCI export boundary

The OCI Management Agent Prometheus data source scrapes Prometheus `/federate`
and sends selected metrics to an OCI Monitoring namespace. This is optional and
requires an operator-created Management Agent, IAM policy, install key, and
named OCI context; the project supplies templates and validation only.

OCI Log Analytics is a separate optional module. It collects redacted service
and agent logs after the operator configures an entity/source association. It
does not receive raw Prometheus time-series metrics. Prompt and completion
payloads are excluded by default.

## Repository layout

```text
compose/                 Docker Compose topology and safe env examples
prometheus/              Scrape, federation, recording, alert rules
grafana/                 Datasource provisioning and dashboard JSON
exporters/               DCGM, node, cAdvisor, Ollama/LiteLLM adapter config
oci/                     Management Agent and Log Analytics templates/docs
scripts/                 install, validate, status, redact, uninstall helpers
docs/                    architecture, security, OCI onboarding, operations
tests/                   static config and redaction tests
```

## Dashboards

### Two-node overview

- per-node reachability, exporter scrape health, SSH health, CPU/RAM/swap
- GPU memory, utilization, power, temperature, clocks, and XID/error state
- QSFP/RoCE traffic and host disk pressure
- model lifecycle state and container restarts

### vLLM serving

- API readiness, queued/running requests, prompt/decode throughput
- TTFT, inter-token and end-to-end latency
- KV-cache utilization, prefix-cache rate, preemptions, and errors
- alert annotations for container restart, rank loss, and API unavailability

### Gateway and local engines

- optional LiteLLM request/error/rate/cost metrics when a Proxy is configured
- Ollama loaded models, request load duration, prompt/decode tokens, and errors
- no request body, completion body, API key, or user identity panels

### OCI export health

- federation endpoint health and selected-series volume
- Management Agent scrape/export health when the operator enables it
- Log Analytics agent/source upload status when the operator enables it

## Security model

- Exporter endpoints bind to loopback or the private QSFP network by default.
- Prometheus binds to loopback/private network; Grafana is the sole management
  LAN interface and requires an operator-provided admin password.
- All examples use placeholders. `.env`, response files, scrape target files,
  OCI config, dashboards with real IDs, and log data are ignored by Git.
- Grafana dashboards aggregate metadata and timing, not prompts or completions.
- OCI export uses metric allow-lists and fixed dimensions to control cardinality,
  cost, and data exposure.

## Deployment flow

1. Render local environment files from `*.example` templates.
2. Deploy collectors identically on both Spark nodes.
3. Deploy Prometheus and Grafana on the control Spark.
4. Validate every exporter, scrape target, dashboard datasource, and alert rule.
5. Optionally enable the OCI Monitoring module after a named-context preflight.
6. Optionally enable Log Analytics after explicit source/entity approval.

## Failure handling

- If a rank, exporter, or endpoint fails, the overview dashboard and alerts
  identify the affected node without retaining sensitive container logs.
- A failed optional OCI module never blocks local Grafana or model serving.
- Installation validates port conflicts and rejects wildcard/public exposure
  unless an operator explicitly changes the safe defaults.
- Uninstall removes only named observability containers/volumes and leaves model
  containers untouched.

## Validation

- Static tests validate Compose, Prometheus, and Grafana JSON/YAML.
- Redaction tests reject private addresses, OCID patterns, token-like values,
  local response files, and non-example environment files.
- A status command verifies two-node scrape health and API reachability without
  transmitting model prompts.
- OCI module validation remains offline unless an explicit named context and
  operator approval are supplied.
