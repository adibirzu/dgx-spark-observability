# DGX Spark Observability

Private-by-default, two-node Grafana and Prometheus monitoring bundle for GB10 systems. Start locally: deploy exporters on both nodes, validate Prometheus and Grafana on the designated primary, and render—but do not start—the standby configuration.

Never expose exporters or Prometheus directly on the management LAN or public Internet. Grafana is authenticated and is the only operator-facing service. OCI Monitoring federation and OCI Log Analytics are optional, disabled by default, and configured only with protected credentials outside Git.

Run the full static suite before any deployment:

```sh
sh tests/test-repository-safety.sh && sh tests/test-exporter-topology.sh && sh tests/test-prometheus-config.sh && sh tests/test-grafana-dashboards.sh && sh tests/test-deployment-safety.sh && sh tests/test-oci-boundaries.sh && sh scripts/verify-repo.sh
```
