# Certificate Management Runbook

**Cluster:** mmrajputhomelab.org
**Last Updated:** April 2026

---

## Overview

TLS certificates are managed by cert-manager using a wildcard certificate `*.mmrajputhomelab.org` issued by Let's Encrypt via Cloudflare DNS-01 challenge. All services share one certificate stored as `wildcard-homelab-tls` in the `ingress-nginx` namespace.

cert-manager renews the certificate automatically 30 days before expiry. No manual intervention is normally required.

---

## Certificate Inventory

| Certificate | Namespace | Secret | Domains | Renews |
|-------------|-----------|--------|---------|--------|
| `wildcard-homelab-tls` | `ingress-nginx` | `wildcard-homelab-tls` | `*.mmrajputhomelab.org` | Auto, 30d before expiry |

---

## Checking Certificate Status

```bash
kubectl get certificate -n ingress-nginx
# READY must be True
# AGE shows how long since issuance

kubectl describe certificate wildcard-homelab-tls -n ingress-nginx
# Check: "Status.Conditions" and "Events"
```

Check expiry date:

```bash
kubectl get secret wildcard-homelab-tls -n ingress-nginx \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -dates
# notAfter shows expiry — should be ~90 days from issuance
```

---

## How DNS-01 Challenge Works

```
cert-manager (CertificateRequest)
    ↓
ACME DNS-01 challenge
    ↓
cert-manager creates TXT record via Cloudflare API
(_acme-challenge.mmrajputhomelab.org)
    ↓
Let's Encrypt verifies TXT record
    ↓
Certificate issued → stored as wildcard-homelab-tls Secret
    ↓
cert-manager deletes the TXT record
```

The Cloudflare API token for this is stored as `cloudflare-api-token` in the `cert-manager` namespace. This secret is applied manually during bootstrap (not managed by ESO).

---

## Checking the Cloudflare API Token Secret

```bash
kubectl get secret cloudflare-api-token -n cert-manager
# Must exist. If missing, the certificate will never issue.

# Re-create if missing:
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=<YOUR_CLOUDFLARE_API_TOKEN> \
  -n cert-manager
```

---

## Manual Certificate Renewal

cert-manager renews automatically. If you need to force renewal:

```bash
# Delete the certificate — cert-manager will immediately re-request it
kubectl delete certificate wildcard-homelab-tls -n ingress-nginx

# ArgoCD will recreate the Certificate resource from Git on next sync
# Monitor renewal:
kubectl get certificate -n ingress-nginx -w
```

Or trigger renewal without deleting the certificate:

```bash
# Annotate the certificate to request renewal
kubectl annotate certificate wildcard-homelab-tls -n ingress-nginx \
  cert-manager.io/issueTemporary=true --overwrite
```

---

## Troubleshooting

### READY = False

```bash
kubectl describe certificate wildcard-homelab-tls -n ingress-nginx
# Check Status.Conditions and Events

# Look for a CertificateRequest
kubectl get certificaterequest -n ingress-nginx
kubectl describe certificaterequest <name> -n ingress-nginx

# Look for a Challenge
kubectl get challenge -n ingress-nginx
kubectl describe challenge <name> -n ingress-nginx
```

### DNS-01 challenge failing

```bash
kubectl logs -n cert-manager -l app=cert-manager --tail=100 | grep -i error

# Common causes:
# 1. Cloudflare API token missing or invalid
kubectl get secret cloudflare-api-token -n cert-manager

# 2. Token lacks "Edit zone DNS" permission on the domain
# Fix: recreate token in Cloudflare Dashboard with correct permissions

# 3. Let's Encrypt rate limit hit (5 certificates per domain per week)
# Fix: wait up to a week. Check: https://crt.sh/?q=mmrajputhomelab.org
```

### Certificate issued but ingress still shows TLS error

```bash
# Check the ingress references the correct secret name
kubectl get ingress -n <namespace> -o yaml | grep secretName
# Should be: wildcard-homelab-tls

# Check the secret exists in ingress-nginx namespace
kubectl get secret wildcard-homelab-tls -n ingress-nginx

# If Ingress is in a different namespace, the secret must be in that namespace too
# (or use cert-manager's ingress-shim to copy it)
```

### cert-manager pod not running

```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Check ArgoCD app status
kubectl get application cert-manager -n argocd
```

### 502 Bad Gateway after valid certificate

The certificate is valid but nginx buffers are too small for Keycloak JWT tokens.

```bash
# Verify proxy-buffer-size is set in nginx configmap
kubectl get configmap -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.data.proxy-buffer-size}'
# Expected: 16k
```

---

## ClusterIssuer Configuration

The Let's Encrypt production ClusterIssuer is managed via ArgoCD at `platform/networking/cert-manager/`. It uses Cloudflare DNS-01:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <your-email>
    privateKeySecretRef:
      name: letsencrypt-production-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

---

## Related Documentation

- [nginx-ingress README](../../platform/networking/nginx-ingress/README.md)
- [Network Topology](../architecture/network-topology.md)
- [ADR-007: Ingress Strategy](../adr/ADR-007-ingress-strategy.md)
