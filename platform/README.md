# Platform Services

## Overview

Platform services provide the foundational capabilities that applications depend on. These are deployed via GitOps (ArgoCD) and managed declaratively through this repository.

## Current Services

| Service | Purpose | Namespace | Access |
|---------|---------|-----------|--------|
| ArgoCD | GitOps continuous delivery | `platform` | `http://argocd.homelab.local:30080` |
| nginx-ingress | HTTP routing and load balancing | `ingress-nginx` | NodePort 30080/30443 |
| local-path-provisioner | Dynamic PV provisioning | `local-path-storage` | N/A |
| prometheus | Monitoring stack | `monitoring` | `http://prometheus.homelab.local:30080` |

## Directory Structure

```
platform/
├── README.md                               # This file
├── argocd/
│   ├── README.md                           # ArgoCD-specific documentation
│   ├── values.yaml                         # ArgoCD Helm values (includes ingress config)
│   ├── apps/                               # ArgoCD Application manifests (GitOps managed)
│   │   ├── argocd-app.yaml                 # ArgoCD self-management
│   │   ├── nginx-ingress-app.yaml
│   │   └── kube-prometheus-stack-app.yaml
│   └── root-app.yaml                       # App-of-Apps root (bootstrap only)
├── nginx-ingress/
│   ├── README.md
│   └── values.yaml                         # nginx-ingress Helm values
└── prometheus/
    ├── README.md
    └── values.yaml                         # kube-prometheus-stack Helm values
```
---

## Bootstrap Workflow (Step-by-Step)

The App-of-Apps pattern requires a one-time manual bootstrap, after which all changes flow through Git.

### Step 1: Install ArgoCD via Helm (Manual, Once)

```bash
# Add Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD with consolidated configuration
helm install argocd argo/argo-cd \
  --namespace platform \
  --create-namespace \
  --values platform/argocd/values.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=120s
```

**File used:** `platform/argocd/values.yaml` (includes server config, ingress, and resource limits)

**Access**

| | |
|---|---|
| **URL** | `http://argocd.homelab.local:30080` |
| **Username** | `admin` |
| **Password** | See command below |

```bash
# Get admin password
kubectl -n platform get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Step 3: Apply Root App (Manual, Once)

```bash
kubectl apply -f platform/argocd/root-app.yaml
```

**File used:** `platform/argocd/root-app.yaml`

This creates the root application that watches `platform/argocd/apps/` directory.

### Step 4: GitOps Takes Over (All Future Changes)

From this point, **no more kubectl for platform services**. Just commit to Git:

```bash
# Adding a new service
vim platform/argocd/apps/kube-prometheus-stack-app.yaml
git add -A
git commit -m "feat(platform): add kube-prometheus-stack-app"
git push

# ArgoCD automatically detects and deploys
```

---

## Visual Flow

```
MANUAL (one-time)                    GITOPS (ongoing)
─────────────────                    ────────────────

1. helm install argocd               
   (uses argocd/values.yaml)        
              │                      
              ▼                      
2. kubectl apply root-app.yaml ──────► root-app watches apps/
                                              │
                                              ▼
                                     4. git push apps/*.yaml
                                              │
                                              ▼
                                        ArgoCD auto-deploys
                                        ├── argocd-app
                                        └── nginx-ingress-app
```
---

## Adding a New Platform Service

```bash
# 1. Create values file (if using Helm)
mkdir -p platform/new-service
cat > platform/new-service/values.yaml << EOF
# Helm values for new-service
replicaCount: 1
EOF

# 2. Create ArgoCD Application manifest
cat > platform/argocd/apps/new-service-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: new-service
  namespace: platform
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/mmrajput/kubernetes-homelab.git
    targetRevision: main
    path: platform/new-service
  destination:
    server: https://kubernetes.default.svc
    namespace: new-service
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# 3. Commit and push
git add -A
git commit -m "feat(platform): add new-service"
git push

# 4. ArgoCD automatically discovers and deploys
```
---

## Updating an Existing Service

```bash
# 1. Edit values file
vim platform/nginx-ingress/values.yaml

# 2. Commit and push
git add -A
git commit -m "config(nginx-ingress): update configuration"
git push

# 3. ArgoCD syncs changes automatically
```
---

## File Purpose Reference

| File | Purpose | How Applied |
|------|---------|-------------|
| `argocd/values.yaml` | ArgoCD Helm configuration | `helm install` (manual, once) |
| `argocd/root-app.yaml` | Watches `apps/` directory | `kubectl apply` (manual, once) |
| `argocd/apps/argocd-app.yaml` | ArgoCD self-management | Git push → auto-discovered |
| `argocd/apps/nginx-ingress-app.yaml` | nginx-ingress deployment | Git push → auto-discovered |
| `nginx-ingress/values.yaml` | nginx-ingress Helm values | Referenced by nginx-ingress-app |

---

## Planned Services

| Service | Phase | Purpose |
|---------|-------|---------|
| Prometheus | Phase 6 | Metrics collection |
| Grafana | Phase 6 | Visualization |
| Loki | Phase 6 | Log aggregation |
| cert-manager | Phase 10 | TLS certificate automation |

---

## Related Documentation

- [ArgoCD Setup](argocd/README.md)
- [nginx-ingress Configuration](nginx-ingress/README.md)
- [GitOps with ArgoCD Guide](../docs/guides/gitops-using-argocd-guide.md)
- [ADR-006: GitOps Tool Selection](../docs/adr/ADR-006-gitops-tool.md)
- [ADR-007: Ingress Strategy](../docs/adr/ADR-007-ingress-strategy.md)
- [ADR-008: App-of-Apps Pattern](../docs/adr/ADR-008-app-of-apps-pattern.md)

---

**Last Updated:** Feb 2026
