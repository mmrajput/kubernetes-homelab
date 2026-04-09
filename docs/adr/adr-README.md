# Architecture Decision Records (ADRs)

Technical decisions made during homelab design and implementation, with context, trade-off analysis, and rationale.

## Format

Each ADR follows this structure:

- **Status**: Accepted, Proposed, Deprecated, or Superseded
- **Context**: Why this decision was needed
- **Decision**: What was chosen
- **Rationale**: Comparison matrix and key factors
- **Consequences**: Trade-offs and implications
- **Alternatives Considered**: What else was evaluated

## Index

| ADR | Decision |
|-----|----------|
| [ADR-001](docs/adr/ADR-001-hardware-selection.md) | Hardware Platform — Beelink SER5 Pro (32GB RAM, 500GB NVMe) |
| [ADR-002](docs/adr/ADR-002-hypervisor-selection.md) | Hypervisor — Proxmox VE over bare-metal deployment |
| [ADR-003](docs/adr/ADR-003-kubernetes-distribution.md) | Kubernetes Distribution — kubeadm over k3s/k0s |
| [ADR-004](docs/adr/ADR-004-cni-selection.md) | CNI — Calico for full NetworkPolicy support |
| [ADR-005](docs/adr/ADR-005-devcontainer.md) | Development Environment — DevContainer for reproducible tooling |
| [ADR-006](docs/adr/ADR-006-gitops-tool.md) | GitOps — ArgoCD over Flux CD |
| [ADR-007](docs/adr/ADR-007-ingress-strategy.md) | Ingress — nginx-ingress + Cloudflare Tunnel (no open ports) |
| [ADR-008](docs/adr/ADR-008-app-of-apps-pattern.md) | GitOps Pattern — ArgoCD App-of-Apps with ApplicationSets |
| [ADR-009](docs/adr/ADR-009-storage-strategy.md) | Storage — Longhorn for workloads, local-path for observability |
| [ADR-010](docs/adr/ADR-010-observability-stack-architecture.md) | Observability — kube-prometheus-stack + Loki + Grafana |
| [ADR-011](docs/adr/ADR-011-networkpolicy-and-pss.md) | Security — NetworkPolicy default-deny + Pod Security Standards |
| [ADR-012](docs/adr/ADR-012-secret-management.md) | Secret Management — Vault + External Secrets Operator |
| [ADR-013](docs/adr/ADR-013-cicd-pipeline-strategy.md) | CI/CD — GitHub Actions ARC + image promotion via Git |
| [ADR-014](docs/adr/ADR-014-backup-strategy.md) | Backup — Velero + CNPG Barman + rclone (3-2-1 posture) |
| [ADR-015](docs/adr/ADR-015-identity-provider.md) | Identity — Keycloak as centralised OIDC provider |
| [ADR-016](docs/adr/ADR-016-reference-workload.md) | Reference Workload — Nextcloud as platform validation workload |

## Adding New ADRs

1. Copy the structure from an existing ADR
2. Use the next sequential number: `ADR-0XX-descriptive-name.md`
3. Update this index
4. Commit with: `docs(adr): add ADR-0XX <short description>`
