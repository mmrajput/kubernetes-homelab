# ADR-007: Ingress Strategy

## Status

Accepted

## Date

2026-01-10

## Context

Kubernetes services need external access for browser-based UIs (ArgoCD, Grafana) and applications. Options for exposing services in a bare-metal homelab environment:

- kubectl port-forward
- NodePort services
- LoadBalancer with MetalLB
- Ingress controller with various backends

Requirements:
- Persistent access (survives terminal disconnection)
- Hostname-based routing for multiple services
- Production-aligned pattern
- Minimal infrastructure overhead

## Decision

Use **nginx-ingress controller** with **NodePort backend** (ports 30080/30443).

## Rationale

| Criteria | port-forward | NodePort | MetalLB + LB | Ingress + NodePort |
|----------|--------------|----------|--------------|-------------------|
| Persistence | ❌ Dies with terminal | ✅ Persistent | ✅ Persistent | ✅ Persistent |
| Hostname routing | ❌ No | ❌ No | ❌ No (IP only) | ✅ Yes |
| Multiple services | ❌ One per command | ⚠️ Port per service | ⚠️ IP per service | ✅ Single entrypoint |
| Production pattern | ❌ Debug only | ⚠️ Dev only | ✅ Yes | ✅ Yes |
| Setup complexity | ✅ None | ✅ Low | ⚠️ Medium | ⚠️ Medium |
| Scalability | ❌ Poor | ❌ Poor | ✅ Good | ✅ Good |

**Key factors:**

1. **Hostname-based routing** — Access services via `argocd.homelab.local`, `grafana.homelab.local` instead of remembering ports.

2. **Single entrypoint** — All HTTP traffic through ports 30080/30443, regardless of number of services.

3. **Production alignment** — Ingress resources are the standard pattern in enterprise Kubernetes (ALB Ingress, GKE Ingress, etc.).

4. **No additional infrastructure** — MetalLB requires IP pool management and ARP/BGP configuration, unnecessary for homelab scale.

## Implementation

```
Internet/LAN → NodePort (30080/30443) → nginx-ingress → Ingress → Service → Pods
```

DNS resolution via `/etc/hosts`:
```
192.168.178.34  argocd.homelab.local
192.168.178.34  grafana.homelab.local
```

## Consequences

### Positive

- Production-equivalent Ingress resource definitions
- Easy to add new services (create Ingress manifest, add hosts entry)
- TLS termination ready (cert-manager integration in future)
- Skills transfer directly to cloud Ingress patterns

### Negative

- Non-standard ports (30080 instead of 80)
- Manual `/etc/hosts` management for DNS
- No automatic failover (single ingress controller replica)

## Alternatives Considered

### kubectl port-forward

Rejected due to:
- Dies when terminal closes
- One command per service
- Not a production pattern

### Direct NodePort per service

Rejected due to:
- Must remember port per service (ArgoCD:30080, Grafana:30081, etc.)
- No hostname routing
- Doesn't scale beyond a few services

### MetalLB LoadBalancer

Rejected due to:
- Additional component to manage
- Requires dedicated IP pool
- Overkill for single-node ingress
- Adds complexity without proportional benefit at homelab scale

**Note:** MetalLB is appropriate for multi-replica ingress controllers or services requiring dedicated IPs.

## Future Considerations

- **cert-manager** — Automate TLS certificates with Let's Encrypt
- **External DNS** — Automate DNS records (if using Pi-hole or similar)
- **MetalLB** — Revisit if adding HA ingress or dedicated service IPs

## References

- [nginx-ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Ingress Concepts](https://kubernetes.io/docs/concepts/services-networking/ingress/)
