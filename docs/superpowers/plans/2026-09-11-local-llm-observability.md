# Local LLM Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a reproducible private two-GB10 Qwen3.8 Flash-Next platform with LiteLLM, Langfuse, Prometheus, Grafana, and a Claude Code Max route.

**Architecture:** vLLM remains the private distributed model backend. LiteLLM provides separate local-Qwen and Claude-Max aliases, with narrowly scoped OAuth-header forwarding for only the Anthropic alias. A local Langfuse dependency stack receives metadata-only traces; Prometheus/Grafana monitor all services without request content or credentials.

**Tech Stack:** Docker Compose, vLLM, LiteLLM Proxy, Langfuse, PostgreSQL, ClickHouse, Redis, Prometheus, Grafana, POSIX shell, jq, rg.

**Spec:** `docs/superpowers/specs/2026-09-11-local-llm-observability-design.md`

## Global Constraints

- Never commit credentials, OAuth tokens, API keys, private host inventory, prompts, completions, request bodies, database volumes, or generated runtime files.
- All generated secret files are below `private/`, ignored by Git, and mode `0600`; all state volumes remain outside Git.
- Qwen3.8 Flash-Next is the default local model alias; LiteLLM must reach vLLM only over the private cluster network.
- Claude Max OAuth header forwarding is enabled only for the `anthropic-claude` model group.
- Langfuse prompt/completion capture is disabled by default; observability labels exclude raw user, address, authorization, key, prompt, completion, and arbitrary request-ID data.
- Grafana, Langfuse, LiteLLM, exporters, and Prometheus bind to loopback or the declared private networks, never `0.0.0.0`.
- Deployment and rollback affect only named local-LLM/observability containers and never model cache or unrelated containers.

---

### Task 1: Add safe local runtime bootstrap and configuration contract

**Files:**
- Create: `runtime/local-llm.env.example`
- Create: `runtime/litellm-config.example.yaml`
- Create: `runtime/langfuse.env.example`
- Create: `scripts/bootstrap-local-llm.sh`
- Create: `tests/test-local-runtime-safety.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: an operator-selected `private/runtime.env` path.
- Produces: mode-0600 runtime environment plus `private/litellm-client.env`, each populated with generated secrets but never printed.

- [ ] **Step 1: Write the failing safety test**

```sh
#!/bin/sh
set -eu
grep -q '^QWEN_MODEL=Qwen/Qwen3.8-Flash-Next' runtime/local-llm.env.example
grep -q 'forward_client_headers_to_llm_api:' runtime/litellm-config.example.yaml
grep -q 'anthropic-claude' runtime/litellm-config.example.yaml
if rg -n '0\.0\.0\.0|LANGFUSE_CAPTURE_CONTENT=true' runtime; then exit 1; fi
if rg -n 'forward_client_headers_to_llm_api: true' runtime/litellm-config.example.yaml; then exit 1; fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh tests/test-local-runtime-safety.sh`

Expected: FAIL because the local runtime templates do not yet exist.

- [ ] **Step 3: Implement the minimal templates and bootstrap script**

```sh
umask 077
mkdir -p "$private_dir"
test -e "$runtime_env" && { echo 'runtime file already exists' >&2; exit 1; }
openssl rand -hex 32 | sed 's/^/LITELLM_MASTER_KEY=sk-/' > "$runtime_env"
chmod 600 "$runtime_env"
```

The LiteLLM template defines `qwen3.8-flash-next` as `openai/Qwen3.8-Flash-Next` with a `${VLLM_API_BASE}` private endpoint. It defines `anthropic-claude` as the Anthropic model alias and scopes `litellm_settings.model_group_settings.forward_client_headers_to_llm_api` to exactly `[anthropic-claude]`.

- [ ] **Step 4: Run the test and repository safety checks**

Run: `sh tests/test-local-runtime-safety.sh && sh tests/test-repository-safety.sh && sh scripts/verify-repo.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add .gitignore runtime scripts/bootstrap-local-llm.sh tests/test-local-runtime-safety.sh
git commit -m "feat: add protected local LLM runtime bootstrap"
```

### Task 2: Add LiteLLM and Langfuse local compose topology

**Files:**
- Create: `compose/local-llm-primary.compose.example.yaml`
- Create: `compose/local-llm-standby.compose.example.yaml`
- Create: `tests/test-local-llm-compose.sh`

**Interfaces:**
- Consumes: `private/runtime.env`, `runtime/litellm-config.yaml`, and ignored state directories.
- Produces: `litellm`, `langfuse-web`, `langfuse-worker`, `langfuse-postgres`, `langfuse-clickhouse`, and `langfuse-redis` services.

- [ ] **Step 1: Write the failing topology test**

```sh
#!/bin/sh
set -eu
file=compose/local-llm-primary.compose.example.yaml
for service in litellm langfuse-web langfuse-worker langfuse-postgres langfuse-clickhouse langfuse-redis; do
  grep -q "^  $service:" "$file"
done
grep -q '127.0.0.1:${LITELLM_PORT}' "$file"
grep -q '127.0.0.1:${LANGFUSE_PORT}' "$file"
if rg -n '0\.0\.0\.0:|privileged: true' "$file"; then exit 1; fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh tests/test-local-llm-compose.sh`

Expected: FAIL because the compose templates are absent.

- [ ] **Step 3: Implement the private compose stacks**

```yaml
litellm:
  env_file: ${RUNTIME_ENV_FILE}
  volumes:
    - ${LITELLM_CONFIG_FILE}:/app/config.yaml:ro
  ports: ["127.0.0.1:${LITELLM_PORT}:4000"]
  depends_on: [langfuse-web]
  restart: unless-stopped
```

Use named volumes for database state, `restart: unless-stopped`, health checks for every dependency, and `cap_drop: [ALL]` where the upstream image supports it. The standby file must render but contain no `ports` and use Compose profiles so no service starts without an explicit `--profile standby`.

- [ ] **Step 4: Render and validate**

Run: `docker compose --env-file runtime/local-llm.env.example -f compose/local-llm-primary.compose.example.yaml config >/dev/null && sh tests/test-local-llm-compose.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add compose tests/test-local-llm-compose.sh
git commit -m "feat: add local LiteLLM and Langfuse topology"
```

### Task 3: Add Qwen dual-GB10 serving template and health contract

**Files:**
- Create: `compose/qwen-vllm-head.compose.example.yaml`
- Create: `compose/qwen-vllm-worker.compose.example.yaml`
- Create: `scripts/status-local-llm.sh`
- Create: `tests/test-qwen-serving-contract.sh`

**Interfaces:**
- Consumes: protected cluster endpoints plus `QWEN_MODEL`, `VLLM_IMAGE`, and `VLLM_API_BIND_ADDRESS` from `private/runtime.env`.
- Produces: a private vLLM `/health`, `/v1/models`, and `/metrics` endpoint and named, machine-readable health statuses.

- [ ] **Step 1: Write the failing serving contract test**

```sh
#!/bin/sh
set -eu
head=compose/qwen-vllm-head.compose.example.yaml
worker=compose/qwen-vllm-worker.compose.example.yaml
grep -q 'Qwen/Qwen3.8-Flash-Next' "$head"
grep -q 'VLLM_API_BIND_ADDRESS' "$head"
grep -q 'VLLM_HEAD_PRIVATE_ADDRESS' "$worker"
if rg -n '0\.0\.0\.0|--api-key' compose/qwen-vllm-*.yaml; then exit 1; fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh tests/test-qwen-serving-contract.sh`

Expected: FAIL because the Qwen compose templates are absent.

- [ ] **Step 3: Implement the head and worker templates**

```yaml
command:
  - serve
  - ${QWEN_MODEL}
  - --host
  - ${VLLM_API_BIND_ADDRESS}
  - --port
  - "8000"
  - --served-model-name
  - Qwen3.8-Flash-Next
```

Document the reviewed vLLM image digest as a runtime variable, use only the protected cluster network values for distributed execution, and preserve model-cache locations. The status script uses `curl --fail --silent` against loopback/private endpoints and prints service names plus state only.

- [ ] **Step 4: Validate static contract**

Run: `sh tests/test-qwen-serving-contract.sh && sh scripts/verify-repo.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add compose scripts/status-local-llm.sh tests/test-qwen-serving-contract.sh
git commit -m "feat: add Qwen dual GB10 serving contract"
```

### Task 4: Connect metadata-only traces and Prometheus scraping

**Files:**
- Modify: `prometheus/prometheus.example.yml`
- Modify: `prometheus/alerts.example.yml`
- Modify: `prometheus/recording.example.yml`
- Create: `prometheus/local-llm-targets.example.yml`
- Create: `tests/test-trace-observability-contract.sh`

**Interfaces:**
- Consumes: LiteLLM `/metrics`, Langfuse health endpoints, and the two node exporter endpoint sets.
- Produces: `litellm`, `langfuse`, `vllm`, and `langfuse_dependencies` scrape jobs plus gateway/trace health alerts.

- [ ] **Step 1: Write the failing observability test**

```sh
#!/bin/sh
set -eu
grep -q 'job_name: langfuse' prometheus/prometheus.example.yml
grep -q 'job_name: litellm' prometheus/prometheus.example.yml
grep -q 'LangfuseUnavailable' prometheus/alerts.example.yml
if rg -n -i 'prompt|completion|authorization|api_key|user_name|ip_address' prometheus; then exit 1; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `sh tests/test-trace-observability-contract.sh`

Expected: FAIL because the Langfuse job and alert are absent.

- [ ] **Step 3: Implement scrape and alert configuration**

```yaml
- alert: LangfuseUnavailable
  expr: up{job="langfuse"} == 0
  for: 5m
  labels: {severity: warning}
  annotations: {summary: "Langfuse health endpoint is unavailable"}
```

Use file-based private targets only. Add service-up recording rules and LiteLLM request-rate/error/latency aggregates that retain only safe model aliases and response status.

- [ ] **Step 4: Validate**

Run: `promtool check config prometheus/prometheus.example.yml && promtool check rules prometheus/alerts.example.yml prometheus/recording.example.yml && sh tests/test-trace-observability-contract.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add prometheus tests/test-trace-observability-contract.sh
git commit -m "feat: monitor LiteLLM and Langfuse safely"
```

### Task 5: Add Grafana trace visibility without content exposure

**Files:**
- Create: `grafana/dashboards/tracing-path.json`
- Modify: `grafana/provisioning/dashboards/dashboards.example.yaml`
- Modify: `tests/test-grafana-dashboards.sh`

**Interfaces:**
- Consumes: Prometheus datasource `Prometheus` and safe LiteLLM/Langfuse aggregate metrics.
- Produces: a provisioned **Tracing Path** dashboard with node and interval variables and no payload panels.

- [ ] **Step 1: Extend the failing dashboard test**

```sh
jq -e '.dashboard.title == "Tracing Path"' grafana/dashboards/tracing-path.json >/dev/null
jq -e '.dashboard.templating.list[] | select(.name == "node")' grafana/dashboards/tracing-path.json >/dev/null
if rg -n -i 'prompt|completion|authorization|api_key|request body' grafana/dashboards/tracing-path.json; then exit 1; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `sh tests/test-grafana-dashboards.sh`

Expected: FAIL because the tracing dashboard is absent.

- [ ] **Step 3: Add the dashboard and provisioning entry**

```json
{"title":"LiteLLM Request Error Ratio","type":"timeseries","targets":[{"expr":"fleet:request_error_ratio:5m"}]}
```

Add panels for LiteLLM health, Langfuse availability, request rate, token rate, p95 latency, response classification, and trace-delivery health. Set explicit no-data descriptions and an authenticated Langfuse base URL variable sourced only from Grafana’s ignored runtime configuration.

- [ ] **Step 4: Validate**

Run: `sh tests/test-grafana-dashboards.sh && jq empty grafana/dashboards/tracing-path.json`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add grafana tests/test-grafana-dashboards.sh
git commit -m "feat: add safe tracing Grafana dashboard"
```

### Task 6: Add deployment, client-profile, backup, and rollback operations

**Files:**
- Create: `scripts/render-local-llm.sh`
- Create: `scripts/deploy-local-llm.sh`
- Create: `scripts/create-claude-code-profile.sh`
- Modify: `scripts/rollback-monitoring.sh`
- Modify: `docs/operations.md`
- Create: `docs/replicate-local-llm.md`
- Create: `tests/test-local-llm-deployment-safety.sh`

**Interfaces:**
- Consumes: an absolute protected runtime environment path and named compose project `local-llm`.
- Produces: rendered configs, started named services, a mode-0600 client profile, safe status output, and named-only rollback.

- [ ] **Step 1: Write the failing deployment-safety test**

```sh
#!/bin/sh
set -eu
grep -q 'mode 600' scripts/render-local-llm.sh
grep -q 'git check-ignore' scripts/bootstrap-local-llm.sh
grep -q 'ANTHROPIC_BASE_URL' scripts/create-claude-code-profile.sh
grep -q 'ANTHROPIC_CUSTOM_HEADERS' scripts/create-claude-code-profile.sh
if rg -n 'echo.*LITELLM|set -x|docker compose down( |$)' scripts/deploy-local-llm.sh scripts/create-claude-code-profile.sh; then exit 1; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `sh tests/test-local-llm-deployment-safety.sh`

Expected: FAIL because the scripts are absent.

- [ ] **Step 3: Implement guarded rendering and deployment**

```sh
test "$(stat -c '%a' "$env_file")" = 600 || { echo 'private env must be mode 600' >&2; exit 1; }
grep -Eq '(^|=)0\.0\.0\.0' "$env_file" && { echo 'public binding refused' >&2; exit 1; }
docker compose --project-name local-llm --env-file "$env_file" -f "$compose" config >/dev/null
docker compose --project-name local-llm --env-file "$env_file" -f "$compose" up -d
```

The client-profile script writes `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL=anthropic-claude`, and `ANTHROPIC_CUSTOM_HEADERS` to an ignored mode-0600 file, then prints the path only. The replication guide includes exact bootstrap, health, OAuth-login, backup, secret-rotation, and named rollback commands.

- [ ] **Step 4: Run static suite**

Run: `sh tests/test-local-llm-deployment-safety.sh && sh tests/test-deployment-safety.sh && sh scripts/verify-repo.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts docs tests/test-local-llm-deployment-safety.sh
git commit -m "feat: add repeatable local LLM deployment runbooks"
```

### Task 7: Add the reusable local-LLM operations skill and complete a live deployment

**Files:**
- Create: `skills/local-llm-observability/SKILL.md`
- Create: `skills/local-llm-observability/references/claude-code-max.md`
- Create: `tests/test-local-llm-skill.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: the project’s bootstrap/deploy/status/rollback scripts and a protected local runtime path.
- Produces: a reusable server-onboarding workflow and a verified local deployment report that contains no secret values.

- [ ] **Step 1: Write the failing skill test**

```sh
#!/bin/sh
set -eu
skill=skills/local-llm-observability/SKILL.md
grep -q 'Qwen3.8 Flash-Next' "$skill"
grep -q 'Claude Code Max' "$skill"
grep -q 'private/runtime.env' "$skill"
grep -q 'prompt and completion capture is disabled' "$skill"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `sh tests/test-local-llm-skill.sh`

Expected: FAIL because the skill is absent.

- [ ] **Step 3: Implement the skill and update the project entrypoint**

The skill must require private-network discovery, protected bootstrap, static validation, staged head/worker/observability deployment, health checks, manual per-client Claude OAuth, and backup verification. It must prohibit logging, committing, or copying secrets and prompt/completion data. The reference lists the official Claude Code Max LiteLLM behavior and exact client variables by name without including a key value.

- [ ] **Step 4: Validate project and live environment**

Run: `sh tests/test-local-llm-skill.sh && sh tests/test-repository-safety.sh && sh tests/test-exporter-topology.sh && sh tests/test-prometheus-config.sh && sh tests/test-grafana-dashboards.sh && sh tests/test-deployment-safety.sh && sh tests/test-local-runtime-safety.sh && sh tests/test-local-llm-compose.sh && sh tests/test-qwen-serving-contract.sh && sh tests/test-trace-observability-contract.sh && sh tests/test-local-llm-deployment-safety.sh && sh scripts/verify-repo.sh`

Then run: `scripts/bootstrap-local-llm.sh /absolute/path/private/runtime.env`, deploy the worker and head with their protected runtime files, run `scripts/deploy-local-llm.sh /absolute/path/private/runtime.env`, and run `scripts/status-local-llm.sh /absolute/path/private/runtime.env`.

Expected: all static checks pass; runtime status reports both GB10 targets plus vLLM, LiteLLM, Langfuse, Prometheus, and Grafana as healthy. The final Claude Code Max check is manually completed in a browser.

- [ ] **Step 5: Commit**

```bash
git add skills README.md tests/test-local-llm-skill.sh
git commit -m "docs: add reusable local LLM observability skill"
```
