# ADR-003: Kubernetes Distribution Selection

## Status

Accepted

## Date

2025-12-20

## Context

Need to select a Kubernetes distribution for a 3-node homelab cluster (1 control plane, 2 workers) running on Proxmox VMs. Requirements:

- Production-aligned architecture and tooling
- Full control over cluster components
- Standard Kubernetes APIs (no proprietary abstractions)
- Suitable for learning cluster lifecycle management

## Decision

Use **kubeadm** to bootstrap a vanilla Kubernetes cluster (v1.31.x).

## Rationale

| Criteria | kubeadm | k3s | RKE2 |
|----------|---------|-----|------|
| Production alignment | ✅ Identical to enterprise | ⚠️ Lightweight variant | ✅ Enterprise-grade |
| Learning depth | ✅ Full exposure to components | ⚠️ Abstracts complexity | ⚠️ Rancher-specific tooling |
| Resource usage | ⚠️ Higher (~2GB control plane) | ✅ Low (~512MB) | ⚠️ Higher |
| Component control | ✅ Full (etcd, API server, etc.) | ❌ Embedded (SQLite default) | ✅ Full |
| Cluster upgrades | ✅ Standard kubeadm upgrade | ✅ Simple binary replacement | ⚠️ Rancher-managed |
| Industry adoption | ✅ Foundation for EKS, AKS, GKE | ✅ Edge/IoT popular | ⚠️ Rancher ecosystem |
| CNI flexibility | ✅ Any CNI | ⚠️ Flannel default | ✅ Any CNI |

**Key factors:**

1. **Production equivalence** — kubeadm clusters are architecturally identical to managed Kubernetes (EKS, AKS, GKE use similar bootstrap processes).

2. **Component visibility** — Separate etcd, kube-apiserver, kube-scheduler, and kube-controller-manager pods provide full observability into control plane operations.

3. **Upgrade experience** — `kubeadm upgrade` workflow mirrors enterprise cluster lifecycle management.

4. **No vendor abstraction** — Pure upstream Kubernetes without distribution-specific tooling or defaults.

## Consequences

### Positive

- Deep understanding of Kubernetes architecture and components
- Skills directly transferable to enterprise Kubernetes environments
- Full flexibility in CNI, storage, and add-on selection
- Standard troubleshooting patterns apply (kubectl, crictl, journalctl)

### Negative

- Higher resource consumption than lightweight alternatives
- More manual setup (CNI, storage provisioner not included)
- No built-in HA for control plane (requires additional configuration)

## Alternatives Considered

### k3s

Rejected for primary cluster due to:
- SQLite default replaces etcd (different architecture)
- Bundled components reduce learning exposure
- Traefik/Flannel defaults would need to be disabled anyway

**Note:** k3s remains a good choice for edge deployments or resource-constrained environments.

### RKE2

Rejected due to:
- Rancher-specific tooling adds abstraction layer
- Smaller community outside Rancher ecosystem
- Overkill for single-cluster homelab

### Managed Kubernetes (EKS, AKS, GKE)

Rejected due to:
- Ongoing cloud costs
- Control plane is abstracted (no access to etcd, API server config)
- Goal is to learn infrastructure layer, not just workload deployment

## References

- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Kubernetes Components](https://kubernetes.io/docs/concepts/overview/components/)
- [kubeadm Cluster Upgrade](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
