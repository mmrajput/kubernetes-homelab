# ADR-008: App-of-Apps Pattern

## Status

Accepted

## Date

2026-01-12

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

Implement **App-of-Apps pattern** with a root application watching `platform/argocd/apps/` directory.

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
root-app (manually bootstrapped once)
    │
    └── watches: platform/argocd/apps/
            │
            ├── argocd-app.yaml ────────→ ArgoCD (self-managed)
            ├── nginx-ingress-app.yaml ─→ nginx-ingress
            └── [future-service].yaml ──→ Auto-discovered
```

**Workflow to add new service:**
```bash
# 1. Create Application manifest
cat > platform/argocd/apps/prometheus-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: platform
spec:
  project: default
  source:
    repoURL: https://github.com/mmrajput/kubernetes-homelab.git
    targetRevision: main
    path: observability/prometheus
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
EOF

# 2. Commit and push
git add -A && git commit -m "feat(observability): add prometheus application"
git push

# 3. ArgoCD auto-discovers and deploys (no manual intervention)
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

### ApplicationSets

Rejected due to:
- Generator templates add complexity
- Overkill for current homelab scale
- Less explicit than individual Application files

**Note:** ApplicationSets are excellent for multi-cluster or multi-tenant scenarios with predictable patterns.

### Helm Umbrella Chart

Rejected due to:
- Mixes Helm packaging with ArgoCD management
- Less visibility into individual applications
- More complex dependency management

## References

- [ArgoCD App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
