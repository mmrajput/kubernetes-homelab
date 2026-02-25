# Architecture Decision Records (ADRs)

This directory contains technical decisions made during homelab design and implementation.

## Format

Each ADR follows this structure:
- **Status**: Accepted, Proposed, Deprecated, or Superseded
- **Context**: Why this decision was needed
- **Decision**: What was chosen
- **Rationale**: Comparison matrix and key factors
- **Consequences**: Trade-offs and implications
- **Alternatives Considered**: What else was evaluated

## Index

All significant technology choices are documented as Architecture Decision Records (ADRs) with context, trade-off analysis, and rationale:

| ADR | Decision |
|-----|----------|
| [ADR-001](docs/adr/adr-001-hardware-selection.md) | Hardware Platform — Beelink SER5 Pro selected for compact, power-efficient homelab setup |
| [ADR-002](docs/adr/adr-002-hypervisor-selection.md) | Hypervisor Strategy — Proxmox VE chosen over bare-metal deployment |
| [ADR-003](docs/adr/adr-003-kubernetes-distribution.md) | Kubernetes Distribution — kubeadm preferred over k3s/k0s for production-aligned experience |
| [ADR-004](docs/adr/adr-004-cni-selection.md) | Container Networking (CNI) — Calico selected for full NetworkPolicy support |
| [ADR-005](docs/adr/adr-005-devcontainer.md) | Development Environment — DevContainer for reproducible and consistent setup |
| [ADR-006](docs/adr/adr-006-gitops-tool.md) | GitOps Tooling — Argo CD selected over Flux CD |
| [ADR-007](docs/adr/adr-007-ingress-strategy.md) | Ingress Strategy — NGINX Ingress Controller exposed via NodePort |
| [ADR-008](ADR-008-app-of-apps-pattern.md) | GitOps Architecture Pattern — Argo CD App-of-Apps approach |
| [ADR-009](ADR-009-storage-strategy.md) | Storage Strategy — local-path-provisioner (Longhorn planned for future phases) |
| [ADR-010](ADR-010-observability-stack-architecture.md) | Observability Stack — Prometheus, Grafana, and Loki |

## Adding New ADRs

1. Copy the template structure from an existing ADR
2. Use the next sequential number: `ADR-0XX-descriptive-name.md`
3. Update this README index
4. Commit with: `docs(adr): add ADR-0XX description`
