# Unified monitoring operations

Create the private environment file outside Git with mode `0600`. Supply a management-LAN bind address for Grafana; Tailnet access must use a separately configured authenticated reverse proxy. Never publish exporter or Prometheus ports on the management LAN.

Run `scripts/render-monitoring.sh` before deployment. Run `scripts/deploy-monitoring.sh` only on the promoted primary. The standby configuration is rendered and backup-restorable, but remains stopped until deliberate promotion.

Validate rejected and accepted Grafana login behavior, Prometheus target health, and that direct exporter/Prometheus requests from the management LAN fail. Rollback with `scripts/rollback-monitoring.sh` stops only named monitoring services.
