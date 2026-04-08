# ArgoCD

GitOps continuous delivery for the homelab cluster, implementing the App-of-Apps pattern.

## Overview

| Property | Value |
|----------|-------|
| Chart | argo-cd 9.3.0 |
| App version | ArgoCD 3.2.3 |
| Namespace | `argocd` |
| Install method | Raw upstream manifest (not Helm) |
| URL | argocd.mmrajputhomelab.org |
| Sync interval | 120s (poll) |

## App-of-Apps Architecture

```
root-app.yaml  (applied manually once via kubectl)
    │
    └── watches platform/argocd/apps/ (all subdirs)
            │
            ├── networking/   ── cert-manager, ingress-nginx, network-policies
            ├── security/     ── vault, external-secrets, keycloak
            ├── data/         ── cnpg, longhorn, minio, velero, rclone
            ├── observability/ ─ prometheus, grafana, loki, promtail
            ├── ci-cd/        ── arc-systems, arc-runners
            └── workloads/    ── workloads-appset (ApplicationSet)
```

Every `*.yaml` file added to `platform/argocd/apps/` is automatically discovered and deployed by ArgoCD. No manual sync required.

## Application Conventions

All platform applications follow these settings:

```yaml
metadata:
  namespace: argocd                     # All apps live in argocd namespace
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true                    # ArgoCD corrects manual drift
    syncOptions:
      - CreateNamespace=false           # Namespaces managed via bootstrap/
  sources:
    - repoURL: <helm-chart-repo>
      chart: <chart>
      targetRevision: <pinned-version>
      helm:
        valueFiles:
          - $values/platform/<layer>/<service>/values.yaml
    - repoURL: https://github.com/mmrajput/kubernetes-homelab-01
      targetRevision: HEAD
      ref: values                       # Multi-source: chart + Git values
```

`ServerSideApply=true` is added for CRD-heavy operators: CNPG, ESO, ARC.

## Common Operations

```bash
# List all applications
argocd app list

# Check a specific app
argocd app get <app-name>

# Force hard refresh (re-read from Git immediately)
kubectl annotate application <app-name> -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# Disable selfHeal before a manual fix
kubectl patch application <app-name> -n argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":false}}}}'

# Re-enable selfHeal after fix
kubectl patch application <app-name> -n argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

## Access

**Web UI:** argocd.mmrajputhomelab.org (SSO via Keycloak, `argocd-admins` group)

**Port-forward fallback (if ingress is down):**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080
# Initial admin password:
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

## Troubleshooting

### Application stuck in Progressing

```bash
argocd app get <app-name>
kubectl describe application <app-name> -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### Sync failed

```bash
# Dry-run to see what ArgoCD would apply
argocd app sync <app-name> --dry-run

# Check events in target namespace
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### selfHeal deadlock (manual apply reverts immediately)

```bash
# Disable selfHeal, fix the resource, re-enable (see Common Operations above)
```

### Finalizer blocking deletion

```bash
kubectl patch application <app-name> -n argocd \
  --type json \
  -p '[{"op":"remove","path":"/metadata/finalizers"}]'
kubectl delete application <app-name> -n argocd
```

### Nil pointer dereference on sync

ArgoCD v3.2.3 triggers a nil pointer error when syncing Namespace resources. Namespaces are managed via `bootstrap/namespaces/` — never via ArgoCD.

### API timeout during sync (NetworkPolicy deadlock)

Check that the `argocd` namespace NetworkPolicy allows egress to both Kubernetes API IPs:
- `10.96.0.1/32:443` (ClusterIP)
- `192.168.178.34:6443` (control plane, post-Calico DNAT)

See `platform/networking/network-policies/argocd-netpol.yaml`.

## Bootstrap Recovery

If ArgoCD needs to be reinstalled from scratch:

```bash
# 1. Re-apply bootstrap namespaces
kubectl apply -f bootstrap/namespaces/

# 2. Re-install ArgoCD from raw manifest
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.3/manifests/install.yaml

# 3. Wait for pods to be ready
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=120s

# 4. Re-apply root-app to restore the App-of-Apps
kubectl apply -f platform/argocd/root-app.yaml

# ArgoCD will rediscover and sync all applications from Git
kubectl get applications -n argocd -w
```

Full rebuild procedure: [`docs/runbooks/cluster-rebuild.md`](../../docs/runbooks/cluster-rebuild.md)

## Related Documentation

- [Platform README](../README.md)
- [ADR-006: GitOps Tool Selection](../../docs/adr/ADR-006-gitops-tool.md)
- [ADR-008: App-of-Apps Pattern](../../docs/adr/ADR-008-app-of-apps-pattern.md)
- [Cluster Rebuild Runbook](../../docs/runbooks/cluster-rebuild.md)

---

**Last Updated:** April 2026
