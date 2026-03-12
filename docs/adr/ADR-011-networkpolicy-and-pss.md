# ADR-011: NetworkPolicy Design and Pod Security Standards Implementation

**Status:** Accepted  
**Date:** March 2026  
**Author:** Mahmood Rajput  
**Phase:** Phase 7 — Security Hardening  

---

## Context

After deploying the core platform stack, the cluster had no network isolation between namespaces and no pod-level security enforcement. Any compromised pod could freely communicate with any other service, and containers could run as root with full Linux capabilities.

Two complementary controls were needed: NetworkPolicies to restrict traffic flow, and Pod Security Standards (PSS) to restrict what containers can do on the host.

For implementation detail, commands, and troubleshooting see `docs/guide/security-hardening.md`.

---

## Decisions

### 1 — NetworkPolicy: Default-Deny with Namespace Boundary Rules

Default-deny applied to every namespace. Explicit allow rules use `namespaceSelector` rather than `podSelector`.

**Why default-deny:** Without it, Kubernetes allows all pod-to-pod traffic. Default-deny forces every communication path to be explicitly declared — the correct posture for PCI-DSS, SOC 2, and most enterprise security frameworks.

**Why namespace boundary over pod-level selectors:** Pod labels change during Helm upgrades and break pod-level policies. Namespace names are stable. For a single-tenant homelab platform, namespace boundary is the appropriate granularity — the threat model is lateral movement prevention, not tenant isolation.

In production, pod-level policies would be added on top of namespace boundary policies for workloads handling sensitive data (payment services, auth services).

### 2 — Kubernetes API Egress: Both ClusterIP and Node IP Required

Namespaces that need API server access must allow both `10.96.0.1/32` (kubernetes ClusterIP) and `192.168.178.34/32` (control plane node IP), on ports 443 and 6443.

**Why:** Calico evaluates NetworkPolicy rules before kube-proxy applies DNAT translation. A connection to `10.96.0.1:443` is translated by kube-proxy to `192.168.178.34:6443` — Calico then evaluates the translated destination and blocks it unless the node IP is explicitly allowed. Allowing only the ClusterIP causes silent timeouts that manifest as unrelated application errors (e.g. ArgoCD nil pointer dereferences).

**Affected namespaces:** `platform`, `cert-manager`, `monitoring`.

### 3 — nginx-ingress Egress Uses Pod Ports, Not Service Ports

NetworkPolicy egress rules from `ingress-nginx` must reference container ports (e.g. Grafana: 3000, ArgoCD: 8080), not service ports (80).

**Why:** nginx-ingress uses the Endpoints API to connect directly to pod IPs, bypassing kube-proxy and service port mapping entirely. A rule allowing port 80 to reach Grafana is silently ineffective.

### 4 — PSS: Baseline for Monitoring, Restricted Everywhere Else

| Namespace | Enforce | Reason |
|-----------|---------|--------|
| platform | restricted | ArgoCD runs as non-root, no host access needed |
| cert-manager | restricted | Well-hardened chart |
| ingress-nginx | restricted | Supports restricted PSS |
| cloudflare | restricted | Runs as non-root (UID 65532) |
| monitoring | baseline | node-exporter requires hostPID, hostNetwork, hostPort by design |

All namespaces set `audit: restricted` and `warn: restricted` to surface violations without breaking workloads.

**Why monitoring cannot enforce restricted:** node-exporter requires host-level access to read process, network, and IPC metrics. These are blocked by `restricted` PSS. This is a permanent, accepted constraint — not a gap to resolve.

**Why security hardening before stateful workloads:** Retrofitting security controls onto existing workloads is significantly harder. A compromised application with no network isolation has lateral movement access to ArgoCD, Prometheus, and cert-manager private keys. Production environments define security requirements before application deployment — this homelab follows the same pattern.

---

## Consequences

**Positive:**
- All inter-namespace traffic is explicitly declared and auditable
- Compromised pod blast radius limited to its own namespace
- PSS enforcement prevents common container escape techniques
- Fully GitOps managed via ArgoCD

**Negative / Trade-offs:**
- NetworkPolicy debugging is more complex — requires checking both allow and default-deny rules
- The Calico DNAT behaviour (Decision 2) caused significant debugging time before root cause was identified
- Adding new workloads requires explicit NetworkPolicy updates before the app can communicate
- monitoring namespace permanently enforces `baseline` — an accepted constraint given node-exporter and Promtail requirements

**Completed (Phase 7):**
- Loki security context fixed — `podSecurityContext` and `containerSecurityContext` moved to `loki:` key in Helm values; now `restricted` PSS compliant
- Promtail documented as accepted `baseline` constraint — host log access is its core function
- RBAC hardening complete — see ADR-012

**Known gaps (future work):**
- External Secrets Operator — remove manual secret creation from bootstrap procedure
- Falco — runtime anomaly detection to complement NetworkPolicy and PSS

---

## References

- `docs/guide/security-hardening.md` — implementation detail, commands, and troubleshooting
- ADR-012 — RBAC hardening and ServiceAccount token management
- [Kubernetes NetworkPolicy documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Calico NetworkPolicy](https://docs.tigera.io/calico/latest/network-policy/get-started/kubernetes-policy/kubernetes-network-policy)
