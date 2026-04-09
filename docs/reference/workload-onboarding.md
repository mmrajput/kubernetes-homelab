# Workload Onboarding Guide

## Prerequisites

1. Vault secrets created at the relevant paths
2. Namespace bootstrapped manually before pushing ArgoCD apps:
   ```bash
   kubectl apply -f bootstrap/namespaces/workloads/<app>/staging-namespace.yaml
   kubectl apply -f bootstrap/namespaces/workloads/<app>/production-namespace.yaml
   ```

---

## Files per workload (single atomic commit)

```
bootstrap/namespaces/workloads/<app>/staging-namespace.yaml
bootstrap/namespaces/workloads/<app>/production-namespace.yaml
platform/data/cnpg/clusters/<app>-cluster.yaml              # staging CNPG
platform/data/cnpg/clusters/<app>-prod-cluster.yaml         # production CNPG
platform/security/external-secrets/stores/databases/<app>-db-secret.yaml
platform/security/external-secrets/stores/workloads/<app>-staging-secret.yaml
platform/security/external-secrets/stores/workloads/<app>-production-secret.yaml
platform/networking/network-policies/workloads/<app>/staging-netpol.yaml
platform/networking/network-policies/workloads/<app>/production-netpol.yaml
workloads/<app>/staging-values.yaml
workloads/<app>/production-values.yaml
platform/argocd/apps/workloads/workloads-appset.yaml        # add element
```

### Namespace label

Every workload namespace must carry:
```yaml
labels:
  homelab.io/role: workload
```

This label allows ingress-nginx and databases network policies to match workload namespaces automatically — no per-workload edits to platform netpols required.

---

## ArgoCD ApplicationSet element (add to workloads-appset.yaml)

```yaml
- name: <app>-staging
  helmRepoURL: <helm-repo-url>
  chart: <chart-name>
  chartVersion: <version>
  namespace: <app>-staging
  valuesFile: workloads/<app>/staging-values.yaml
```

---

## ArgoCD Application template (standalone, if not using AppSet)

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

---

## CI/CD pipeline (wiki.js reference)

**File:** `.github/workflows/ci.yaml`
**Trigger:** Manual `workflow_dispatch` (image_tag, environment inputs)
**Runner:** `homelab-runner` (ARC scale set, 1–3 runners, `arc-runners` namespace)

Flow:
1. Pull upstream image from Docker Hub
2. Trivy scan (HIGH/CRITICAL CVEs with fixes → block)
3. Copy to ghcr.io via crane
4. Update image tag in values file with `sed`
5. `git commit` + push → ArgoCD auto-syncs within 2 minutes

ARC config: `ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=false`, work volumes on `local-path`.
GitHub App secret must exist in **both** `arc-runners` and `arc-systems` namespaces.

---

## Enhancement roadmap

See `docs/reference/enhancement-roadmap.md`.
