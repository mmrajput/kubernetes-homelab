# ArgoCD

## Overview

ArgoCD provides GitOps-based continuous delivery for the homelab Kubernetes cluster. It implements the App-of-Apps pattern for scalable, declarative management of all platform services.

## App-of-Apps Architecture

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

---

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
