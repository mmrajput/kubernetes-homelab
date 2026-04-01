# Claude Code — Kubernetes Homelab

## Project overview

Production-grade Kubernetes homelab targeting Platform Engineering, DevOps, and SRE roles
in the DACH region. Every phase produces working infrastructure with documented architectural
decisions. The repo is a portfolio artifact — code quality, commit hygiene, and documentation
standards matter as much as functionality.

---

## Cluster topology

- **Hardware:** Beelink SER5 Pro, Proxmox VE hypervisor, single physical host
- **Cluster:** 3-node kubeadm v1.31, Calico CNI
  - Control plane: `192.168.178.34` (6GB RAM, 3 vCPU)
  - Worker 1: `192.168.178.35` (7GB RAM, 3 vCPU)
  - Worker 2: `192.168.178.36` (7GB RAM, 3 vCPU)
- **Domain:** `mmrajputhomelab.org`
- **External access:** Cloudflare Tunnel — no open inbound ports

## Environment model

Single-cluster, namespace-based staging/production simulation. Vault, Keycloak, and CNPG
are shared infrastructure — not replicated per environment. Credential isolation is logical:
separate Vault paths, separate DB users, separate Keycloak clients per environment.

Physical infrastructure isolation would require a second cluster with dedicated instances.
This is a known homelab constraint, not an architectural oversight.

```
nextcloud-staging     ← staging namespace
nextcloud-production  ← production namespace (same cluster, logical isolation)
```

---

## Platform stack

| Layer | Technology |
|---|---|
| GitOps | ArgoCD (app-of-apps, `argocd` namespace) |
| Ingress | nginx-ingress + Cloudflare Tunnel |
| TLS | cert-manager, Cloudflare DNS-01 |
| Secrets | HashiCorp Vault + External Secrets Operator v2.1.0 |
| Identity | Keycloak 26.x (codecentric/keycloakx chart) |
| Database | CloudNativePG operator |
| Storage | Longhorn (RF=2, default SC), MinIO (S3), local-path |
| Observability | kube-prometheus-stack, Grafana, Loki, Promtail |
| CI/CD | GitHub Actions + ARC v0.14.0 |

---

## Repository structure

```
kubernetes-homelab/
├── bootstrap/namespaces/       # Applied manually once — never via ArgoCD
│   ├── networking/             # cert-manager, cloudflare, ingress-nginx
│   ├── security/               # external-secrets, keycloak, vault
│   ├── data/                   # cnpg-system, databases, longhorn, minio
│   ├── observability/          # monitoring
│   ├── ci-cd/                  # argocd, arc-runners, arc-systems
│   └── workloads/              # <app>/staging-namespace.yaml, production-namespace.yaml
├── platform/
│   ├── argocd/                 # ArgoCD self-management + app-of-apps
│   │   ├── root-app.yaml       # Bootstrap entry point
│   │   ├── values.yaml         # ArgoCD Helm values
│   │   └── apps/               # ArgoCD Application manifests
│   │       ├── argocd-app.yaml # Self-manage — sits above concern groups
│   │       ├── networking/
│   │       ├── security/
│   │       ├── data/
│   │       ├── observability/
│   │       ├── ci-cd/
│   │       └── workloads/      # <app>/staging-app.yaml, production-app.yaml
│   ├── networking/             # cert-manager, cloudflare, nginx-ingress, network-policies
│   │   └── network-policies/   # <group>/<app>/staging-netpol.yaml
│   ├── security/               # vault, external-secrets, keycloak
│   │   └── external-secrets/
│   │       └── stores/
│   │           ├── operators/  # ArgoCD, Grafana, Keycloak OIDC secrets
│   │           ├── databases/  # CNPG initdb secrets
│   │           └── workloads/  # App-level secrets
│   ├── data/                   # cnpg, longhorn, minio
│   │   └── cnpg/clusters/      # CNPG cluster definitions
│   ├── observability/          # prometheus, grafana, loki
│   └── ci-cd/                  # github-runner (ARC)
└── workloads/                  # Helm values — Pattern B (workload-first)
    ├── homepage/values.yaml
    └── nextcloud/              # staging-values.yaml, production-values.yaml
```

---

## Workload onboarding convention (Pattern B)

A workload exists in the repo when it is ready to deploy. All files are created in a single
atomic commit. Nothing is created partially or with placeholder content.

Files required per workload (example: nextcloud):

```
bootstrap/namespaces/workloads/nextcloud/staging-namespace.yaml
bootstrap/namespaces/workloads/nextcloud/production-namespace.yaml
platform/data/cnpg/clusters/nextcloud-cluster.yaml
platform/security/external-secrets/stores/databases/nextcloud-db-secret.yaml
platform/security/external-secrets/stores/workloads/nextcloud-staging-secret.yaml
platform/security/external-secrets/stores/workloads/nextcloud-production-secret.yaml
platform/networking/network-policies/workloads/nextcloud/staging-netpol.yaml
platform/networking/network-policies/workloads/nextcloud/production-netpol.yaml
workloads/nextcloud/staging-values.yaml
workloads/nextcloud/production-values.yaml
platform/argocd/apps/workloads/nextcloud/staging-app.yaml
platform/argocd/apps/workloads/nextcloud/production-app.yaml
```

### Shared namespace NetworkPolicy updates (mandatory)

Two shared NetworkPolicies must be updated for every new workload — omitting either causes
silent connectivity failures that only surface after deployment:

**1. `platform/networking/network-policies/networking/ingress-nginx-netpol.yaml`**
Add an egress rule so nginx-ingress can forward traffic to the workload namespace:
```yaml
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: <app>-staging
  ports:
    - port: <app-pod-port>   # pod port, not service port
      protocol: TCP
```

**2. `platform/networking/network-policies/data/databases-netpol.yaml`**
Add an ingress rule so the workload namespace can reach PostgreSQL:
```yaml
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: <app>-staging
  ports:
    - port: 5432
      protocol: TCP
```

Namespaces are applied manually before ArgoCD manages the workload:
```bash
kubectl apply -f bootstrap/namespaces/workloads/nextcloud/staging-namespace.yaml
kubectl apply -f bootstrap/namespaces/workloads/nextcloud/production-namespace.yaml
```

---

## Secret management workflow

1. Write secrets to Vault imperatively (CLI inside vault pod — never committed to Git)
2. Create ExternalSecret manifest in the appropriate `stores/` subdirectory
3. Commit ExternalSecret to Git — ESO syncs it to the cluster
4. Application consumes the resulting Kubernetes Secret

Vault path conventions:
```
secret/databases/<app>       # CNPG initdb credentials (username, password)
secret/<app>/admin           # Application admin credentials
secret/<app>/config          # Application-specific config secrets
secret/minio/<app>           # MinIO access credentials
secret/operators/<tool>      # Platform operator secrets (ArgoCD, Grafana, Keycloak)
```

ESO ExternalSecret `remoteRef.key` uses API path format: `secret/data/<path>`
Vault CLI uses logical path format: `secret/<path>`

---

## ArgoCD conventions

- All Application manifests use `namespace: argocd`
- Multi-source pattern: Helm chart source + Git `$values` reference
- `CreateNamespace=false` on all Applications — namespaces bootstrapped manually
- `ServerSideApply=true` for CRD-heavy operators (CNPG, ESO, ARC)
- Hard refresh: `kubectl annotate application <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite`
- Self-heal is enabled — never manually `kubectl apply` platform resources without disabling selfHeal first

ArgoCD Application template (multi-source):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app>-staging
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: workloads
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: <helm-chart-repo>
      chart: <chart-name>
      targetRevision: <version>
      helm:
        valueFiles:
          - $values/workloads/<app>/staging-values.yaml
    - repoURL: https://github.com/mmrajput/kubernetes-homelab
      targetRevision: HEAD
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: <app>-staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
```

---

## NetworkPolicy conventions

- Default-deny applied to every namespace
- Calico evaluates NetworkPolicy before DNAT — egress to Kubernetes API requires both:
  - `10.96.0.1/32` (ClusterIP) on port 443
  - `192.168.178.34/32` (control plane node IP) on port 6443
- nginx-ingress connects to pod IPs directly — use pod ports, not service ports
- `namespaceSelector` preferred over `podSelector` for cross-namespace egress
- PSS `monitoring` namespace stays at `privileged` permanently — Promtail requires host access

NetworkPolicy file template:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: <app>-staging-default-deny
  namespace: <app>-staging
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: <app>-staging-allow
  namespace: <app>-staging
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - port: <app-port>
          protocol: TCP
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

---

## Git conventions

- Conventional commits with one-line messages
- Feature branches for all work: `feat/<workload>-staging`, `feat/<workload>-production`
- Never push directly to `main` — always use feature branches and PRs
- Commit all related files together atomically
- `helm template` dry-run before every commit
- `git diff --staged` review before every commit

Commit message format:
```
feat(nextcloud): add staging deployment

Brief description of what changed and why.
```

---

## Claude Code safety boundaries

### Allowed
- Read and write files within `/workspaces/kubernetes-homelab-01/`
- Run `kubectl` against the homelab cluster (staging namespace work only)
- Run `helm`, `git`, `vault` CLI commands
- Run bash scripts for infrastructure automation
- Create feature branches and commits
- Run `helm template` dry-runs

### Hard boundaries — never do these
- Never push directly to `main` branch
- Never run `kubectl delete` on platform-critical namespaces without explicit confirmation
- Never store, log, or transmit secrets or credentials
- Never write secrets or credentials into any file that gets committed to Git
- Never modify `.kube/config` or `.ssh/` files
- Never apply changes to `production` namespaces — production PRs are human-only
- Never run `kubectl apply` on platform resources directly — use GitOps
- Always show `git diff --staged` and ask for confirmation before committing
- Always run `helm template` before committing Helm value changes

### Production boundary
Claude Code operates on staging only. Production namespace work is done by the human
engineer via a separate PR after staging validation is complete. Production Vault paths,
production database credentials, and production Keycloak clients are out of scope.

---

## Known issues and gotchas

### Calico NetworkPolicy
- Calico evaluates NetworkPolicy before kube-proxy DNAT — always allow both ClusterIP
  and node IP for Kubernetes API egress
- nginx-ingress egress rules need pod ports, not service ports

### ArgoCD
- selfHeal deadlock: disable selfHeal before applying manual fixes, re-enable after
- ESO secrets need label `app.kubernetes.io/part-of: argocd` for ArgoCD to consume them
- Cannot mix Helm and raw manifests in a single Application source

### CNPG
- `initdb` secret keys must be named exactly `username` and `password` — not configurable
- Annotate CNPG PVCs to exclude from Velero: `backup.velero.io/backup-volumes-excludes: pgdata`

### ESO
- `remoteRef.key` uses API path (`secret/data/`), not logical path (`secret/`)
- `apiVersion: external-secrets.io/v1` (not v1beta1) for ESO 2.x

### ARC
- GitHub App secret must exist in `arc-runners` namespace, not just `arc-systems`
- Use `local-path` storage class for runner work volumes — Longhorn causes chown failures
- `ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=false` required for steps without job container

### Line endings
- All YAML files must use LF line endings (`.gitattributes` enforces this)
- sed patterns will fail on CRLF files — strip with `sed -i 's/\r//'` if needed

---

## Storage conventions

### Longhorn (default StorageClass)
- Used for all persistent workload data — databases, user files, stateful app data
- RF=2 — every PVC consumes 2× its declared size in physical storage
- Total available: ~160GB raw, ~80GB effective (RF=2)
- Schedulable nodes: k8s-worker-01, k8s-worker-02 only (control plane excluded)

### Recommended PVC sizes — Nextcloud
| Volume | Staging | Production |
|---|---|---|
| User files (nextcloud-data) | 5Gi | 15Gi |
| CNPG database (nextcloud-db) | 3Gi | 8Gi |
| Redis cache | 1Gi | 1Gi |

PVCs can be expanded online via Longhorn — start conservative, expand when needed.

### MinIO (S3-compatible object storage)
- Used for: CNPG WAL archiving, Velero backups, Loki log storage
- Nextcloud CNPG backups: `s3://cnpg-backups/nextcloud/`
- MinIO endpoint (internal): `http://minio.minio.svc.cluster.local:9000`
- Credentials managed via ESO at `secret/minio/<app>`

### StorageClass selection
| Use case | StorageClass |
|---|---|
| Production databases | longhorn |
| Staging databases | longhorn |
| Nextcloud user files | longhorn |
| Redis cache | longhorn |
| ARC runner work volumes | local-path (Longhorn causes chown failures) |
| Development/test scratch | local-path |

### Velero backup annotations
Exclude CNPG PVCs from Velero (CNPG handles its own backup via WAL archiving):
```yaml
annotations:
  backup.velero.io/backup-volumes-excludes: pgdata
```
Include Nextcloud user file PVCs in Velero:
```yaml
annotations:
  backup.velero.io/backup-volumes: nextcloud-data
```
