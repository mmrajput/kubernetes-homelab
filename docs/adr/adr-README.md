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

| ADR | Decision | Status |
|-----|----------|--------|
| [ADR-001](ADR-001-hardware-selection.md) | Mini PC over Raspberry Pi / Cloud | Accepted |
| [ADR-002](ADR-002-hypervisor-selection.md) | Proxmox VE as hypervisor | Accepted |
| [ADR-003](ADR-003-kubernetes-distribution.md) | kubeadm over k3s / RKE2 | Accepted |
| [ADR-004](ADR-004-cni-selection.md) | Calico over Cilium / Flannel | Accepted |
| [ADR-005](ADR-005-devcontainer.md) | DevContainer for tooling isolation | Accepted |
| [ADR-006](ADR-006-gitops-tool.md) | ArgoCD over Flux CD | Accepted |
| [ADR-007](ADR-007-ingress-strategy.md) | nginx-ingress with NodePort | Accepted |
| [ADR-008](ADR-008-app-of-apps-pattern.md) | App-of-Apps for GitOps structure | Accepted |
| [ADR-009](ADR-009-storage-strategy.md) | local-path-provisioner (Longhorn planned) | Accepted |

## Adding New ADRs

1. Copy the template structure from an existing ADR
2. Use the next sequential number: `ADR-0XX-descriptive-name.md`
3. Update this README index
4. Commit with: `docs(adr): add ADR-0XX description`
