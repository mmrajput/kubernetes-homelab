# ArgoCD

## Overview

ArgoCD provides GitOps-based continuous delivery for the homelab Kubernetes cluster. It implements the App-of-Apps pattern for scalable, declarative management of all platform services.

## App-of-Apps Architecture
```
root-app (bootstrap, manually applied once)
    │
    └── watches: platform/argocd/apps/
            │
            ├── argocd-app.yaml ──────────────▶ ArgoCD (self-managed)
            ├── nginx-ingress-app.yaml ───────▶ nginx-ingress controller
            └── kube-prometheus-stack-app.yaml ▶ Prometheus, Grafana, AlertManager
```

**How it works:**
1. `root-app` monitors `platform/argocd/apps/` directory in Git
2. Any `*.yaml` file added to that directory becomes an ArgoCD Application
3. ArgoCD deploys and manages the corresponding service
4. Changes to Git automatically sync to cluster

---

## Configuration

### Helm Values (`argocd/values.yaml`)

All ArgoCD configuration is consolidated in a single values file, including ingress settings.

Key configurations:
```yaml
server:
  ingress:
    enabled: true                    # Managed by Helm
    ingressClassName: nginx
    hostname: argocd.homelab.local
  extraArgs:
    - --insecure                     # TLS terminated at ingress

controller:
  extraArgs:
    - --app-resync=120               # Sync every 2 minutes
```

**Resource limits:**
- Server: 100m-500m CPU, 128Mi-512Mi memory
- Repo Server: 100m-500m CPU, 128Mi-512Mi memory  
- Controller: 250m-1000m CPU, 512Mi-1Gi memory

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

# Or use Web UI at http://argocd.homelab.local
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

### Access UI Without Ingress (Port-Forward)
```bash
# If ingress is down, use port-forward
kubectl port-forward svc/argocd-server -n platform 8080:80

# Access at http://localhost:8080
# Get admin password:
kubectl get secret argocd-initial-admin-secret -n platform -o jsonpath="{.data.password}" | base64 -d && echo
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

# Common issue: duplicate ingress resources
kubectl get ingress -A | grep <hostname>
```

### Cannot Access UI
```bash
# Verify pods running
kubectl get pods -n platform

# Check ingress (should be in argocd namespace)
kubectl get ingress -n platform

# Verify service
kubectl get svc -n platform argocd-server

# Test from within cluster
kubectl run curl --image=curlimages/curl -it --rm -- \
  curl -s http://argocd-server.argocd.svc.cluster.local

# If ingress exists but not working, check nginx-ingress controller
kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50
```

### Ingress Conflicts

If you see validation webhook errors about duplicate ingress:
```bash
# List all ingress resources
kubectl get ingress -A

# Delete old manual ingress if it exists
kubectl delete ingress <old-ingress-name> -n <namespace>

# Sync ArgoCD to recreate Helm-managed ingress
argocd app sync argocd
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
  --values platform/argocd/values.yaml

# 3. Wait for pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server \
  -n platform --timeout=120s

# 4. Apply root-app to bootstrap App-of-Apps
kubectl apply -f platform/argocd/root-app.yaml

# 5. ArgoCD rebuilds all applications from Git
# Monitor progress:
argocd app list
```

## Related Documentation

- [Platform Services Overview](../README.md)
- [ADR-006: GitOps Tool Selection](../../docs/adr/ADR-006-gitops-tool.md)
- [ADR-008: App-of-Apps Pattern](../../docs/adr/ADR-008-app-of-apps-pattern.md)
- [ArgoCD Official Docs](https://argo-cd.readthedocs.io/)

---

**Last Updated:** February 2026