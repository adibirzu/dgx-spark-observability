# Unified monitoring deployment design

**Status:** architecture approved; implementation begins after review of this specification.

## Objective

Deploy one authenticated Grafana workspace backed by Prometheus for two GB10 systems. The workspace answers, in order: is either node unavailable, is model serving healthy, is GPU or unified memory constrained, are requests slow or failing, and is recovery material current.

## Topology and boundaries

The designated primary monitoring node runs Grafana, Prometheus, alert rules, and local exporters. The peer runs the same collectors and retains a synchronized, disabled standby configuration. The primary scrapes only the private metrics network; neither exporter nor Prometheus is exposed to the public Internet.

Grafana is the only operator-facing service. It is reachable through authenticated Tailnet access and the management LAN. Grafana anonymous access is disabled; its initial administrator credential is created locally in a mode-0600 environment file and never appears in Git, logs, dashboards, or command output.

## Metrics contract

Prometheus obtains these metric groups from both nodes:

- host: reachability, CPU, memory, storage capacity and pressure, network traffic;
- GPU: utilization, memory, temperature, power, clocks, and error state;
- containers: lifecycle, restart count, CPU, memory, and health;
- serving: vLLM readiness, queued/running requests, throughput, latency, KV cache, prefix cache, preemptions, and errors;
- gateway: LiteLLM readiness, authenticated request rate, latency, response status, and configured upstream health;
- recovery: last verified backup timestamp and backup job result.

No panel, label, log, or alert includes prompts, completions, API keys, usernames, raw addresses, or model content.

## Dashboard contract

The first release provisions four Grafana dashboards:

1. **Fleet overview**: per-node scrape health, service readiness, CPU/unified memory, GPU state, storage pressure, and backup freshness.
2. **Serving path**: vLLM readiness, request load, throughput, latency, cache behavior, and rank-loss/restart annotations.
3. **Gateway path**: LiteLLM availability, authenticated response classification, upstream health, and no-payload error trends.
4. **Recovery and export**: backup age/result, Prometheus retention, OCI federation readiness, and Log Analytics status when opt-in modules are configured.

Every dashboard has a node selector, a time-range selector, visible last-updated state, and explicit no-data/stale/down panels. The mobile reading order is fleet status, serving status, GPU/memory pressure, then details.

## Access and operational behavior

The management-LAN endpoint is restricted by host firewall policy to the approved administrative network. Tailnet access uses an authenticated reverse proxy without publishing the Grafana port globally. TLS termination and host-specific paths belong in protected local configuration.

Prometheus retains data locally. Grafana remains useful with the most recent samples when a target is stale and labels partial/outage state rather than silently drawing zeroes. A lost optional OCI integration does not change local scraping, dashboards, model serving, LiteLLM, or backup jobs.

## Standby, backup, and rollback

The standby has provisioned images, dashboard definitions, and an encrypted protected backup of the primary monitoring configuration. Promotion is manual: verify primary loss, restore protected configuration and volume material on the standby, start the named monitoring stack, validate authenticated Grafana plus both scrape targets, then direct operators to the promoted endpoint.

Rollback stops only named observability services, restores the last verified protected monitoring archive, and revalidates datasource, exporter, and access health. It never alters vLLM, LiteLLM, model containers, or their volumes.

## OCI integration boundary

OCI Monitoring Prometheus scraping uses an allowlisted Prometheus federation endpoint and an operator-created OCI Management Agent configuration. OCI Log Analytics receives separately redacted logs only after explicit source/entity setup. Each module is independently disabled by default and uses protected credentials outside this repository.

## Validation and tests

Static tests validate Compose, Prometheus configuration, Grafana provisioning, dashboard JSON, label allow-lists, and absence of sensitive paths or values. Runtime validation checks both exporter targets, Prometheus target health, Grafana authentication rejection and acceptance, dashboard datasource readiness, and that neither management-LAN nor Tailnet routing reaches exporter or Prometheus endpoints directly.

The deployment is accepted only when all four dashboards load from Prometheus, both nodes report fresh samples, authenticated access works through both approved paths, and an offline restore drill is documented and verified.
