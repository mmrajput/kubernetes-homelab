# ADR-007: Ingress Strategy

## Status

Accepted — Updated Phase 7 (TLS), Phase 9 (Cloudflare Tunnel), Phase 10 (ClusterIP)

## Date

2026-01-10 — Initial decision (nginx-ingress + NodePort)
2026-02-15 — Updated: cert-manager TLS implemented (Phase 7)
2026-03-20 — Updated: Cloudflare Tunnel external access + custom domain (Phase 9)
2026-04-09 — Updated: service type changed from NodePort to ClusterIP (Phase 10)

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

**All access via Cloudflare Tunnel (Phase 10+):**
```
Internet → Cloudflare CDN/WAF → Cloudflare Tunnel (outbound) → ingress-nginx ClusterIP → Ingress → Service → Pods
```

The `cloudflared` daemon initiates an outbound connection to Cloudflare and routes traffic directly to the ingress-nginx ClusterIP service (`http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80`). No open inbound ports on the router or cluster nodes. Public services are authenticated via Cloudflare Access before traffic reaches the cluster.

Domain: `mmrajputhomelab.org` (e.g., `argocd.mmrajputhomelab.org`, `grafana.mmrajputhomelab.org`).

**Service type:** `ClusterIP` — NodePort was used in Phases 1–9 for direct LAN access and as a fallback. Removed in Phase 10 once Cloudflare Tunnel was confirmed to use the ClusterIP URL directly, enforcing consistent zero-trust access for all clients.

## Consequences

### Positive

- Production-equivalent Ingress resource definitions
- Easy to add new services (create Ingress manifest)
- TLS termination via cert-manager wildcard certificate (`wildcard-homelab-tls`)
- Cloudflare WAF + Access provides zero-trust external access with no open inbound ports
- Skills transfer directly to cloud Ingress patterns (ALB Ingress, GKE Ingress)

### Negative

- Single ingress controller replica — no HA (acceptable for homelab)
- Cloudflare Tunnel adds an external dependency — if Cloudflare is unreachable, use `kubectl port-forward` for emergency access
- No direct LAN access without `kubectl port-forward`

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

## Implementation History

- **cert-manager (Phase 7)** — Wildcard TLS certificate via Cloudflare DNS-01 challenge. Shared `wildcard-homelab-tls` secret distributed to all ingress namespaces.
- **Cloudflare Tunnel (Phase 9)** — Zero-trust external access without open inbound ports. `cloudflared` runs as a Deployment (2 replicas) in the `cloudflare` namespace.
- **ClusterIP service (Phase 10)** — Service type changed from NodePort to ClusterIP. NodePort was unnecessary once the tunnel was confirmed to use the ClusterIP URL directly.
- **MetalLB** — Not adopted; Cloudflare Tunnel satisfies the external access requirement without an additional IP management layer.

## References

- [nginx-ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Ingress Concepts](https://kubernetes.io/docs/concepts/services-networking/ingress/)
