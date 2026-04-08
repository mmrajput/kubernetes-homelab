# Platform Inventory

## Service endpoints

All via Cloudflare Tunnel → nginx NodePort 30080/30443.

| Service | URL |
|---------|-----|
| ArgoCD | argocd.mmrajputhomelab.org |
| Grafana | grafana.mmrajputhomelab.org |
| Prometheus | prometheus.mmrajputhomelab.org |
| Alertmanager | alertmanager.mmrajputhomelab.org |
| Longhorn | longhorn.mmrajputhomelab.org |
| MinIO Console | minio-console.mmrajputhomelab.org |
| Vault | vault.mmrajputhomelab.org |
| Keycloak | keycloak.mmrajputhomelab.org |
| Homepage | homepage.mmrajputhomelab.org |
| Nextcloud (prod) | nextcloud.mmrajputhomelab.org |
| Nextcloud (staging) | nextcloud-staging.mmrajputhomelab.org |

---

## ArgoCD application inventory

All apps: `namespace: argocd`, multi-source pattern, `CreateNamespace=false`, `selfHeal: true`.

| App name | Chart | Version | Destination NS |
|----------|-------|---------|----------------|
| argocd | argo-cd | 9.3.0 | argocd |
| cert-manager | cert-manager | v1.16.2 | cert-manager |
| ingress-nginx | ingress-nginx | 4.11.3 | ingress-nginx |
| network-policies | Git raw manifests | HEAD | (multi-NS) |
| vault | vault | 0.32.0 | vault |
| external-secrets | external-secrets | 2.1.0 | external-secrets |
| external-secrets-config | Git raw manifests | HEAD | external-secrets |
| external-secrets-stores | Git raw manifests | HEAD | (multi-NS) |
| keycloak | keycloakx | 7.1.9 | keycloak |
| cloudnativepg | cloudnative-pg | 0.27.1 | cnpg-system |
| cnpg-clusters | Git raw manifests | HEAD | databases |
| longhorn | longhorn | 1.7.2 | longhorn-system |
| minio | minio | 5.4.0 | minio |
| velero | velero | 12.0.0 | velero |
| rclone-onedrive-sync | Git raw manifests | HEAD | velero |
| kube-prometheus-stack | kube-prometheus-stack | 65.8.1 | monitoring |
| grafana | grafana | 10.5.15 | monitoring |
| loki | loki | 6.20.0 | monitoring |
| promtail | promtail | 6.16.6 | monitoring |
| arc-systems | gha-runner-scale-set-controller | 0.14.0 | arc-systems |
| arc-runners | gha-runner-scale-set | 0.14.0 | arc-runners |
| homepage | homepage | 2.1.0 | homepage |
| nextcloud-staging | nextcloud | 9.0.4 | nextcloud-staging |
| nextcloud-production | nextcloud | 9.0.4 | nextcloud-production |

---

## ArgoCD Application template (multi-source)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app>-staging
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: workloads
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: <helm-chart-repo>
      chart: <chart-name>
      targetRevision: <version>
      helm:
        valueFiles:
          - $values/workloads/<app>/staging-values.yaml
    - repoURL: https://github.com/mmrajput/kubernetes-homelab
      targetRevision: HEAD
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: <app>-staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
```
