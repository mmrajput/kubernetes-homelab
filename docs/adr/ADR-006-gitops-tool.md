# ADR-006: GitOps Tool Selection

## Status

Accepted

## Date

2026-01-05

## Context

The homelab requires a GitOps solution to manage Kubernetes deployments declaratively. Requirements:

- Continuous delivery from Git repository to cluster
- Support for Helm charts and plain manifests
- Visibility into deployment state and sync status
- Self-healing capability (drift detection and correction)
- Manageable learning curve for single operator

## Decision

Use **ArgoCD** as the GitOps platform.

## Rationale

| Criteria | ArgoCD | Flux CD |
|----------|--------|---------|
| Web UI | ✅ Full-featured built-in | ❌ None (requires Weave GitOps add-on) |
| Helm support | ✅ Native | ✅ Via Helm Controller |
| Learning curve | ✅ Easier (visual feedback) | ⚠️ Steeper (CLI-first) |
| Job market demand | ✅ Higher (more job postings) | ⚠️ Growing adoption |
| Multi-tenancy | ✅ Built-in Projects, RBAC | ⚠️ Requires Flux Tenancy setup |
| App-of-Apps pattern | ✅ Native support | ⚠️ Kustomize overlays |
| Resource usage | ⚠️ Higher (~500MB) | ✅ Lower (~200MB) |
| CNCF status | ✅ Graduated | ✅ Graduated |

**Key factors:**

1. **Web UI for debugging** — Visual representation of application state, sync status, and resource hierarchy significantly accelerates troubleshooting and learning.

2. **Job market alignment** — ArgoCD appears more frequently in Platform Engineering job requirements based on market research.

3. **App-of-Apps pattern** — Native support for managing multiple applications through a single root application simplifies platform management.

4. **Lower barrier to entry** — UI provides immediate feedback loop, reducing time to productivity.

## Consequences

### Positive

- Visual debugging accelerates learning and troubleshooting
- Strong community with extensive documentation
- Native Helm and Kustomize support
- Built-in RBAC and multi-tenancy for future scaling
- Portfolio demonstrations benefit from visual UI

### Negative

- Higher resource consumption than Flux
- More components to manage (server, repo-server, controller, redis)
- UI can become a crutch if over-relied upon

## Alternatives Considered

### Flux CD

Rejected due to:
- No built-in UI increases initial learning friction
- CLI-first approach less suitable for demonstrating work visually
- App-of-Apps pattern requires more manual configuration

**Note:** Flux is an excellent choice for teams preferring CLI-centric workflows or resource-constrained environments.

### Jenkins X

Rejected due to:
- Heavyweight for homelab scale
- Opinionated CI/CD pipeline not needed (using GitOps only)

### Manual kubectl/Helm

Rejected due to:
- No drift detection or self-healing
- No audit trail of deployments
- Doesn't demonstrate GitOps competency

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [CNCF GitOps Principles](https://opengitops.dev/)
- [ArgoCD vs Flux Comparison](https://www.cncf.io/blog/2023/06/14/argo-cd-and-flux-cncf-gitops-tools/)
