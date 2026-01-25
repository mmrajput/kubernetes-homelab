# ADR-004: CNI Selection

## Status

Accepted

## Date

2024-12-20

## Context

Kubernetes requires a Container Network Interface (CNI) plugin to provide pod networking. The CNI must support:

- Pod-to-pod communication across nodes
- Network policy enforcement
- Compatibility with kubeadm bootstrap
- Reasonable resource footprint for homelab scale

## Decision

Use **Calico** as the CNI plugin.

## Rationale

| Criteria | Calico | Cilium | Flannel |
|----------|--------|--------|---------|
| Network Policy | ✅ Full support | ✅ Full + extended | ❌ None |
| Resource usage | ✅ Moderate (~100MB/node) | ⚠️ Higher (~200MB+/node) | ✅ Low (~50MB/node) |
| eBPF support | ⚠️ Optional | ✅ Native | ❌ No |
| Learning curve | ✅ Moderate | ⚠️ Steeper | ✅ Simple |
| Industry adoption | ✅ Very high | ✅ Growing fast | ✅ High (basic use) |
| Troubleshooting | ✅ Standard iptables | ⚠️ eBPF tooling required | ✅ Simple |
| Documentation | ✅ Excellent | ✅ Excellent | ✅ Good |

**Key factors:**

1. **Network Policy support** — Essential for learning Kubernetes security. Flannel lacks this entirely.

2. **Production prevalence** — Calico is the default CNI for many enterprise deployments and managed Kubernetes offerings.

3. **Balanced complexity** — More capable than Flannel, less operational overhead than Cilium.

4. **iptables-based** — Standard Linux networking makes troubleshooting accessible with familiar tools (`iptables -L`, `tcpdump`).

## Consequences

### Positive

- Full NetworkPolicy support for security learning
- Well-documented troubleshooting procedures
- Skills transfer directly to enterprise environments
- BGP peering capability available for future advanced networking

### Negative

- Higher resource usage than Flannel
- iptables-based dataplane less performant than Cilium's eBPF at scale
- Additional CRDs to understand (IPPool, BGPConfiguration, etc.)

## Alternatives Considered

### Flannel

Rejected due to:
- No NetworkPolicy support (critical gap for learning Kubernetes security)
- Limited feature set for production scenarios
- Would require adding another component (like Calico for policy only) later

### Cilium

Rejected for initial deployment due to:
- eBPF complexity adds troubleshooting overhead
- Higher resource consumption on constrained homelab
- Steeper learning curve for networking fundamentals

**Note:** Cilium is an excellent choice and may be adopted in future iterations once core networking concepts are solid.

### Weave Net

Not evaluated — declining community adoption and development activity.

## Implementation Notes

Calico installed via manifest with default VXLAN encapsulation:

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Pod CIDR: `10.244.0.0/16` (configured during kubeadm init)

## References

- [Calico Documentation](https://docs.tigera.io/calico/latest/about/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Calico vs Cilium Comparison](https://docs.tigera.io/calico/latest/getting-started/kubernetes/helm)
