# Loki Log Aggregation Stack

Log aggregation for the Kubernetes homelab using Grafana Loki and Promtail.

## Overview

| Property | Value |
|----------|-------|
| Loki chart | grafana/loki 6.20.0 |
| Promtail chart | grafana/promtail 6.16.6 |
| Namespace | `monitoring` |
| Mode | SingleBinary |
| Storage | MinIO (S3-compatible, `loki` bucket) |
| Retention | 7 days |
| Log access | Grafana → Loki |

**Components:**
- **Loki** — log aggregation engine (stores and queries logs)
- **Promtail** — log collection agent (DaemonSet, one pod per node)

## Architecture

```
Promtail DaemonSet (k8s-cp-01, k8s-worker-01, k8s-worker-02)
    │
    │  Tails /var/log/pods/* and /var/log/* on each node
    │  Extracts labels: namespace, pod, container, node, app
    │
    ▼
Loki Server (StatefulSet, monitoring namespace)
    │
    │  Persists compressed log chunks to MinIO via S3 API
    │
    ▼
MinIO (minio namespace, loki bucket)
    │
    ▼
Grafana (LogQL queries via http://loki.monitoring.svc.cluster.local:3100)
```

### Data Flow

1. Pods write logs to stdout/stderr
2. Promtail tails container log files on each node
3. Promtail extracts labels (namespace, pod, container, node, app) and ships logs to Loki via HTTP
4. Loki indexes labels only (not full-text), compresses log chunks, stores them in MinIO
5. Grafana queries Loki with LogQL and renders results

## Storage Backend

Loki uses **MinIO** as its object store (S3-compatible, `loki` bucket). Log chunks are streamed to MinIO continuously — no local PVC is used for log data. A small WAL PVC (`local-path`, 5Gi) buffers in-flight writes before they are flushed to MinIO.

Credentials are synced from Vault by ESO as `loki-minio-credentials` in the `monitoring` namespace.

| Storage | Purpose | Class |
|---------|---------|-------|
| MinIO `loki` bucket | Log chunk storage | S3 (MinIO) |
| 5Gi PVC | WAL (write-ahead log) | local-path |

## Resource Allocation

| Component | Replicas | CPU | Memory | Notes |
|-----------|----------|-----|--------|-------|
| Loki | 1 | 50m / — | 256Mi / 512Mi | SingleBinary mode |
| Promtail | 3 | 100m / — | 128Mi / 256Mi | DaemonSet, one per node |

## Configuration

### Deployment Mode

**SingleBinary** — all Loki components (ingester, querier, compactor) run in a single process. Appropriate for a 3-node homelab cluster. No horizontal scaling per component is needed.

### Log Retention

```yaml
retention_period: 168h  # 7 days
```

Compactor enforces retention against the MinIO bucket. 7 days covers all practical homelab troubleshooting windows.

### Promtail Scrape Jobs

| Job | Source | Labels extracted |
|-----|--------|-----------------|
| `kubernetes-pods` | `/var/log/pods/` | namespace, pod, container, node, app |
| `system` | `/var/log/` | job=varlogs (kubelet, containerd, kernel) |

## GitOps Management

| Resource | Path |
|----------|------|
| Loki ArgoCD app | `platform/argocd/apps/loki-app.yaml` |
| Promtail ArgoCD app | `platform/argocd/apps/promtail-app.yaml` |
| Loki Helm values | `platform/observability/loki/values.yaml` |
| Promtail Helm values | `platform/observability/loki/promtail-values.yaml` |

Configuration changes flow through Git → ArgoCD → cluster. Do not `kubectl edit` Loki or Promtail resources directly.

## Verification

```bash
# Check Loki pod
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# Check Promtail pods (expect 3, one per node)
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail -o wide

# Check MinIO credentials secret is synced
kubectl get secret loki-minio-credentials -n monitoring

# Check Promtail is shipping logs
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=20
# Look for: "Successfully sent batch"

# Verify Loki is ingesting
kubectl port-forward -n monitoring svc/loki 3100:3100 &
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="kubernetes-pods"}' \
  --data-urlencode 'limit=1' | jq '.status'
# Expected: "success"
pkill -f "port-forward.*loki"
```

## Troubleshooting

### No logs in Grafana

```bash
# 1. Check Promtail is running on all 3 nodes
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail -o wide

# 2. Check Promtail logs for errors
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=50
# "connection refused" → Loki pod not ready
# "permission denied" → Promtail cannot read /var/log/pods

# 3. Verify Promtail can reach Loki
kubectl exec -n monitoring -it <promtail-pod> -- wget -O- http://loki:3100/ready
# Expected: ready
```

### MinIO credentials not synced

```bash
# Check ExternalSecret status
kubectl get externalsecret loki-minio-credentials -n monitoring
# STATUS must be SecretSynced — if not, check Vault path secret/data/minio/loki

kubectl describe externalsecret loki-minio-credentials -n monitoring
```

### Loki pod CrashLoopBackOff

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=50

# Common causes:
# - MinIO bucket "loki" does not exist → create it in MinIO Console
# - loki-minio-credentials not synced → fix ESO/Vault
# - WAL PVC not bound → check local-path provisioner
```

### Loki query returns empty

```bash
# Check Loki has received data
kubectl port-forward -n monitoring svc/loki 3100:3100 &
curl -s http://localhost:3100/metrics | grep loki_ingester_streams_created_total
pkill -f "port-forward.*loki"

# If zero: Promtail is not shipping. Check Promtail → Loki connectivity.
```

## Common LogQL Queries

```logql
# All logs from a namespace
{namespace="monitoring"}

# Error logs cluster-wide
{namespace=~".+"} |~ "error|ERROR"

# Logs from specific pod
{pod="nextcloud-production-0"}

# Parse JSON logs and filter by level
{namespace="monitoring"} | json | level="error"

# Log rate — errors per minute
sum(rate({namespace=~".+"} |~ "error" [1m]))

# Logs from multiple namespaces
{namespace=~"nextcloud-production|databases"}
```

## Related Documentation

- [ADR-010: Observability Stack](../../docs/adr/ADR-010-observability-stack-architecture.md)
- [Data Layer Reference](../../docs/reference/data-layer.md) — MinIO credentials inventory
- [Grafana README](../grafana/README.md) — log visualization via LogQL
- [Prometheus README](../prometheus/README.md) — metrics stack
