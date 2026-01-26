# ArgoCD

## Overview

ArgoCD provides GitOps-based continuous delivery for the homelab Kubernetes cluster. It implements the App-of-Apps pattern for scalable, declarative management of all platform services.

## Access

| | |
|---|---|
| **URL** | `http://argocd.homelab.local:30080` |
| **Username** | `admin` |
| **Password** | See command below |

```bash
# Get admin password
kubectl -n platform get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Add to /etc/hosts (or Windows: C:\Windows\System32\drivers\etc\hosts)
192.168.178.34  argocd.homelab.local
```

## Architecture

### App-of-Apps Pattern

```
root-app (bootstrap, manually applied once)
    │
    └── watches: platform/argocd/apps/
            │
            ├── argocd-app.yaml ──────▶ ArgoCD (self-managed)
            └── nginx-ingress-app.yaml ▶ nginx-ingress controller
```

**How it works:**
1. `root-app` monitors `platform/argocd/apps/` directory in Git
2. Any `*.yaml` file added to that directory becomes an ArgoCD Application
3. ArgoCD deploys and manages the corresponding service
4. Changes to Git automatically sync to cluster

## Directory Structure

```
platform/argocd/
├── README.md           # This file
├── apps/               # ArgoCD Application manifests
│   ├── argocd-app.yaml       # Self-management
│   └── nginx-ingress-app.yaml
├── install/
│   └── values.yaml     # Helm values for ArgoCD
├── ingress.yaml        # Ingress resource for UI access
└── root-app.yaml       # App-of-Apps bootstrap
```

## Configuration

### Helm Values (`install/values.yaml`)

Key configurations:

```yaml
server:
  ingress:
    enabled: false      # Using separate ingress.yaml
  service:
    type: ClusterIP

configs:
  params:
    server.insecure: true  # TLS terminated at ingress
```

### Self-Management Settings (`apps/argocd-app.yaml`)

```yaml
syncPolicy:
  automated:
    prune: false        # Prevent accidental deletion
    selfHeal: true      # Auto-correct drift
```

## Common Operations

### View Sync Status

```bash
# CLI
argocd app list
argocd app get argocd

# Or use Web UI
```

### Manual Sync

```bash
# Sync specific application
argocd app sync nginx-ingress

# Sync all applications
argocd app sync --all
```

### Refresh from Git

```bash
argocd app refresh argocd
```

### View Application Logs

```bash
kubectl logs -n platform deployment/argocd-server
kubectl logs -n platform statefulset/argocd-application-controller
```

## Adding New Applications

```bash
# 1. Create Application manifest
cat > platform/argocd/apps/my-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: platform
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/mmrajput/kubernetes-homelab.git
    targetRevision: main
    path: apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# 2. Commit and push
git add -A
git commit -m "feat(argocd): add my-app application"
git push

# 3. root-app discovers and deploys automatically
```

## Troubleshooting

### Application Stuck in "Progressing"

```bash
# Check application status
argocd app get <app-name>

# Check events
kubectl describe application <app-name> -n platform

# Check controller logs
kubectl logs -n platform statefulset/argocd-application-controller --tail=50
```

### Sync Failed

```bash
# View sync details
argocd app sync <app-name> --dry-run

# Check for resource conflicts
kubectl get events -n <app-namespace> --sort-by='.lastTimestamp'
```

### Cannot Access UI

```bash
# Verify pods running
kubectl get pods -n platform

# Check ingress
kubectl get ingress -n platform

# Verify service
kubectl get svc -n platform argocd-server

# Test from within cluster
kubectl run curl --image=curlimages/curl -it --rm -- \
  curl -s http://argocd-server.platform.svc.cluster.local
```

## Bootstrap Recovery

If ArgoCD needs to be reinstalled:

```bash
# 1. Delete existing installation
kubectl delete namespace platform

# 2. Reinstall via Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --namespace platform \
  --create-namespace \
  --values platform/argocd/install/values.yaml

# 3. Wait for pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server \
  -n platform --timeout=120s

# 4. Apply ingress and root-app
kubectl apply -f platform/argocd/ingress.yaml
kubectl apply -f platform/argocd/root-app.yaml

# 5. ArgoCD rebuilds all applications from Git
```

## Related Documentation

- [Platform Services Overview](../README.md)
- [ADR-006: GitOps Tool Selection](../../docs/adr/ADR-006-gitops-tool.md)
- [ADR-008: App-of-Apps Pattern](../../docs/adr/ADR-008-app-of-apps-pattern.md)
- [ArgoCD Official Docs](https://argo-cd.readthedocs.io/)

---

**Last Updated:** January 2026
