# Loki Log Aggregation Stack

Enterprise-grade log aggregation for Kubernetes homelab using Grafana Loki and Promtail.

## Overview

Loki is a horizontally-scalable, highly-available log aggregation system inspired by Prometheus. Unlike other logging systems, Loki only indexes metadata (labels) rather than full-text, making it cost-effective and performant.

**Components:**
- **Loki**: Log aggregation engine (stores and queries logs)
- **Promtail**: Log collection agent (DaemonSet, runs on all nodes)

**Query Interface:** Grafana (deployed separately in Step 3)

## Architecture

```
┌─────────────────────────────────────────────────┐
│          Loki Stack - SingleBinary Mode         │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────────────────────────┐           │
│  │         Promtail Agent           │           │
│  │         (DaemonSet)              │           │
│  │  Runs on: k8s-cp-01              │           │
│  │           k8s-worker-01          │           │
│  │           k8s-worker-02          │           │
│  └────────────┬─────────────────────┘           │
│               │                                 │
│               │ Scrapes logs from:              │
│               │ - /var/log/pods/*               │
│               │ - /var/lib/docker/containers/*  │
│               │ - /var/log/*log (system)        │
│               │                                 │
│               │ Pushes logs via HTTP            │
│               ▼                                 │
│  ┌──────────────────────────────────┐           │
│  │      Loki Server                 │           │
│  │      (StatefulSet)               │           │
│  │                                  │           │
│  │  ┌─────────────────────────┐     │           │
│  │  │  All-in-one binary:     │     │           │
│  │  │  - Ingester             │     │           │
│  │  │  - Querier              │     │           │
│  │  │  - Query Frontend       │     │           │
│  │  │  - Compactor            │     │           │
│  │  └─────────────────────────┘     │           │
│  │                                  │           │
│  │  Storage: Filesystem (PVC)       │           │
│  └────────────┬─────────────────────┘           │
│               │                                 │
│               │ Queried by                      │
│               ▼                                 │
│          Grafana UI                             │
│     (deployed in Step 3)                        │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Data Flow

1. **Log Generation**: Pods write logs to stdout/stderr
2. **Log Collection**: Promtail tails log files on each node
3. **Label Extraction**: Promtail extracts metadata (namespace, pod, container)
4. **Log Shipping**: Promtail pushes logs to Loki via HTTP
5. **Indexing**: Loki indexes labels only (not full-text)
6. **Storage**: Log chunks stored on PVC (filesystem mode)
7. **Querying**: Grafana queries Loki using LogQL

## Resource Allocation

| Component | Replicas | CPU | Memory | Storage | Notes |
|-----------|----------|-----|--------|---------|-------|
| Loki | 1 | 50m / - | 256Mi / 512Mi | 10Gi PVC | SingleBinary mode |
| Promtail | 3 | 100m / - | 128Mi / 256Mi | - | DaemonSet (per node) |
| **Total** | - | **~350m** | **~640Mi / 1.3Gi** | **10Gi** | 3 nodes |

*Format: request / limit*

### Memory Footprint Comparison

| Mode | Components | Memory Usage | Use Case |
|------|------------|--------------|----------|
| **SingleBinary** (current) | 1 pod | 256Mi-512Mi | Homelab, <50 nodes |
| Microservices | 10+ pods | 4Gi-8Gi | Production, >100 nodes |
| Microservices + Cache | 15+ pods | 8Gi-16Gi | Large scale, high query load |

## Configuration

### Deployment Mode

**SingleBinary**: All Loki components run in a single process
- ✅ Simple to operate and debug
- ✅ Low resource overhead
- ✅ Perfect for homelab/small deployments
- ❌ No horizontal scaling per component
- ❌ Single point of failure (acceptable for homelab)

**Why not Microservices mode?**
- Requires 4Gi-8Gi RAM minimum
- Adds operational complexity (10+ pods to manage)
- Homelab doesn't need independent scaling of ingesters/queriers

### Storage Backend

**Filesystem Mode** (current):
- Stores log chunks directly on PVC
- Simple setup, no external dependencies
- 10Gi PVC with 7-day retention

**Production Alternative** (S3/MinIO):
- Object storage for chunks (unlimited retention)
- Multi-cluster log aggregation
- Higher durability across AZs
- Trade-off: Requires running MinIO or cloud S3

### Log Retention

```yaml
retention_period: 168h  # 7 days
```

**Rationale:**
- 7 days sufficient for homelab troubleshooting
- 10Gi PVC handles ~3-5GB/day log volume from 3-node cluster
- Longer retention requires larger PVC or S3 backend

**Calculation:**
```
3 nodes × ~20 pods/node × ~50KB/day/pod = ~3GB/day
7 days × 3GB = ~21GB uncompressed
With compression (3:1): ~7GB actual usage
```

### Schema Configuration

```yaml
schemaConfig:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: loki_index_
        period: 24h
```

**Schema v13** (latest stable):
- TSDB for better query performance
- 24h index period balances query speed vs storage
- Filesystem object store (matches our storage mode)

### Promtail Scrape Jobs

**Job 1: kubernetes-pods**
- Scrapes all pod logs from `/var/log/pods`
- Extracts labels: namespace, pod, container, node, app
- Uses CRI parser for container runtime logs

**Job 2: system**
- Scrapes host system logs from `/var/log`
- Useful for kubelet, containerd, kernel logs
- Label: job=varlogs

## Deployment

### Prerequisites
- ArgoCD operational
- nginx-ingress controller
- StorageClass available (local-path-provisioner)
- Prometheus deployed (for ServiceMonitor integration)

### GitOps Deployment

**Managed by:**
- Loki App: `platform/argocd/apps/loki-app.yaml`
- Promtail App: `platform/argocd/apps/promtail-app.yaml`
- Loki Values: `platform/loki/values.yaml`
- Promtail Values: `platform/loki/promtail-values.yaml`
- Charts: `grafana/loki v6.20.0`, `grafana/promtail v6.16.6`

### Update Configuration

```bash
# Edit Loki configuration
vim platform/loki/values.yaml

# Or Promtail configuration
vim platform/loki/promtail-values.yaml

# Commit and push
git add platform/loki/
git commit -m "feat(logging): update Loki configuration"
git push origin main

# ArgoCD auto-syncs within 3 minutes
# Or force immediate sync:
kubectl patch application loki -n platform \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge
```

## Access

### Loki API Endpoint

**Internal (Grafana uses this):**
```
http://loki.monitoring.svc.cluster.local:3100
```

**External (for testing):**
```bash
# Port-forward
kubectl port-forward -n monitoring svc/loki 3100:3100

# Query API
curl http://localhost:3100/ready
# Expected: ready

# Get labels
curl -s http://localhost:3100/loki/api/v1/labels | jq

# Query logs
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={namespace="monitoring"}' \
  --data-urlencode 'limit=10' | jq
```

**Note:** Loki has no UI. Access logs through Grafana (Step 3).

### Ingress Configuration

If ingress is enabled:
```
http://loki.homelab.local:30080
```

Add to `/etc/hosts`:
```
192.168.178.36   loki.homelab.local
```

## Verification

### Check Deployment Status

```bash
# Loki pod
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# Expected: loki-0   1/1 or 2/2   Running

# Promtail pods (should be 3, one per node)
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail

# PVC status
kubectl get pvc -n monitoring | grep loki

# Check resource usage
kubectl top pods -n monitoring -l app.kubernetes.io/name=loki
```

### Verify Log Ingestion

```bash
# Check Promtail is sending logs
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=20

# Look for: "Successfully sent batch"

# Port-forward to Loki
kubectl port-forward -n monitoring svc/loki 3100:3100 &

# Check Loki received data
curl -s http://localhost:3100/metrics | grep loki_ingester_streams
# Should show non-zero value

# Query actual logs
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="kubernetes-pods"}' \
  --data-urlencode 'limit=1' | jq '.status'
# Expected: "success"

# Kill port-forward
pkill -f "port-forward.*loki"
```

### Check ServiceMonitor Integration

```bash
# Verify ServiceMonitors exist
kubectl get servicemonitor -n monitoring | grep -E "loki|promtail"

# Check Prometheus is scraping Loki/Promtail metrics
# In Prometheus UI: http://prometheus.homelab.local:30080
# Query: up{job=~"loki|promtail"}
# Expected: 4 targets UP (1 Loki + 3 Promtail)
```

## Troubleshooting

### Loki Pod Pending (Insufficient Memory)

**Symptom:** `loki-0` or cache pods stuck in Pending state

**Cause:** Memory pressure on worker nodes OR chart deploying unwanted cache components

**Solution:**
```bash
# Check node memory
kubectl top nodes

# Check what pods are deploying
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# If you see cache pods (loki-chunks-cache, loki-results-cache):
# These should NOT exist in SingleBinary mode

# Fix: Explicitly disable in values.yaml
vim platform/loki/values.yaml

# Add:
chunksCache:
  enabled: false
  replicas: 0

resultsCache:
  enabled: false
  replicas: 0

# Delete stuck pods
kubectl delete pods -n monitoring -l app.kubernetes.io/name=loki --force
```

### No Logs Being Collected

**Symptom:** Loki queries return empty results

**Debug:**
```bash
# 1. Check Promtail is running on all nodes
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail -o wide
# Expected: 3 pods, one per node

# 2. Check Promtail logs for errors
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=50

# Look for errors like:
# - "connection refused" → Loki service not accessible
# - "permission denied" → Promtail can't read log files
# - "client stream closed" → Network issues

# 3. Check Promtail can reach Loki
kubectl exec -n monitoring -it <promtail-pod> -- wget -O- http://loki:3100/ready
# Expected: ready

# 4. Check Loki ingester is accepting data
kubectl logs -n monitoring loki-0 | grep -i error
```

### Loki Out of Disk Space

**Symptom:** Loki pod crashes with "no space left on device"

**Solution:**
```bash
# Check PVC usage
kubectl exec -n monitoring loki-0 -- df -h /loki

# Option 1: Reduce retention
vim platform/loki/values.yaml
# Change: retention_period: 168h → 72h (3 days)

# Option 2: Increase PVC size
vim platform/loki/values.yaml
# Change: size: 10Gi → 20Gi

# Then expand the PVC
kubectl patch pvc storage-loki-0 -n monitoring \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

### Promtail High CPU Usage

**Symptom:** Promtail pods consuming >200m CPU

**Cause:** Too aggressive scraping or high log volume

**Solution:**
```bash
# Reduce scrape frequency
vim platform/loki/promtail-values.yaml

# Add rate limiting:
resources:
  limits:
    cpu: 200m  # Cap CPU usage
```

### Grafana Can't Query Loki

**Symptom:** Grafana shows "Loki datasource not working"

**Debug:**
```bash
# Check Loki service is accessible from Grafana
kubectl run curl-test --image=curlimages/curl -it --rm -- \
  curl http://loki.monitoring.svc.cluster.local:3100/ready

# Expected: ready

# Check Loki logs for query errors
kubectl logs -n monitoring loki-0 --tail=100 | grep -i error
```

## LogQL Query Examples

### Basic Queries

```logql
# All logs from monitoring namespace
{namespace="monitoring"}

# Logs from specific pod
{pod="prometheus-prometheus-prometheus-0"}

# Logs from all Promtail agents
{job="promtail"}

# Filter by log content (regex)
{namespace="monitoring"} |~ "error|Error|ERROR"

# Exclude debug logs
{namespace="monitoring"} != "debug"
```

### Advanced Queries

```logql
# Count errors per minute
sum(rate({namespace="monitoring"} |~ "error" [1m]))

# Logs from multiple namespaces
{namespace=~"monitoring|kube-system"}

# Parse JSON logs and filter
{namespace="monitoring"} | json | level="error"

# Show only specific fields
{pod="loki-0"} | logfmt | line_format "{{.level}} - {{.msg}}"
```

### Performance Tips

```logql
# Use label filters first (indexed)
{namespace="monitoring", pod="loki-0"}  # Fast

# Avoid full-text regex without labels (slow)
{} |~ "error"  # Very slow, scans all logs

# Use time ranges
{namespace="monitoring"}[5m]  # Last 5 minutes only
```

## Production Comparison

| Aspect | Homelab (Current) | Enterprise Production |
|--------|-------------------|----------------------|
| Deployment | SingleBinary | Microservices (distributed) |
| Storage | Filesystem (10Gi PVC) | S3/GCS (unlimited) |
| Retention | 7 days | 30-90+ days |
| Replicas | 1 | 3+ with anti-affinity |
| High Availability | No (single pod) | Yes (multi-AZ) |
| Query Cache | Disabled | Redis/Memcached cluster |
| Ingestion | 3GB/day | TB/day+ |
| Backup | None | S3 lifecycle policies |
| Auth | None | OAuth2/OIDC |

**Cloud Cost Equivalent (AWS):**
- CloudWatch Logs Insights: ~$0.50/GB ingested + $0.005/GB scanned
- 3GB/day × 30 days = 90GB/month
- Ingestion: $45/month
- Queries: ~$10/month (assuming 2GB scanned/day)
- **Total**: ~$55/month vs homelab ~$0

## Integration Points

### Current Integrations
- **Prometheus**: ServiceMonitor for metrics scraping
- **nginx-ingress**: Optional ingress for external access
- **local-path-provisioner**: Persistent storage

### Future Integrations (Step 3+)
- **Grafana**: Primary log visualization UI
- **Alertmanager**: Log-based alerting (via Grafana)
- **Tempo**: Trace-log correlation (Phase 7+)

## LogCLI Usage

Install LogCLI for command-line log access:

```bash
# Install
wget https://github.com/grafana/loki/releases/download/v2.9.3/logcli-linux-amd64.zip
unzip logcli-linux-amd64.zip
sudo mv logcli-linux-amd64 /usr/local/bin/logcli

# Configure (with port-forward running)
export LOKI_ADDR=http://localhost:3100

# Query logs
logcli query '{namespace="monitoring"}'

# Follow logs in real-time
logcli query --tail '{pod="prometheus-prometheus-prometheus-0"}'

# Query with time range
logcli query --since=1h '{job="kubernetes-pods"}' --limit=50
```

## Maintenance

### Log Retention Management

```bash
# Check current log volume
kubectl exec -n monitoring loki-0 -- du -sh /loki/chunks

# Manually trigger compaction (if needed)
kubectl exec -n monitoring loki-0 -- wget -O- --post-data='' \
  http://localhost:3100/loki/api/v1/compact
```

### Upgrade Chart Version

```bash
# Check current version
kubectl get application loki -n platform -o yaml | grep targetRevision

# Update to new version
vim platform/argocd/apps/loki-app.yaml
# Change: targetRevision: 6.20.0 → 6.21.0

# Review changelog
# https://github.com/grafana/loki/releases

git add platform/argocd/apps/loki-app.yaml
git commit -m "chore(logging): upgrade Loki to v6.21.0"
git push
```

### Backup Strategy

**Current:** No automated backups (7-day retention acceptable)

**Future** (if needed):
```bash
# Snapshot PVC
kubectl exec -n monitoring loki-0 -- tar czf /tmp/loki-backup.tar.gz /loki

# Copy out
kubectl cp monitoring/loki-0:/tmp/loki-backup.tar.gz ./loki-backup-$(date +%Y%m%d).tar.gz
```

## Common Patterns

### Application Log Integration

To make your app logs searchable in Loki:

**Option 1: Automatic (no code changes)**
- Promtail automatically collects all pod logs
- Just ensure pod logs to stdout/stderr
- Labels extracted: namespace, pod, container

**Option 2: Custom labels**
Add labels to your pod spec:
```yaml
metadata:
  labels:
    app: myapp
    component: backend
    version: v1.2.3
```
Promtail extracts these automatically.

**Option 3: Structured logging**
Log as JSON for better parsing:
```json
{"level":"info","msg":"Request processed","duration_ms":45}
```
Query in Grafana:
```logql
{app="myapp"} | json | duration_ms > 100
```

## Related Documentation

- **ADR**: `docs/adr/010-observability-stack-architecture.md`
- **ArgoCD Apps**: 
  - `platform/argocd/apps/loki-app.yaml`
  - `platform/argocd/apps/promtail-app.yaml`
- **Prometheus Integration**: `platform/prometheus/README.md`
- **Grafana Setup** (Step 3): `platform/grafana/README.md`
- **Loki Docs**: https://grafana.com/docs/loki/latest/
- **LogQL Reference**: https://grafana.com/docs/loki/latest/logql/

---

**Last Updated**: 2026-02-07