# Prometheus Observability Stack

Enterprise-grade metrics collection and monitoring for Kubernetes homelab using kube-prometheus-stack.

## Overview

Deploys the complete Prometheus Operator stack for metrics collection, storage, alerting, and service discovery using Kubernetes-native CRDs.

**Components:**
- Prometheus Operator (manages Prometheus instances)
- Prometheus Server (metrics collection & TSDB storage)
- Alertmanager (alert routing)
- node-exporter (hardware/OS metrics, DaemonSet)
- kube-state-metrics (Kubernetes object metrics)

**NOT included:** Grafana (deployed separately in `platform/grafana/`)

## Architecture

```
┌─────────────────────────────────────────────┐
│         kube-prometheus-stack               │
├─────────────────────────────────────────────┤
│                                             │
│  ┌──────────────┐    ┌─────────────────┐    │
│  │  Prometheus  │◄───┤ ServiceMonitors │    │
│  │   Operator   │    │      (CRDs)     │    │
│  └──────┬───────┘    └─────────────────┘    │
│         │ Manages                           │
│         ▼                                   │
│  ┌──────────────┐    ┌──────────────┐       │
│  │  Prometheus  │◄───┤ Alertmanager │       │
│  │    Server    │    └──────────────┘       │
│  │ (StatefulSet)│                           │
│  └──────┬───────┘                           │
│         │ Scrapes                           │
│         ├──────────────┐                    │
│         ▼              ▼                    │
│  ┌─────────────┐  ┌─────────────┐           │
│  │node-exporter│  │kube-state-  │           │
│  │ (DaemonSet) │  │  metrics    │           │
│  └─────────────┘  └─────────────┘           │
└─────────────────────────────────────────────┘
         │
         │ nginx-ingress (NodePort 30080)
         ▼
  http://prometheus.homelab.local:30080
```

## Resource Allocation

| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| Prometheus | 1 | 200m / - | 1Gi / 2Gi | 50Gi PVC |
| Alertmanager | 1 | 50m / - | 128Mi / 256Mi | 5Gi PVC |
| Operator | 1 | 100m / - | 128Mi / 256Mi | - |
| kube-state-metrics | 1 | 50m / - | 200Mi / 400Mi | - |
| node-exporter | 3 | 50m / - | 100Mi / 200Mi | - |
| **Total** | - | **~500m** | **~1.8Gi / 3.5Gi** | **55Gi** |

*Format: request / limit*

## Configuration

### Data Retention
- **Time**: 15 days
- **Size**: 45GB (90% of 50GB PVC)
- **Rationale**: Balances history with homelab storage limits

### Storage Backend
- **Current**: local-path-provisioner (node-local)
- **Phase 8**: Migration to Longhorn (distributed HA storage)
- **Risk**: Data loss on node failure (acceptable for short-retention metrics)

### Service Discovery
```yaml
serviceMonitorSelectorNilUsesHelmValues: false
```
- Discovers ALL ServiceMonitors cluster-wide (no label filtering)
- Auto-discovers new apps that expose metrics

### Expected DOWN Targets
These are **normal** and not issues:
- `kube-controller-manager` - metrics on localhost only (security)
- `kube-scheduler` - metrics on localhost only (security)  
- `kube-etcd` - not exposed in this configuration
- `kube-proxy` - Calico CNI may replace functionality

**Critical targets (MUST be UP):**
- kubernetes-apiservers
- kubernetes-nodes
- node-exporter
- kube-state-metrics
- prometheus-operator

## Deployment

### Prerequisites
- ArgoCD operational
- nginx-ingress controller
- StorageClass available

### GitOps Flow
```bash
# 1. Edit configuration
vim platform/prometheus/values.yaml

# 2. Commit and push
git add platform/prometheus/values.yaml
git commit -m "feat(monitoring): update prometheus config"
git push origin main

# 3. ArgoCD auto-syncs within 3 minutes
# Or force immediate sync:
kubectl patch application kube-prometheus-stack -n platform \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge
```

**Managed by:**
- ArgoCD App: `platform/argocd/apps/kube-prometheus-stack-app.yaml`
- Helm Values: `platform/prometheus/values.yaml`
- Chart: `prometheus-community/kube-prometheus-stack v65.8.1`

## Access

### URLs
- **Prometheus**: http://prometheus.homelab.local:30080
- **Alertmanager**: http://alertmanager.homelab.local:30080
- **Auth**: None (internal cluster access only)

### DNS Configuration
Add to your `/etc/hosts` (Windows: `C:\Windows\System32\drivers\etc\hosts`):
```
192.168.178.36   prometheus.homelab.local
192.168.178.36   alertmanager.homelab.local
```
*Note: IP is k8s-worker-02 where nginx-ingress pod runs*

## Verification

### Check Deployment
```bash
# ArgoCD application status
kubectl get application kube-prometheus-stack -n platform

# All pods should be Running
kubectl get pods -n monitoring

# PVCs should be Bound
kubectl get pvc -n monitoring

# Ingress should exist
kubectl get ingress -n monitoring
```

### Verify Metrics Collection
Open Prometheus UI and run:

```promql
# Node metrics (expect 3 results)
up{job="node-exporter"}

# Total pod count
count(kube_pod_info)

# Node memory available
node_memory_MemAvailable_bytes
```

Navigate to **Status → Targets** - verify critical targets are UP.

### Test HTTP Access
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://prometheus.homelab.local:30080
# Expected: 200

curl -s -o /dev/null -w "%{http_code}\n" http://alertmanager.homelab.local:30080
# Expected: 200
```

## Troubleshooting

### ArgoCD Shows "Degraded"

**Cause 1: PVC Unbound**
```bash
kubectl get pvc -n monitoring
# If "Pending", install local-path-provisioner
```

**Cause 2: CRD Sync Failure**
```bash
# Verify syncOptions includes:
# - ServerSideApply=true
# - Replace=true
kubectl get application kube-prometheus-stack -n platform -o yaml | grep -A5 syncOptions
```

### No Ingress Created

**Symptom**: `kubectl get ingress -n monitoring` returns nothing

**Cause**: Ingress config in wrong YAML location

**Fix**: Ingress must be at service level:
```yaml
# ✅ CORRECT
prometheus:
  ingress:
    enabled: true
  prometheusSpec:
    # spec config here

# ❌ WRONG
prometheus:
  prometheusSpec:
    ingress:
      enabled: true
```

### Queries Return Empty Results

**Debug:**
1. Check **Status → Targets** in Prometheus UI
2. Verify critical targets UP (see "Expected DOWN Targets" above)
3. Check ServiceMonitors exist:
   ```bash
   kubectl get servicemonitor -A
   ```
4. Check Prometheus logs:
   ```bash
   kubectl logs -n monitoring prometheus-prometheus-prometheus-0 -c prometheus
   ```

### Prometheus OOM (Out of Memory)

**Solution**: Reduce retention or increase limits
```yaml
prometheus:
  prometheusSpec:
    retention: 7d          # reduce from 15d
    retentionSize: "20GB"  # reduce from 45GB
    resources:
      limits:
        memory: 3Gi        # increase from 2Gi
```

## Useful PromQL Queries

### Cluster Health
```promql
# Node CPU usage %
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node memory usage %
100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)

# Disk usage %
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)

# Pods per node
count by (node) (kube_pod_info)
```

### Kubernetes Objects
```promql
# Pods not running
kube_pod_status_phase{phase!="Running"} == 1

# Failed pods
kube_pod_status_phase{phase="Failed"} == 1

# Deployments with unavailable replicas
kube_deployment_status_replicas_unavailable > 0

# Pending PVCs
kube_persistentvolumeclaim_status_phase{phase="Pending"} == 1
```

### Prometheus Health
```promql
# Memory usage
process_resident_memory_bytes{job="prometheus"}

# Time series count
prometheus_tsdb_symbol_table_size_bytes

# Failed scrapes
rate(prometheus_target_scrapes_exceeded_sample_limit_total[5m])
```

## ServiceMonitor Pattern

Applications expose metrics by creating a ServiceMonitor:

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

Prometheus auto-discovers and scrapes this endpoint.

## Production Comparison

| Aspect | Homelab | Enterprise |
|--------|---------|------------|
| Storage | local-path (node-local) | Longhorn/Ceph/Cloud |
| Replicas | 1 | 3+ with anti-affinity |
| Retention | 15 days | 30-90+ days |
| Ingress | NodePort 30080 | LoadBalancer/Cloud LB |
| Auth | None | OAuth2/OIDC |
| Alerting | Basic | PagerDuty/Opsgenie |
| Backup | None | S3 snapshots |

**Cloud Cost Equivalent (AWS):**
- Managed Prometheus: $50-100/month
- Storage (55GB EBS): $6/month
- ALB + data transfer: $20/month
- **Total**: ~$76-126/month vs homelab ~$5/month

## Maintenance

### Chart Upgrade
```bash
# Update targetRevision in ArgoCD app manifest
vim platform/argocd/apps/kube-prometheus-stack-app.yaml
# Change: targetRevision: 65.8.1 → 66.0.0

# Review changelog first
# https://github.com/prometheus-community/helm-charts/releases

git add platform/argocd/apps/kube-prometheus-stack-app.yaml
git commit -m "chore(monitoring): upgrade prometheus stack to v66.0.0"
git push
```

### Retention Changes
```bash
# Edit values
vim platform/prometheus/values.yaml

# Adjust:
prometheus:
  prometheusSpec:
    retention: 30d
    retentionSize: "90GB"

# Commit and push (ArgoCD syncs)

# Resize PVC if needed:
kubectl patch pvc prometheus-prometheus-db-prometheus-prometheus-prometheus-0 \
  -n monitoring -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

### Manual Backup (Future)
```bash
# Create snapshot
kubectl exec -n monitoring prometheus-prometheus-prometheus-0 -c prometheus -- \
  tar czf /prometheus/snapshot-$(date +%Y%m%d).tar.gz /prometheus/data

# Copy out
kubectl cp monitoring/prometheus-prometheus-prometheus-0:/prometheus/snapshot-*.tar.gz ./
```

## Related Documentation

- **ADR**: `docs/adr/010-observability-stack-architecture.md`
- **ArgoCD App**: `platform/argocd/apps/kube-prometheus-stack-app.yaml`
- **Chart Source**: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack

## Contributing

When making changes:
1. Update this README if architecture changes
2. Add comments in values.yaml explaining choices
3. Test in separate branch first
4. Use conventional commits: `feat(monitoring):`, `fix(monitoring):`
5. Document significant decisions in ADR

---

**Last Updated**: 2026-02-07  
**Chart Version**: v65.8.1  
**Kubernetes**: v1.31.4
