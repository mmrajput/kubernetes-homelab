# nginx-ingress Controller

## Overview

nginx-ingress provides HTTP/HTTPS routing for cluster services using Kubernetes Ingress resources. Deployed via GitOps with NodePort backend for homelab access.

## Configuration

| Setting | Value |
|---------|-------|
| Namespace | `ingress-nginx` |
| Service Type | NodePort |
| HTTP Port | 30080 |
| HTTPS Port | 30443 |
| Default IngressClass | `nginx` (default=true) |

## Access Pattern

```
Browser Request
    ↓
http://argocd.homelab.local:30080
    ↓
NodePort Service (30080)
    ↓
nginx-ingress Controller
    ↓
Ingress Resource (host: argocd.homelab.local)
    ↓
ClusterIP Service (argocd-server)
    ↓
ArgoCD Pod
```

## Helm Values

`values.yaml`:

```yaml
controller:
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
  ingressClassResource:
    default: true
```

## Adding Ingress for New Services

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service
  namespace: my-namespace
spec:
  ingressClassName: nginx
  rules:
    - host: my-service.homelab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
```

Then add to `/etc/hosts`:
```
192.168.178.34  my-service.homelab.local
```

## Managed By

This service is managed via ArgoCD App-of-Apps pattern:

- **Application:** `platform/argocd/apps/nginx-ingress-app.yaml`
- **Values:** `platform/nginx-ingress/values.yaml`

Changes to `values.yaml` are automatically synced by ArgoCD.

## Troubleshooting

### Ingress Not Routing

```bash
# Check controller pod
kubectl get pods -n ingress-nginx

# Check ingress resources
kubectl get ingress -A

# View controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

### 404 Not Found

```bash
# Verify backend service exists
kubectl get svc -n <namespace>

# Verify endpoints
kubectl get endpoints -n <namespace>

# Check ingress configuration
kubectl describe ingress <name> -n <namespace>
```

## Related Documentation

- [Platform Overview](../README.md)
- [ADR-007: Ingress Strategy](../../docs/adr/ADR-007-ingress-strategy.md)
- [nginx-ingress Official Docs](https://kubernetes.github.io/ingress-nginx/)

---

**Last Updated:** January 2026
