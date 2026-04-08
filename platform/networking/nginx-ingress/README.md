# nginx-ingress Controller

HTTP/HTTPS ingress for the homelab cluster. All external traffic enters via Cloudflare Tunnel and is routed through nginx-ingress to internal services.

## Overview

| Property | Value |
|----------|-------|
| Chart | ingress-nginx 4.11.3 |
| Namespace | `ingress-nginx` |
| Service type | NodePort |
| HTTP port | 30080 |
| HTTPS port | 30443 |
| IngressClass | `nginx` (default) |
| TLS | Wildcard cert from cert-manager (Cloudflare DNS-01) |

## Access Pattern

```
Browser (HTTPS)
    ↓
Cloudflare DNS (*.mmrajputhomelab.org)
    ↓
Cloudflare Tunnel (cloudflared pod in cluster, no open inbound ports)
    ↓
nginx-ingress NodePort 30443
    ↓
Ingress resource (host-based routing)
    ↓
ClusterIP Service → Pod
```

TLS is terminated at nginx-ingress using the wildcard certificate `wildcard-homelab-tls` issued by cert-manager via Cloudflare DNS-01 challenge. All services share one certificate.

## TLS Configuration

The wildcard certificate is stored as a Kubernetes Secret in the `ingress-nginx` namespace and referenced by all Ingress resources:

```yaml
spec:
  tls:
    - hosts:
        - "*.mmrajputhomelab.org"
      secretName: wildcard-homelab-tls
  rules:
    - host: myservice.mmrajputhomelab.org
      ...
```

cert-manager renews the certificate automatically before expiry.

## Key nginx Configuration

```yaml
controller:
  config:
    proxy-buffer-size: "16k"     # Required for JWT tokens (Keycloak OIDC)
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
  ingressClassResource:
    default: true
```

`proxy-buffer-size: 16k` is required globally because Keycloak OIDC tokens exceed the default 4k nginx buffer and cause `502 Bad Gateway` responses.

## Adding Ingress for a New Service

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service
  namespace: my-namespace
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - my-service.mmrajputhomelab.org
      secretName: wildcard-homelab-tls
  rules:
    - host: my-service.mmrajputhomelab.org
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

The service will be accessible at `https://my-service.mmrajputhomelab.org` once ArgoCD syncs and Cloudflare Tunnel routes the subdomain.

## NetworkPolicy Notes

nginx-ingress connects to **pod IPs** (not service IPs) when forwarding traffic. NetworkPolicies in workload namespaces must allow ingress from the `ingress-nginx` namespace on the **pod port** (not the service port):

```yaml
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
  ports:
    - port: <pod-port>   # e.g. 8080, not 80
      protocol: TCP
```

## GitOps Management

| Resource | Path |
|----------|------|
| ArgoCD app | `platform/argocd/apps/networking/ingress-nginx-app.yaml` |
| Helm values | `platform/networking/nginx-ingress/values.yaml` |

## Troubleshooting

### Service returns 502 Bad Gateway

Most common cause: `proxy-buffer-size` too small for large OIDC tokens.

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50
# Look for: "upstream sent too big header"
# Fix: ensure proxy-buffer-size: "16k" is in nginx configmap
```

### Certificate not issued / TLS errors

```bash
kubectl get certificate -n ingress-nginx
kubectl describe certificate wildcard-homelab-tls -n ingress-nginx
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

See [`docs/runbooks/certificate-management.md`](../../../docs/runbooks/certificate-management.md).

### Ingress not routing (404)

```bash
kubectl get ingress -A
kubectl describe ingress <name> -n <namespace>
kubectl get endpoints -n <namespace>
# Verify endpoint IPs match running pod IPs
kubectl get pods -n <namespace> -o wide
```

### Cloudflare Tunnel disconnected

```bash
kubectl get pods -n cloudflare
kubectl logs -n cloudflare -l app=cloudflared --tail=50
```

## Related Documentation

- [cert-manager README](../cert-manager/README.md)
- [ADR-007: Ingress Strategy](../../../docs/adr/ADR-007-ingress-strategy.md)
- [Certificate Management Runbook](../../../docs/runbooks/certificate-management.md)
- [Network Topology](../../../docs/architecture/network-topology.md)

---

**Last Updated:** April 2026
