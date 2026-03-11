# ADR-011: NetworkPolicy Design and Pod Security Standards Implementation

**Status:** Accepted  
**Date:** March 2026  
**Author:** Mahmood Rajput  
**Phase:** Phase 7 — Security Hardening  

---

## Context

After deploying the core platform stack (ArgoCD, cert-manager, nginx-ingress, Prometheus, Loki, Grafana, Cloudflare Tunnel), the cluster had no network isolation between namespaces and no pod-level security enforcement. Any compromised pod could freely communicate with any other pod or service in the cluster, and pods could run as root with full Linux capabilities.

Two controls were needed:

1. **NetworkPolicies** — restrict which namespaces and pods can communicate with each other
2. **Pod Security Standards (PSS)** — enforce security constraints on pod specifications at the namespace level

These are complementary controls. NetworkPolicies restrict network traffic. PSS restricts what a pod is allowed to do on the host. Together they form a defence-in-depth posture at the Kubernetes layer.

---

## Decision 1 — NetworkPolicy Strategy: Namespace Boundary with Default-Deny

### What we decided

Apply a **default-deny-all** NetworkPolicy to every namespace, then add explicit allow rules at the **namespace boundary** rather than at the individual pod level.

Each namespace gets two NetworkPolicy objects:
- `<namespace>-default-deny` — denies all ingress and egress
- `<namespace>-allow` — explicitly permits required traffic flows

### Why default-deny

Without a default-deny policy, Kubernetes allows all pod-to-pod traffic by default. This means a compromised Loki pod could freely connect to ArgoCD, Prometheus, or any other service. Default-deny forces you to explicitly declare every allowed communication path, which is the correct security posture.

In enterprise environments, default-deny is standard practice. PCI-DSS, SOC 2, and most security frameworks require network segmentation with explicit allow rules — not implicit open access.

### Why namespace boundary, not pod-level selectors

Pod-level NetworkPolicies use `podSelector` to target individual pods or deployments. Namespace boundary policies use `namespaceSelector` to allow all traffic from a given namespace.

We chose namespace boundary for these reasons:

**Operational simplicity.** Pod labels change when Helm charts are upgraded. A NetworkPolicy targeting `app.kubernetes.io/name=grafana` will break if the chart changes that label. Namespace selectors are stable — the namespace name doesn't change.

**Appropriate granularity for a homelab platform.** We are not running untrusted multi-tenant workloads. Each namespace contains a single, trusted application stack. The threat model is about preventing lateral movement from a compromised container, not isolating tenants from each other.

**Enterprise comparison.** In production, you would typically use namespace boundary policies at the platform level (monitoring, ingress, CI/CD) and add pod-level policies for applications that handle sensitive data (payment services, auth services). The pattern is the same — it's a question of where you draw the boundary based on your threat model.

### Traffic architecture and why each rule exists

The overall traffic flow is:

```
Internet → Cloudflare Edge → Cloudflare Tunnel (cloudflared pod)
         → nginx-ingress → application pods
         → Prometheus scrapes all namespaces
         → ArgoCD pulls from GitHub → deploys to all namespaces
```

This flow dictates the NetworkPolicy rules:

**cloudflare namespace**
- No ingress rules. cloudflared only makes outbound connections to Cloudflare's edge — nothing connects inbound to cloudflared.
- Egress to `ingress-nginx` on port 80 — cloudflared forwards decrypted traffic to nginx-ingress.
- Egress to internet on 443/TCP and 7844/UDP — QUIC tunnel to Cloudflare edge.

**ingress-nginx namespace**
- Ingress from `cloudflare` on 80/443 — receives traffic from cloudflared.
- Ingress from `monitoring` on 10254 — Prometheus scrapes nginx-ingress metrics.
- Egress to all application namespaces on their pod ports — nginx-ingress connects directly to pod IPs, bypassing service port mapping. This is a critical detail covered in Decision 3 below.

**monitoring namespace**
- Ingress from `ingress-nginx` — Grafana and Prometheus UIs are exposed via ingress.
- Intra-namespace open — Prometheus, Grafana, Loki, and Alertmanager communicate internally.
- Egress to scrape ports across all namespaces (9100/10254/3101/9402) — Prometheus must reach node-exporter, nginx metrics, Promtail metrics, and cert-manager metrics.
- Egress to Kubernetes API — Prometheus uses the Kubernetes API for service discovery (finding pods and services to scrape).
- Egress to external 443 — Alertmanager webhooks (PagerDuty, Slack, etc.).

**platform namespace (ArgoCD)**
- Ingress from `ingress-nginx` on 8080 — ArgoCD UI served via ingress.
- Intra-namespace open — ArgoCD has multiple components (server, repo-server, application-controller, dex, redis) that communicate internally.
- Egress to Kubernetes API — ArgoCD constantly queries and writes to the Kubernetes API to manage resources.
- Egress to external 443 — ArgoCD pulls manifests from GitHub and Helm chart repositories.

**cert-manager namespace**
- Egress to Kubernetes API — cert-manager creates and updates Certificate, Secret, and Ingress resources.
- Egress to external 443 — ACME DNS-01 challenge requires reaching Let's Encrypt and the Cloudflare API.

---

## Decision 2 — Kubernetes API Egress: Both ClusterIP and Node IP Required (Calico DNAT)

### What we decided

NetworkPolicy egress rules for namespaces that need to reach the Kubernetes API must allow **both** the Kubernetes service ClusterIP (`10.96.0.1/32`) and the control plane node IP (`192.168.178.34/32`), on both port 443 and 6443.

```yaml
- to:
    - ipBlock:
        cidr: 10.96.0.1/32       # kubernetes service ClusterIP
    - ipBlock:
        cidr: 192.168.178.34/32  # control plane node IP (post-DNAT)
  ports:
    - port: 443
      protocol: TCP
    - port: 6443
      protocol: TCP
```

### Why both IPs are needed

This is a non-obvious behaviour specific to how Calico interacts with kube-proxy.

When a pod makes a connection to `10.96.0.1:443` (the `kubernetes` service ClusterIP), the following happens:

```
Pod initiates connection to 10.96.0.1:443
  → kube-proxy intercepts via iptables DNAT rule
  → translates destination to 192.168.178.34:6443 (actual control plane)
  → packet leaves the pod network toward the node
```

The critical timing issue is that **Calico evaluates NetworkPolicy rules before kube-proxy applies the DNAT translation**. This means:

- The pod sees it is connecting to `10.96.0.1:443` — Calico allows this (if the ClusterIP rule exists)
- After DNAT, the packet is destined for `192.168.178.34:6443`
- Calico evaluates the egress again on the translated destination — this is blocked unless the node IP is also allowed

In practice, if you only allow `10.96.0.1/32`, the connection times out with no clear error. The symptoms look like a random connectivity issue or an ArgoCD bug — which is exactly what we experienced (misleading nil pointer dereference errors that masked the real root cause).

**Namespaces requiring this fix:** `platform` (ArgoCD) and `cert-manager`. Prometheus in the `monitoring` namespace also queries the Kubernetes API for service discovery and requires the same fix.

**How to verify connectivity:**

```bash
kubectl run test --image=curlimages/curl --rm -it --restart=Never -n platform \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"test","image":"curlimages/curl","args":["-I","https://10.96.0.1:443","--max-time","5","--insecure"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
```

Expected result: `HTTP/2 403` — connected successfully, rejected due to missing credentials. A timeout means the NetworkPolicy is still blocking.

---

## Decision 3 — nginx-ingress Connects to Pod IPs, Not Service Ports

### What we decided

Egress rules from `ingress-nginx` to application namespaces must use **pod ports**, not service ports.

| Application | Service Port | Pod Port |
|-------------|-------------|----------|
| Grafana | 80 | 3000 |
| Prometheus | 9090 | 9090 |
| Alertmanager | 9093 | 9093 |
| ArgoCD | 80 | 8080 |
| Loki | 3100 | 3100 |

### Why pod ports, not service ports

nginx-ingress (and most Kubernetes ingress controllers) uses the Kubernetes Endpoints API to discover the IP addresses and ports of the pods backing a service. It then connects **directly to the pod IPs**, bypassing the service ClusterIP and kube-proxy entirely.

This means kube-proxy's port mapping (service port → container port) is never involved. The connection goes straight to the container port.

If you write a NetworkPolicy egress rule allowing port 80 to reach Grafana, it will be blocked — because nginx-ingress is actually connecting to port 3000. The NetworkPolicy must allow the actual container port.

**How to find actual pod ports:**

```bash
kubectl get pods -n monitoring -o jsonpath='{.items[*].spec.containers[*].ports}' | python3 -m json.tool
```

Or check the service definition:

```bash
kubectl get service grafana -n monitoring -o yaml | grep -A5 "ports:"
# targetPort is the pod port
```

---

## Decision 4 — Pod Security Standards: Baseline for Monitoring, Restricted for Everything Else

### PSS levels explained

Kubernetes Pod Security Standards define three levels:

- **Privileged** — no restrictions, equivalent to no PSS
- **Baseline** — prevents known privilege escalations (no host namespaces, no privileged containers, no hostPath volumes with dangerous paths)
- **Restricted** — implements current pod hardening best practices (non-root user, no privilege escalation, drop all capabilities, seccomp profile required)

Each level can be applied in three modes:
- **enforce** — pods violating the policy are rejected
- **audit** — violations are logged but pods are allowed
- **warn** — violations surface as warnings in kubectl output but pods are allowed

### What we decided per namespace

| Namespace | Enforce | Audit | Warn | Reason |
|-----------|---------|-------|------|--------|
| platform | restricted | restricted | restricted | ArgoCD runs as non-root, no host access needed |
| cert-manager | restricted | restricted | restricted | cert-manager pods are well-hardened |
| ingress-nginx | restricted | restricted | restricted | nginx-ingress supports restricted PSS |
| cloudflare | restricted | restricted | restricted | cloudflared runs as non-root (UID 65532) |
| monitoring | baseline | restricted | restricted | node-exporter requires host access by design |

### Why monitoring cannot enforce restricted

Prometheus node-exporter must access host-level metrics. It requires:
- `hostPID: true` — reads process information from the host
- `hostNetwork: true` — reads network interface statistics
- `hostIPC: true` — accesses host IPC namespace
- `hostPort` — binds directly to a port on the node

These are all blocked by the `restricted` PSS level. node-exporter cannot function without them — this is by design, not a misconfiguration. The equivalent in a managed cloud environment is a DaemonSet with elevated privileges deployed by the cloud provider's monitoring agent.

`baseline` prevents the most dangerous privilege escalations while still allowing node-exporter's legitimate host access requirements.

**Loki and Promtail** also have restricted PSS violations (missing seccomp profiles, running as root) but these are fixable. The audit/warn labels on monitoring will surface these as warnings, providing a path to tighten the policy once those issues are resolved.

### Why security hardening before stateful workloads

PSS and NetworkPolicies were implemented before deploying Nextcloud, PostgreSQL, and other stateful workloads. This sequencing matters because:

- Retrofitting security controls onto existing workloads is significantly harder than designing them in from the start
- A compromised Nextcloud instance in an unsegmented cluster has lateral movement access to ArgoCD, Prometheus, and cert-manager private keys
- In production environments, security requirements are defined before application deployment — this homelab follows the same pattern

---

## Consequences

**Positive:**
- All inter-namespace traffic is explicitly declared and auditable
- Compromised pod blast radius is limited to its own namespace
- PSS enforcement prevents common container escape techniques
- Audit/warn labels provide ongoing visibility into policy violations without breaking workloads
- The NetworkPolicy and PSS configuration is fully GitOps managed via ArgoCD

**Negative / Trade-offs:**
- NetworkPolicy debugging is more complex — connectivity issues require checking both the allow rules and the default-deny rules
- The Calico DNAT behaviour (Decision 2) is a non-obvious footgun that caused significant debugging time
- Adding new applications requires explicitly updating NetworkPolicies before the app can communicate with the rest of the platform
- monitoring namespace is pinned to `baseline` until Loki and Promtail security contexts are fixed

**Known gaps (future work):**
- Loki and Promtail security context fixes to enable `restricted` enforcement on monitoring namespace
- RBAC hardening — least-privilege service accounts for all platform components
- External Secrets Operator — remove manual secret creation from bootstrap procedure
- Falco — runtime anomaly detection to complement NetworkPolicy and PSS

---

## References

- [Kubernetes NetworkPolicy documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Calico NetworkPolicy](https://docs.tigera.io/calico/latest/network-policy/get-started/kubernetes-policy/kubernetes-network-policy)
- `docs/runbooks/cluster-rebuild.md` — operational procedures including NetworkPolicy deadlock workaround
