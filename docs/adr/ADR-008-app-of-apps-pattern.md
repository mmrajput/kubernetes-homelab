# ADR-008: App-of-Apps Pattern

## Status

Accepted — Updated Phase 8 (ApplicationSets adopted for category management)

## Date

2026-01-12 — Initial decision (App-of-Apps, individual Application files)
2026-03-01 — Updated: ApplicationSets adopted per category; App-of-Apps retained for bootstrap

## Context

ArgoCD can manage applications in multiple ways. As the platform grows, need a scalable pattern for:

- Managing multiple ArgoCD Applications declaratively
- Adding new platform services without manual ArgoCD UI interaction
- Enabling ArgoCD to manage itself (self-management)
- Maintaining a single source of truth in Git

Options evaluated:
1. Manual Application creation via UI/CLI
2. App-of-Apps pattern (root application watches directory)
3. ApplicationSets (template-based generation)
4. Helm umbrella chart

## Decision

Implement a **hybrid App-of-Apps + ApplicationSets pattern**:

- A single root `Application` (`argocd-app.yaml`) bootstraps ArgoCD's self-management and watches `platform/argocd/apps/` via directory recursion.
- Within that directory, each platform category (`networking`, `security`, `data`, `observability`, `ci-cd`, `workloads`) is managed by an `ApplicationSet`, not individual `Application` files.
- ApplicationSets were initially rejected (see below) but adopted in Phase 8 once the per-category list pattern made the value clear.

## Rationale

| Criteria | Manual Creation | App-of-Apps | ApplicationSets | Helm Umbrella |
|----------|----------------|-------------|-----------------|---------------|
| Declarative | ❌ Imperative | ✅ Fully | ✅ Fully | ✅ Fully |
| Learning curve | ✅ Simple | ✅ Moderate | ⚠️ Steeper | ⚠️ Helm knowledge |
| Flexibility | ✅ Full control | ✅ Full control | ⚠️ Template constraints | ⚠️ Chart structure |
| Scalability | ❌ Doesn't scale | ✅ Good | ✅ Excellent | ⚠️ Complex values |
| Self-service | ❌ Manual steps | ✅ Git commit only | ✅ Git commit only | ⚠️ Chart updates |
| Visibility | ⚠️ UI only | ✅ Git + UI | ✅ Git + UI | ⚠️ Nested charts |

**Key factors:**

1. **Pure GitOps workflow** — Adding a service = commit YAML file to `platform/argocd/apps/`. No UI or CLI interaction required.

2. **Appropriate complexity** — ApplicationSets are powerful but overkill for homelab scale. App-of-Apps provides declarative management without templating complexity.

3. **Self-management capability** — ArgoCD can manage its own installation, enabling configuration changes via Git commits.

4. **Clear directory structure** — Each Application manifest is a separate file, easy to understand and modify.

## Implementation

```
root-app (manually bootstrapped once via kubectl apply)
    │
    └── watches: platform/argocd/apps/ (recurse: true)
            │
            ├── argocd-app.yaml              → ArgoCD self-managed (Application)
            ├── networking/
            │   └── networking-appset.yaml   → nginx-ingress, cert-manager, network-policies (ApplicationSet)
            ├── security/
            │   └── security-appset.yaml     → vault, external-secrets, keycloak (ApplicationSet)
            ├── data/
            │   └── data-appset.yaml         → cnpg, longhorn, minio, velero, rclone (ApplicationSet)
            ├── observability/
            │   └── observability-appset.yaml → prometheus, grafana, loki, promtail (ApplicationSet)
            ├── ci-cd/
            │   └── ci-cd-appset.yaml        → arc-systems, arc-runners (ApplicationSet)
            └── workloads/
                └── workloads-appset.yaml    → nextcloud, homepage (ApplicationSet)
```

**Workflow to add a service to an existing category:**
```bash
# Add an element to the list generator in the relevant AppSet
vim platform/argocd/apps/observability/observability-appset.yaml

# Commit and push
git commit -m "feat(observability): add tempo tracing"
git push
# ArgoCD detects the ApplicationSet change and creates the new Application automatically
```

**All Applications use multi-source pattern** — Helm chart from the upstream Helm repo, values file from this Git repository:
```yaml
sources:
  - repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 65.8.1
    helm:
      valueFiles:
        - $values/platform/observability/prometheus/values.yaml
  - repoURL: https://github.com/mmrajput/kubernetes-homelab
    targetRevision: HEAD
    ref: values
```

## Consequences

### Positive

- True GitOps: all changes via Git, full audit trail
- Self-service: add services without ArgoCD UI access
- Self-management: ArgoCD configuration changes via Git
- Scalable: pattern works for 2 or 200 applications
- Discoverable: root-app shows all managed applications

### Negative

- Bootstrap complexity: root-app must be created manually once
- Two-layer abstraction: root-app → child apps (can confuse initially)
- Circular dependency risk: misconfigured argocd-app can break self-management

### Risks Mitigated

- **ArgoCD self-management safety:**
  - `automated.prune: false` prevents accidental deletion
  - `automated.selfHeal: true` corrects drift
  - Manual sync option for major upgrades

## Alternatives Considered

### Manual Application Creation

Rejected due to:
- Imperative workflow breaks GitOps principles
- No audit trail in Git
- Doesn't scale beyond a few applications

### ApplicationSets (standalone)

Initially rejected as "overkill" — the list generator pattern adds a template layer that obscures individual services. However, ApplicationSets were adopted in Phase 8 for category management. The hybrid pattern (App-of-Apps bootstrap + ApplicationSets per category) provides the benefits of both: a clear directory-based overview via the root app, and a scalable list-based pattern for adding services within a category.

ApplicationSets remain inappropriate as the sole top-level pattern — a root ApplicationSet that auto-discovers all services loses the explicit overview that App-of-Apps provides.

### Helm Umbrella Chart

Rejected due to:
- Mixes Helm packaging with ArgoCD management
- Less visibility into individual applications
- More complex dependency management

## References

- [ArgoCD App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
