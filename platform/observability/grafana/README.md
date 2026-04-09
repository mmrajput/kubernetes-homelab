# Grafana

Unified observability dashboard for the homelab cluster.

## Overview

| Property | Value |
|----------|-------|
| Chart | grafana 10.5.15 |
| App version | Grafana 12.3.1 |
| Namespace | `monitoring` |
| Storage | 1Gi PVC (local-path) |
| URL | grafana.mmrajputhomelab.org |
| Auth | Keycloak OIDC SSO (homelab realm) |

## Data Sources

| Source | URL | Purpose |
|--------|-----|---------|
| Prometheus (default) | `http://prometheus-operated:9090` | Metrics (PromQL) |
| Loki | `http://loki:3100` | Logs (LogQL) |

Both data sources are configured via Helm values and provisioned automatically on deployment.

## Authentication

Grafana uses **Keycloak OIDC SSO**. Users authenticate via `keycloak.mmrajputhomelab.org` (homelab realm). Role mapping is derived from Keycloak group membership:

| Keycloak group | Grafana role |
|---------------|-------------|
| `argocd-admins` | Admin |
| (all authenticated users) | Viewer |

The OIDC client secret is synced from Vault by ESO as `grafana-oidc-secret` in the `monitoring` namespace.

> There is no local admin account in normal operation. Use SSO.

## Pre-installed Dashboards

| Dashboard | Grafana ID | Data Source |
|-----------|-----------|-------------|
| Kubernetes Cluster Monitoring | 7249 | Prometheus |
| Kubernetes Pods Monitoring | 6417 | Prometheus |
| Node Exporter Full | 1860 | Prometheus |
| Loki Logs | 13639 | Loki |

Dashboards are auto-imported on deployment via Helm values and saved to the 1Gi PVC.

## GitOps Management

| Resource | Path |
|----------|------|
| ArgoCD app | `platform/argocd/apps/observability/grafana-app.yaml` |
| Helm values | `platform/observability/grafana/values.yaml` |

Configuration changes (new dashboards, data sources, plugins) flow through Git → ArgoCD.

```bash
# Force immediate sync after pushing changes
kubectl annotate application grafana -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

## Verification

```bash
# Pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# PVC status
kubectl get pvc -n monitoring | grep grafana

# OIDC secret synced
kubectl get externalsecret grafana-oidc-secret -n monitoring

# Test UI
curl -I https://grafana.mmrajputhomelab.org
# Expected: HTTP 200 or 302 (redirect to Keycloak)
```

## Troubleshooting

### Cannot log in (SSO redirect fails)

```bash
# Check OIDC secret is synced
kubectl get externalsecret grafana-oidc-secret -n monitoring
# STATUS must be SecretSynced

# Check Grafana logs for OIDC errors
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50 | grep -i oidc
```

### Pod CrashLoopBackOff (init-chown-data)

```yaml
# Ensure values.yaml has:
initChownData:
  enabled: false
securityContext:
  runAsUser: 472
  runAsGroup: 472
  fsGroup: 472
```

### Data source not working

```bash
# Check service names from Grafana pod
kubectl exec -n monitoring -l app.kubernetes.io/name=grafana -- \
  curl -s http://prometheus-operated:9090/api/v1/status/config | head -5

kubectl exec -n monitoring -l app.kubernetes.io/name=grafana -- \
  curl -s http://loki:3100/ready
# Expected: ready
```

### Dashboard shows empty panels

- Adjust time range (top right) — default might be outside retention window
- Check the data source selected in the panel matches an active source
- Verify Prometheus is scraping targets: check `Status → Targets` in Prometheus UI

## Common Queries

### PromQL

```promql
# Node CPU usage %
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node memory usage %
100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)

# Pod CPU by namespace
sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace)
```

### LogQL

```logql
# Error logs from all namespaces
{namespace=~".+"} |~ "error|ERROR"

# Logs from specific pod
{pod="nextcloud-production-0"}

# Parse JSON and filter by level
{namespace="monitoring"} | json | level="error"
```

## Related Documentation

- [Prometheus README](../prometheus/README.md)
- [Loki README](../loki/README.md)
- [ADR-010: Observability Stack](../../docs/adr/ADR-010-observability-stack-architecture.md)
- [Data Layer Reference](../../docs/reference/data-layer.md) — OIDC secret inventory

---

**Last Updated:** April 2026
