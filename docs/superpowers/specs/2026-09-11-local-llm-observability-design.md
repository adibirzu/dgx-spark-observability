# Local LLM gateway and observability design

**Status:** approved for implementation.

## Objective

Provide a repeatable, local-first two-GB10 coding platform. Qwen3.8 Flash-Next is the default local model, served by vLLM across both GB10 systems. LiteLLM is the only client-facing gateway and Langfuse provides trace-level visibility. Prometheus and Grafana retain private operational metrics. The bundle must be deployable on a new server without committing credentials, host inventory, model prompts, completions, API keys, OAuth tokens, or database data.

## Topology and trust boundaries

The designated primary GB10 runs the vLLM API server, LiteLLM, Langfuse, its PostgreSQL, ClickHouse, and Redis dependencies, Prometheus, Grafana, and local exporters. The peer GB10 runs the distributed vLLM worker and private exporters; it also has a rendered but disabled monitoring standby configuration. Model traffic and all scrape traffic stay on the private cluster/metrics networks. Grafana, Langfuse, and LiteLLM bind to loopback by default; operator access is via an authenticated local reverse proxy or Tailnet configuration supplied outside Git.

LiteLLM exposes two explicit model groups:

- `qwen3.8-flash-next`: default OpenAI-compatible local coding model, upstreamed to the private vLLM endpoint;
- `anthropic-claude`: an opt-in Claude Code Max route. LiteLLM must forward client headers only for this model group, so each Claude Code client authenticates to Anthropic with its own OAuth session.

No OAuth token transits Grafana, Prometheus, Langfuse, logs, dashboard labels, or configuration files. LiteLLM virtual keys authenticate clients to the gateway and are independently generated/stored in protected local files.

## Claude Code Max integration

The operator installs Claude Code and holds a Claude Max subscription. On every developer client, a generated local profile sets the LiteLLM base URL, the `anthropic-claude` model alias, and that client’s LiteLLM virtual key. Claude Code then performs the normal interactive browser login using “Claude account with subscription.” LiteLLM forwards the resulting Authorization header solely to Anthropic for its allowed Anthropic model group; it does not persist the token.

The first deployment validates the gateway route without exposing or printing credentials. A human must complete the browser OAuth flow and make the first Claude Code request; the validation records only success/failure, duration, model alias, token counts, and status code.

## Data and observability contract

LiteLLM sends non-content request traces to the local Langfuse deployment. Langfuse records request identity pseudonyms, model alias, timestamps, token counts, latency, status, optional cost metadata, and parent/trace IDs. Prompt and completion capture is disabled by default. A protected local setting is required to opt in to content capture for a narrowly scoped debugging session.

Prometheus receives host, GPU, container, vLLM, LiteLLM, Langfuse, database health, backup, and gateway request aggregates. It must never scrape or derive prompt/completion bodies, Authorization headers, API keys, user names, IP addresses, or arbitrary request IDs. Grafana retains the original fleet, serving, gateway, and recovery dashboards and adds a tracing/dashboard health view with link-outs to authenticated Langfuse traces where safe.

## Runtime configuration and replication

Tracked example files contain variable names and safe defaults only. `scripts/bootstrap-local-llm.sh` creates a machine-specific ignored `private/runtime.env` (mode 0600), random service secrets, state directories, and a generated LiteLLM virtual-key file. `scripts/render-local-llm.sh` refuses unsafe bindings, missing secret files, non-0600 modes, public endpoints, or any target outside the configured private networks. The generated file names and the required `git check-ignore` assertions are documented in the runbook.

The replication guide has an ordered bootstrap: prepare the two hosts and private network; install the pinned container runtime/NVIDIA stack; create protected runtime secrets; launch distributed Qwen vLLM; launch LiteLLM/Langfuse/Prometheus/Grafana; run health checks; complete per-client Claude Code OAuth; and take a protected backup. It includes a rotation/recovery section and an explicit list of files that must not be copied into Git.

## Failure and rollback

Qwen/vLLM loss degrades only the local Qwen route. Anthropic/Claude Max authorization loss degrades only the `anthropic-claude` route. Langfuse loss must not prevent LiteLLM from serving requests; it emits health/trace-delivery failures to Prometheus. Prometheus/Grafana loss must not affect serving. Named-stack rollback and restore never alter model caches, vLLM volumes, the client’s Claude OAuth state, or unrelated containers.

## Validation

Static tests verify that local configurations reject public bindings, tracked secret data, broad header forwarding, prompt/completion logging, and sensitive labels. They validate LiteLLM model routing, Langfuse content-capture defaults, compose/config syntax, Prometheus alert rules, and Grafana dashboards. Runtime checks validate all services, both GB10 scrape targets, Qwen route readiness, the LiteLLM local model route, Langfuse ingestion without content, authenticated Grafana/Langfuse access, and the manually completed Claude Code Max request path.
