# ADR 010: Observability Stack Architecture

## Status
Accepted

## Context
Need comprehensive observability for 3-node Kubernetes homelab with:
- Limited resources (~10GB RAM available)
- Production-pattern demonstration for career advancement
- GitOps-managed everything via ArgoCD

## Decision
Implement four-component stack:
1. **kube-prometheus-stack** (Prometheus + Alertmanager + Operator)
2. **Loki** (log aggregation with filesystem storage)
3. **Promtail** (log collection DaemonSet)
4. **Grafana** (separate from prometheus-stack bundle)

### Key Choices
- **Prometheus Operator over standalone:** CRD-based ServiceMonitors enable dynamic scraping
- **Separate Grafana:** Better GitOps separation, matches enterprise patterns
- **Loki filesystem mode:** Chose simplicity over MinIO for homelab scale
- **15-day retention:** Balances storage (50GB) with useful history

## Consequences

### Positive
- ServiceMonitor pattern = interview talking point about Kubernetes-native monitoring
- Separate Grafana = cleaner ownership model, easier to version control dashboards
- Resource-optimized (~4GB total) = fits homelab budget
- Full metrics + logs = complete observability story

### Negative
- Loki filesystem mode = less "cloud-native" than S3 backend
- Single replicas = no HA (acceptable for homelab)
- Manual dashboard management = need to version control JSON files

### Enterprise Differences
| Aspect | Homelab | Enterprise |
|--------|---------|------------|
| Storage | Filesystem | S3/GCS/Azure Blob |
| Replicas | 1 | 3+ with anti-affinity |
| Retention | 15d | 30-90d+ |
| Alerting | Basic | PagerDuty/Opsgenie integration |

## Compliance
Maps to production patterns: Prometheus Operator, ServiceMonitor CRDs, separate data sources.