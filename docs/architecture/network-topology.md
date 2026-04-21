# Network Topology

**Cluster:** mmrajputhomelab.org
**Last Updated:** April 2026

---

## Physical Network

```
Internet
    │
    └── Home Router (192.168.178.1 / 24)
            │
            ├── Proxmox Host (192.168.178.33)
            │       │
            │       └── vmbr0 (Linux bridge)
            │               │
            │               ├── k8s-cp-01     (192.168.178.34) — control plane
            │               ├── k8s-worker-01 (192.168.178.35) — worker
            │               └── k8s-worker-02 (192.168.178.36) — worker
            │
            └── Other home devices (DHCP 192.168.178.100–254)
```

### IP Address Allocation

| Device | IP | Role |
|--------|----|------|
| Router | 192.168.178.1 | Gateway + DNS |
| Proxmox host | 192.168.178.33 | Hypervisor |
| k8s-cp-01 | 192.168.178.34 | Kubernetes control plane, etcd |
| k8s-worker-01 | 192.168.178.35 | Worker node |
| k8s-worker-02 | 192.168.178.36 | Worker node |

- **Subnet:** 192.168.178.0/24
- **Static range:** 192.168.178.30–50 (infrastructure)
- **DHCP range:** 192.168.178.100–254 (home devices)

---

## Kubernetes Network

### Address Ranges

| Range | Purpose |
|-------|---------|
| `10.244.0.0/16` | Pod CIDR (Calico, configured at kubeadm init) |
| `10.96.0.0/12` | Service CIDR (ClusterIP range) |
| `10.96.0.1` | `kubernetes` service ClusterIP (API server) |

### CNI — Calico

Calico provides:
- Pod-to-pod routing across nodes (VXLAN or BGP)
- Full NetworkPolicy enforcement
- IP address management (IPAM) for pods

**Important:** Calico evaluates NetworkPolicy **before** kube-proxy DNAT. Traffic destined for the `kubernetes` service (`10.96.0.1`) is NATted to `192.168.178.34:6443` by kube-proxy after Calico has already evaluated the policy. This means any namespace needing Kubernetes API egress must explicitly allow **both** IPs:

```yaml
egress:
  - to:
      - ipBlock:
          cidr: 10.96.0.1/32        # ClusterIP (pre-DNAT)
      - ipBlock:
          cidr: 192.168.178.34/32   # Control plane node IP (post-DNAT)
    ports:
      - port: 443
        protocol: TCP
      - port: 6443
        protocol: TCP
```

---

## External Access — Cloudflare Tunnel

There are **no open inbound ports** on the home network. External access uses Cloudflare Tunnel:

```
Browser (HTTPS, port 443)
    │
    ▼
Cloudflare Edge (*.mmrajputhomelab.org)
    │  Outbound-only tunnel (initiated by cloudflared pod)
    ▼
cloudflared Deployment (cloudflare namespace, 2 replicas)
    │
    ▼
ingress-nginx-controller ClusterIP Service (:80)
    │
    ▼
nginx-ingress Controller pod
    │  Host-based routing
    ▼
ClusterIP Service → Application pod
```

`cloudflared` maintains a persistent outbound connection to Cloudflare's edge and routes traffic directly to `ingress-nginx-controller.ingress-nginx.svc.cluster.local:80`. No firewall rules or port forwarding are needed on the router. The ingress-nginx service is type `ClusterIP` — there are no NodePorts exposed on cluster nodes.

### TLS

TLS is terminated at the Cloudflare edge. The `cloudflared` pod connects to `ingress-nginx` over plain HTTP inside the cluster — no TLS certificate is required on the nginx side.

```
Browser → Cloudflare Edge (TLS terminated, Cloudflare-managed cert)
               │  outbound tunnel
               ▼
          cloudflared pod → ingress-nginx (HTTP)
```

cert-manager remains in the stack solely to provision webhook TLS certificates for cluster operators (CNPG, ESO, etc.).

---

## NetworkPolicy Architecture

Every namespace has a default-deny NetworkPolicy. Explicit allow rules are added per-namespace using `namespaceSelector` (namespace-boundary rules) rather than `podSelector`.

### Why namespace-boundary rules

Pod labels change during Helm upgrades and can break pod-level policies. Namespace names are stable. For a single-tenant platform, namespace-boundary isolation is the appropriate granularity.

### Standard NetworkPolicy Patterns

**Workload namespace (e.g., nextcloud-production):**

```
Allowed Ingress:
  - ingress-nginx namespace → pod port (e.g., 8080)
  - monitoring namespace → metrics port (e.g., 9090)

Allowed Egress:
  - databases namespace → port 5432 (PostgreSQL)
  - keycloak namespace → port 8080 (OIDC)
  - minio namespace → port 9000 (S3)
  - 10.96.0.1/32:443 + 192.168.178.34:6443 (Kubernetes API)
  - DNS: kube-dns port 53
```

**nginx-ingress connects to pod IPs** (not service IPs). NetworkPolicies must allow ingress on the **pod port** (e.g., 8080), not the service port (e.g., 80).

### Namespace Labels

Namespaces used in NetworkPolicy selectors carry these labels:

| Label | Value | Purpose |
|-------|-------|---------|
| `kubernetes.io/metadata.name` | namespace name | Standard label for namespaceSelector |
| `homelab.io/role` | `workload` | Applied to all workload namespaces; used by ingress-nginx and databases netpols |

Workload namespaces labeled `homelab.io/role: workload` are automatically matched by platform NetworkPolicies — no per-workload edits to platform netpols needed.

### Pod Security Standards (PSS)

| Namespace | PSS enforce | Rationale |
|-----------|------------|-----------|
| Most platform namespaces | `restricted` | Least privilege |
| `monitoring` | `privileged` | Promtail requires host path access |
| `longhorn-system` | `privileged` | Longhorn CSI driver |

---

## Internal DNS

CoreDNS is the cluster DNS resolver. All internal service discovery uses the pattern:

```
<service>.<namespace>.svc.cluster.local
```

Common internal service addresses:

| Service | DNS name |
|---------|---------|
| Vault | `vault.vault.svc.cluster.local:8200` |
| MinIO S3 API | `minio.minio.svc.cluster.local:9000` |
| Loki | `loki.monitoring.svc.cluster.local:3100` |
| Prometheus | `prometheus-operated.monitoring.svc.cluster.local:9090` |
| Keycloak | `keycloakx.keycloak.svc.cluster.local:8080` |
| CNPG primary (nextcloud) | `nextcloud-prod-db-rw.databases.svc.cluster.local:5432` |

---

## Service Topology Summary

```
External Access Layer:
  Cloudflare DNS → Cloudflare Tunnel → cloudflared pod

Ingress Layer:
  nginx-ingress (ClusterIP :80) → Ingress resources → Services

Platform Services:
  argocd, cert-manager, vault, external-secrets, keycloak
  (all in their own namespaces, default-deny NetworkPolicy)

Data Layer:
  databases ns: CNPG clusters (nextcloud-prod-db, keycloak-db)
  minio ns:     MinIO (S3 for Loki, Velero, CNPG WAL)
  longhorn-system: Longhorn CSI + volume replicas

Observability:
  monitoring ns: Prometheus, Grafana, Loki, Promtail, Alertmanager

Workloads:
  nextcloud-production, nextcloud-staging (label: homelab.io/role=workload)
```

---

## Related Documentation

- [ADR-004: CNI Selection (Calico)](../adr/ADR-004-cni-selection.md)
- [ADR-007: Ingress Strategy](../adr/ADR-007-ingress-strategy.md)
- [ADR-011: NetworkPolicy and PSS](../adr/ADR-011-networkpolicy-and-pss.md)
- [Security Hardening Guide](../guides/security-hardening-guide.md)
