# Prometheus Observability Stack

Metrics collection, storage, and alerting for the homelab cluster using kube-prometheus-stack.

## Overview

| Property | Value |
|----------|-------|
| Chart | kube-prometheus-stack 65.8.1 |
| Namespace | `monitoring` |
| URL | prometheus.mmrajputhomelab.org |
| Alertmanager | alertmanager.mmrajputhomelab.org |
| Retention | 15 days / 45GB |
| Storage | 50Gi PVC (local-path) |

**Components deployed by this chart:**
- Prometheus Operator
- Prometheus Server (metrics collection, TSDB)
- Alertmanager (alert routing)
- node-exporter (DaemonSet — hardware/OS metrics)
- kube-state-metrics (Kubernetes object metrics)

Grafana is deployed separately via `platform/observability/grafana/`.

## Architecture

```
ServiceMonitors (CRDs) ──► Prometheus Operator ──► Prometheus Server
                                                          │
                                                          ├── Scrapes: node-exporter (all nodes)
                                                          ├── Scrapes: kube-state-metrics
                                                          ├── Scrapes: kubernetes API
                                                          └── Evaluates rules → Alertmanager
                                                          │
                                                          ▼
                                                     Grafana (queries via PromQL)
```

## Storage

Prometheus uses `local-path` (node-local storage) for its 50Gi metrics PVC. This is intentional — metrics are ephemeral reference data with a 15-day retention window. Node-local storage avoids Longhorn overhead for high-write workloads.

| Component | Storage | Class | Notes |
|-----------|---------|-------|-------|
| Prometheus | 50Gi | local-path | Retention: 15d / 45GB |
| Alertmanager | 5Gi | local-path | Alert state persistence |

## Resource Allocation

| Component | Replicas | CPU req | Memory req |
|-----------|----------|---------|-----------|
| Prometheus | 1 | 200m | 1Gi |
| Alertmanager | 1 | 50m | 128Mi |
| Operator | 1 | 100m | 128Mi |
| kube-state-metrics | 1 | 50m | 200Mi |
| node-exporter | 3 | 50m | 100Mi |

## Service Discovery

```yaml
serviceMonitorSelectorNilUsesHelmValues: false
```

Prometheus discovers **all** ServiceMonitors cluster-wide (no label filtering). Any app that creates a ServiceMonitor is automatically scraped.

## Expected DOWN Targets

These are normal and not errors:

| Target | Reason |
|--------|--------|
| `kube-controller-manager` | Binds to localhost only (security) |
| `kube-scheduler` | Binds to localhost only (security) |
| `kube-etcd` | Not exposed in this configuration |

**Critical targets that must be UP:**
- `kubernetes-apiservers`
- `kubernetes-nodes`
- `node-exporter` (3 instances)
- `kube-state-metrics`
- `prometheus-operator`

## GitOps Management

| Resource | Path |
|----------|------|
| ArgoCD app | `platform/argocd/apps/observability/kube-prometheus-stack-app.yaml` |
| Helm values | `platform/observability/prometheus/values.yaml` |

```bash
# Force immediate sync
kubectl annotate application kube-prometheus-stack -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

## Verification

```bash
# Check all pods running
kubectl get pods -n monitoring

# Check PVCs bound
kubectl get pvc -n monitoring

# Check targets in Prometheus UI
# https://prometheus.mmrajputhomelab.org/targets

# Spot-check via PromQL
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
curl -s 'http://localhost:9090/api/v1/query?query=up{job="node-exporter"}' | jq '.data.result | length'
# Expected: 3
pkill -f "port-forward.*9090"
```

## Troubleshooting

### ArgoCD shows Degraded

```bash
# Check if CRD sync options are correct
kubectl get application kube-prometheus-stack -n argocd -o yaml | grep -A5 syncOptions
# Must include: ServerSideApply=true

# Check PVC is bound
kubectl get pvc -n monitoring
```

### No ingress created

Ingress config must be at the service level, not inside `prometheusSpec`:

```yaml
# Correct
prometheus:
  ingress:
    enabled: true
  prometheusSpec:
    ...

# Wrong — ingress inside prometheusSpec is ignored
prometheus:
  prometheusSpec:
    ingress: ...
```

### Prometheus OOM

```yaml
prometheus:
  prometheusSpec:
    retention: 7d
    retentionSize: "20GB"
    resources:
      limits:
        memory: 3Gi
```

### Queries return empty results

1. Check `Status → Targets` in Prometheus UI — verify critical targets are UP
2. Verify ServiceMonitors exist: `kubectl get servicemonitor -A`
3. Check Prometheus logs: `kubectl logs -n monitoring prometheus-prometheus-prometheus-0 -c prometheus`

## Useful PromQL Queries

```promql
# Pods not in Running state
kube_pod_status_phase{phase!="Running"} == 1

# Deployments with unavailable replicas
kube_deployment_status_replicas_unavailable > 0

# Node disk usage %
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)

# Prometheus memory usage
process_resident_memory_bytes{job="prometheus"}
```

## Adding a ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: my-namespace
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
```

Prometheus discovers this automatically within the next scrape interval.

## Related Documentation

- [Grafana README](../grafana/README.md)
- [Loki README](../loki/README.md)
- [ADR-010: Observability Stack](../../docs/adr/ADR-010-observability-stack-architecture.md)

---

**Last Updated:** April 2026
