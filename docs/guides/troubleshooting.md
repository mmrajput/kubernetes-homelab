# Platform Troubleshooting Guide

**Cluster:** mmrajputhomelab.org — kubeadm v1.31, Calico, ArgoCD GitOps
**Last Updated:** April 2026

This guide covers operational troubleshooting for the full platform stack. For cluster rebuild from scratch see [`docs/runbooks/cluster-rebuild.md`](../runbooks/cluster-rebuild.md). For backup and restore see [`docs/runbooks/disaster-recovery.md`](../runbooks/disaster-recovery.md).

---

## Quick Diagnostics

```bash
# Cluster health
kubectl get nodes
kubectl get pods -A | grep -v "Running\|Completed"

# ArgoCD app health
kubectl get applications -n argocd

# Platform-wide events (last 10 minutes)
kubectl get events -A --sort-by='.lastTimestamp' | tail -30
```

---

## ArgoCD

### App stuck in Progressing

```bash
argocd app get <app-name>
kubectl describe application <app-name> -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### Sync fails with "API timeout" or nil pointer dereference

Most common cause: the ArgoCD namespace NetworkPolicy is blocking egress to the Kubernetes API.

```bash
# Verify both API server IPs are reachable from argocd namespace
kubectl run test --image=curlimages/curl --rm -it --restart=Never -n argocd \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"test","image":"curlimages/curl","args":["-I","https://10.96.0.1:443","--max-time","5","--insecure"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
# Expected: HTTP/2 403 (connected, rejected by API — correct)

# If timeout: fix the NetworkPolicy (both 10.96.0.1/32:443 and 192.168.178.34:6443 must be allowed)
```

### selfHeal reverts manual changes immediately

```bash
# 1. Disable selfHeal
kubectl patch application <app-name> -n argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":false}}}}'

# 2. Apply your fix
kubectl apply -f <manifest>

# 3. Re-enable selfHeal
kubectl patch application <app-name> -n argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

### Application finalizer blocking deletion

```bash
kubectl patch application <app-name> -n argocd \
  --type json \
  -p '[{"op":"remove","path":"/metadata/finalizers"}]'
kubectl delete application <app-name> -n argocd
```

---

## Vault

### Vault is sealed after pod restart

Vault does not auto-unseal. After any pod restart it starts sealed.

```bash
# Check seal status
kubectl exec -n vault vault-0 -- vault status
# Sealed: true → needs unsealing

# Unseal (run twice with different keys)
kubectl exec -it -n vault vault-0 -- vault operator unseal
```

### ClusterSecretStore not ready

```bash
kubectl get clustersecretstore vault-backend
kubectl describe clustersecretstore vault-backend
# Most common cause: Vault is sealed
# Fix: unseal Vault first (see above)
```

---

## External Secrets Operator (ESO)

### ExternalSecret not syncing (STATUS ≠ SecretSynced)

```bash
kubectl describe externalsecret <name> -n <namespace>
# Check "Status.Conditions" for error message

# Common causes and fixes:
# 1. Vault is sealed → unseal Vault
# 2. Vault path does not exist → create the secret in Vault
# 3. Wrong remoteRef.key (missing data/ segment for KV v2)
# 4. Policy does not cover the path → check vault external-secrets policy
```

### Force re-sync of an ExternalSecret

```bash
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync=$(date +%s) --overwrite
```

---

## cert-manager / TLS

### Certificate not issuing (READY = False)

```bash
kubectl get certificate -n ingress-nginx
kubectl describe certificate wildcard-homelab-tls -n ingress-nginx

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Check the ChallengeRequest
kubectl get challenges -A
kubectl describe challenge <name> -n cert-manager
```

Most common causes:
- Cloudflare API token secret missing or wrong: `kubectl get secret cloudflare-api-token -n cert-manager`
- DNS-01 challenge taking time (normal: up to 5 minutes)
- Rate limit hit (Let's Encrypt): wait and retry

### Ingress returning 502 (JWT token too large)

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=30
# Look for: "upstream sent too big header"
# Fix: ensure proxy-buffer-size: "16k" in nginx configmap
```

---

## CloudNativePG (CNPG)

### Cluster not reaching healthy state

```bash
kubectl get cluster -n databases -w
kubectl describe cluster <cluster-name> -n databases

# Check pods
kubectl get pods -n databases -l cnpg.io/cluster=<cluster-name>
kubectl logs -n databases -l cnpg.io/cluster=<cluster-name> --all-containers --tail=50
```

### Standby pod fails to join (times out silently)

Most common cause: the `databases` namespace NetworkPolicy does not allow bidirectional port 5432 within the namespace.

```bash
# Check pod-to-pod connectivity on port 5432
kubectl get networkpolicy -n databases
# Must have BOTH:
# - ingress from databases namespace on port 5432
# - egress to databases namespace on port 5432
```

### initdb secret has wrong keys

CNPG requires **exactly** `username` and `password` as keys in the initdb secret.

```bash
kubectl get secret <initdb-secret-name> -n databases -o jsonpath='{.data}' | jq 'keys'
# Must show: ["password","username"]
# Wrong key names (e.g. "user", "pass") cause the cluster to fail initialization
```

### WAL archiving failing

```bash
kubectl describe cluster <cluster-name> -n databases | grep -A10 "Continuous Archiving"

# Check MinIO credentials
kubectl get externalsecret cnpg-minio-secret -n databases

# Check if MinIO bucket exists and is accessible
kubectl logs -n databases -l cnpg.io/cluster=<cluster-name> -c postgres | grep barman
```

---

## Longhorn

### PVC stuck in Pending

```bash
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>

# Check Longhorn manager
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=30 | grep -i error

# Common cause: all replicas scheduled on same node (anti-affinity)
# Check node disk availability in Longhorn UI: longhorn.mmrajputhomelab.org
```

### Volume degraded (replica count < requested)

```bash
# Check volume health in Longhorn UI
# Navigate to Volumes → find the volume → check replica status

# Or via kubectl
kubectl get volumes -n longhorn-system
```

---

## Networking (Calico / NetworkPolicy)

### Pod cannot reach Kubernetes API

Calico evaluates NetworkPolicy **before** kube-proxy DNAT. Both IPs must be allowed:

```bash
# Test from within the affected namespace
kubectl run test --image=curlimages/curl --rm -it --restart=Never -n <namespace> \
  --overrides='...' -- curl -I https://10.96.0.1:443 --insecure --max-time 5
# Expected: HTTP 403 (connected, rejected by API)
# Timeout: NetworkPolicy is blocking

# Required egress rule in NetworkPolicy:
# - ipBlock: cidr: 10.96.0.1/32  port: 443
# - ipBlock: cidr: 192.168.178.34/32  port: 6443
```

### nginx-ingress cannot reach workload pod (NetworkPolicy blocking)

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep "upstream"

# Check workload NetworkPolicy allows ingress from ingress-nginx namespace
kubectl get networkpolicy -n <workload-namespace>

# nginx-ingress uses pod IPs. Rule must allow ingress on pod port (e.g. 8080), not service port (80)
```

---

## Observability Stack

### Prometheus targets showing DOWN

```bash
# Open https://prometheus.mmrajputhomelab.org/targets
# Check which targets are down and their error messages

# Common: kube-controller-manager, kube-scheduler — these are expected DOWN
# (bound to localhost only). All others should be UP.

# Check ServiceMonitors exist
kubectl get servicemonitor -A
```

### Grafana not loading dashboards (data source error)

```bash
kubectl exec -n monitoring -l app.kubernetes.io/name=grafana -- \
  curl -s http://prometheus-operated:9090/api/v1/status/config | head -5

kubectl exec -n monitoring -l app.kubernetes.io/name=grafana -- \
  curl -s http://loki:3100/ready
```

### Loki returning empty results

```bash
# Check Promtail is running on all 3 nodes
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail -o wide

# Check Promtail is shipping logs
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=20
# Look for: "Successfully sent batch"

# Check Loki MinIO credentials
kubectl get externalsecret loki-minio-credentials -n monitoring
```

---

## Keycloak / SSO

### SSO redirect fails (ArgoCD, Grafana, Nextcloud)

```bash
# Check Keycloak pod is running
kubectl get pods -n keycloak

# Check the OIDC secret is synced for the affected service
kubectl get externalsecret argocd-oidc-secret -n argocd
kubectl get externalsecret grafana-oidc-secret -n monitoring

# Check Keycloak logs
kubectl logs -n keycloak -l app.kubernetes.io/name=keycloakx --tail=50
```

### Login loop after successful Keycloak auth

Most common cause: `proxy-buffer-size` too small for the JWT token in nginx.

```bash
# Check nginx config
kubectl get configmap -n ingress-nginx ingress-nginx-controller -o yaml | grep proxy-buffer-size
# Must be: proxy-buffer-size: "16k"
```

---

## CI/CD (ARC / GitHub Actions)

### Runner pods not appearing

```bash
# Check ARC controller
kubectl get pods -n arc-systems
kubectl logs -n arc-systems -l app.kubernetes.io/name=gha-runner-scale-set-controller --tail=50

# Check GitHub App secret in arc-runners (must exist there, not just arc-systems)
kubectl get secret github-app-secret -n arc-runners
```

### Runner job fails with "job container" error

```bash
# Confirm ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=false is set in arc-runners values
kubectl get configmap -n arc-runners -o yaml | grep JOB_CONTAINER
```

### Runner work volume fails (chown error)

Work volumes must use `local-path`, not Longhorn. Longhorn causes permission/chown failures on runner work directories. Check values file for the ARC runner scale set.

---

## General Debug Commands

```bash
# All non-running pods
kubectl get pods -A | grep -v "Running\|Completed"

# Recent events cluster-wide
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Resource usage per node
kubectl top nodes

# Resource usage per pod (namespace)
kubectl top pods -n <namespace>

# Force ArgoCD to re-read from Git
kubectl annotate application <app-name> -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```
