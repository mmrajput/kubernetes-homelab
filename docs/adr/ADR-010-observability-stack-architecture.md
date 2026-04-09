# ADR-010: Observability Stack Architecture

## Status

Accepted — Updated Phase 8 (Loki storage migrated to MinIO)

## Date

2026-01-20 — Initial decision
2026-03-17 — Updated: Loki storage backend changed from filesystem to MinIO (S3)

## Context

Need comprehensive observability for 3-node Kubernetes homelab with:
- Limited resources (~10GB RAM available)
- Production-pattern demonstration for career advancement
- GitOps-managed everything via ArgoCD

## Decision

Implement four-component stack:
1. **kube-prometheus-stack** (Prometheus + Alertmanager + Operator)
2. **Loki** (log aggregation with MinIO S3 backend)
3. **Promtail** (log collection DaemonSet)
4. **Grafana** (separate from prometheus-stack bundle)

### Key Choices

- **Prometheus Operator over standalone:** CRD-based ServiceMonitors enable dynamic scraping without reconfiguration when services are added.
- **Separate Grafana:** Better GitOps separation, matches enterprise patterns where dashboards and data sources are independently managed.
- **Loki MinIO S3 backend:** Initial Phase 6 deployment used filesystem mode for simplicity. Migrated to MinIO in Phase 8 when object storage became available. MinIO is the authoritative log storage backend — Loki does not use a PVC.
- **15-day retention:** Balances storage with useful history at homelab scale.

## Consequences

### Positive

- ServiceMonitor pattern = Kubernetes-native monitoring, maps directly to enterprise Prometheus Operator deployments
- Separate Grafana = cleaner ownership model, easier to version control dashboards
- Resource-optimized (~4GB total) = fits homelab budget
- Loki + MinIO = production-equivalent S3 log storage pattern (maps to enterprise Loki + S3/GCS)
- Full metrics + logs = complete observability story

### Negative

- Single replicas = no HA (acceptable for homelab)
- Manual dashboard management = JSON files must be version controlled in Git

### Enterprise Differences

| Aspect | Homelab | Enterprise |
|--------|---------|------------|
| Log storage | MinIO (in-cluster S3) | AWS S3 / GCS / Azure Blob |
| Metric storage | local-path PVC | Thanos / Cortex / cloud-managed |
| Replicas | 1 | 3+ with anti-affinity |
| Retention | 15d | 30-90d+ |
| Alerting | Basic rules | PagerDuty / Opsgenie integration |

## Compliance

Maps to production patterns: Prometheus Operator, ServiceMonitor CRDs, S3-backed Loki, separate data sources.