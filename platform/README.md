# Platform Services

## Overview

Platform services provide the foundational capabilities that applications depend on. These are deployed via GitOps (ArgoCD) and managed declaratively through this repository.

## Current Services

| Service | Purpose | Namespace | Access |
|---------|---------|-----------|--------|
| ArgoCD | GitOps continuous delivery | `platform` | `http://argocd.homelab.local:30080` |
| nginx-ingress | HTTP routing and load balancing | `ingress-nginx` | NodePort 30080/30443 |
| local-path-provisioner | Dynamic PV provisioning | `local-path-storage` | N/A |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      GitOps Flow                            │
│                                                             │
│   Git Repository                                            │
│        │                                                    │
│        ▼                                                    │
│   ┌─────────┐     ┌─────────────────┐     ┌──────────────┐  │
│   │ root-app│───▶│ platform/argocd │────▶│ ArgoCD       │  │
│   │         │     │ /apps/*.yaml    │     │ (self-manage)│  │
│   └─────────┘     └─────────────────┘     └──────────────┘  │
│        │                                                    │
│        ▼                                                    │
│   ┌─────────────────┐      ┌──────────────┐                 │
│   │ nginx-ingress-  │───▶ │nginx-ingress │                 │
│   │ app.yaml        │      │ controller   │                 │
│   └─────────────────┘      └──────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
platform/
├── README.md                 # This file
├── argocd/
│   ├── apps/                 # ArgoCD Application manifests
│   │   ├── argocd-app.yaml   # ArgoCD self-management
│   │   └── nginx-ingress-app.yaml
│   ├── install/
│   │   └── values.yaml       # ArgoCD Helm values
│   ├── ingress.yaml          # ArgoCD Ingress resource
│   └── root-app.yaml         # App-of-Apps root (bootstrap)
└── nginx-ingress/
    └── values.yaml           # nginx-ingress Helm values
```

## Bootstrap Process

Initial cluster setup requires manual bootstrap of ArgoCD:

```bash
# 1. Install ArgoCD via Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace platform \
  --create-namespace \
  --values platform/argocd/install/values.yaml

# 2. Apply root-app (enables GitOps for everything else)
kubectl apply -f platform/argocd/root-app.yaml

# 3. ArgoCD now manages itself and all platform services
```

After bootstrap, all changes flow through Git.

## GitOps Workflow

**Adding a new platform service:**

```bash
# 1. Create values file
cat > platform/new-service/values.yaml << EOF
# Helm values for new-service
EOF

# 2. Create ArgoCD Application
cat > platform/argocd/apps/new-service-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: new-service
  namespace: platform
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
EOF

# 3. Commit and push
git add -A
git commit -m "feat(platform): add new-service"
git push

# 4. ArgoCD automatically discovers and deploys
```

**Updating an existing service:**

```bash
# 1. Edit values file
vim platform/nginx-ingress/values.yaml

# 2. Commit and push
git add -A
git commit -m "config(nginx-ingress): update configuration"
git push

# 3. ArgoCD syncs changes automatically
```

## Planned Services

| Service | Phase | Purpose |
|---------|-------|---------|
| Prometheus | Phase 6 | Metrics collection |
| Grafana | Phase 6 | Visualization |
| Loki | Phase 6 | Log aggregation |
| cert-manager | Phase 10 | TLS certificate automation |

## Related Documentation

- [ArgoCD Setup](argocd/README.md)
- [nginx-ingress Configuration](nginx-ingress/README.md)
- [ADR-006: GitOps Tool Selection](../docs/adr/ADR-006-gitops-tool.md)
- [ADR-007: Ingress Strategy](../docs/adr/ADR-007-ingress-strategy.md)
- [ADR-008: App-of-Apps Pattern](../docs/adr/ADR-008-app-of-apps-pattern.md)
- [GitOps with ArgoCD Guide](../../docs/guides/gitops-argocd.md)
---

**Last Updated:** January 2026
