# OCI Monitoring Prometheus federation

This module is **disabled by default**. First validate local Prometheus targets and Grafana dashboards. Then create an OCI Management Agent configuration outside this repository that requests only the reviewed `match[]` selectors in the metric allowlist. Do not expose `/federate` beyond the private monitoring boundary.
