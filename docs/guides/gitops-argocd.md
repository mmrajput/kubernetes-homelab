# GitOps with ArgoCD: Implementation Guide

## Overview

This guide covers GitOps implementation using ArgoCD, including architecture concepts, deployment patterns, and operational best practices for Kubernetes environments.

---

## What is GitOps?

GitOps is a declarative approach to continuous delivery where Git serves as the single source of truth for infrastructure and application configuration.

### Traditional Deployment vs GitOps

**Traditional Approach:**
```
Developer → kubectl apply → Cluster
DevOps   → helm install   → Cluster
Platform → manual fixes   → Cluster

Problems:
- No audit trail (who deployed what, when, why?)
- State drift over time
- Manual interventions not tracked
- Disaster recovery unclear
```

**GitOps Approach:**
```
Git (desired state) → ArgoCD (reconciler) → Cluster (actual state)
                           ↓
                     Continuous sync & drift detection
```

**Key Principle:** Git becomes the control plane for the entire platform. ArgoCD enforces what Git declares.

### Benefits

**For Platform Engineers:**
- Declarative infrastructure at the application layer
- Self-service for developers (PR to Git, auto-deploy)
- Drift detection (alerts if manual changes occur)
- Disaster recovery (`git clone` + ArgoCD = rebuilt cluster)
- Full audit trail (every change is a Git commit)

**For Organizations:**
- Compliance (SOC2, ISO27001 auditors value immutable logs)
- Security (access control via Git PRs, not kubectl)
- Multi-environment support (same manifests, different branches)
- Deployment velocity (deploy frequently, revert easily)

---

## ArgoCD Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                         ArgoCD                              │
│                                                             │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐     │
│  │   API Server │   │ Repo Server  │   │ Application  │     │
│  │              │   │              │   │  Controller  │     │
│  │ (Web UI/CLI) │   │ (Git Fetch)  │   │ (Reconciler) │     │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘     │
│         │                  │                  │             │
│         └──────────────────┴──────────────────┘             │
│                            │                                │
└────────────────────────────┼────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
   ┌─────────┐          ┌─────────┐         ┌─────────┐
   │   Git   │          │  K8s    │         │  Redis  │
   │  Repo   │          │ Cluster │         │ (cache) │
   └─────────┘          └─────────┘         └─────────┘
```

| Component | Purpose |
|-----------|---------|
| **API Server** | Web UI, gRPC API, CLI interface. Handles authentication and RBAC. |
| **Repo Server** | Clones Git repos, renders manifests (Helm, Kustomize, YAML), caches content. |
| **Application Controller** | The reconciliation engine. Compares Git (desired) vs Cluster (actual) state. |
| **Redis** | Caches Git repo data and temporary tokens. Non-critical for small deployments. |

### The Reconciliation Loop

Every 3 minutes (default), ArgoCD:

1. **Fetch:** Repo Server pulls latest from Git
2. **Render:** Manifests are rendered (Helm/Kustomize)
3. **Compare:** Controller gets current cluster state via `kubectl get`
4. **Detect:** Compare Git state vs Cluster state
5. **Act:**
   - If different → Show "OutOfSync"
   - If auto-sync enabled → Apply changes
   - If manual → Wait for approval
6. **Health:** Verify pods are Running/Healthy

**Key insight:** Push to Git, walk away. ArgoCD notices and deploys automatically.

---

## Architecture Decisions

### Ingress Strategy

**Recommendation:** Use nginx-ingress with NodePort

| Option | Pros | Cons |
|--------|------|------|
| Port-forward | Quick setup | Breaks on disconnect, not production-like |
| nginx-ingress | Persistent access, production pattern | Additional component to manage |

**Why nginx-ingress:**
- Access services via hostnames (e.g., `argocd.homelab.local`)
- Production-equivalent pattern
- Required for observability tools (Grafana, Prometheus)
- Survives reboots and disconnections

### Persistence Strategy

**Recommendation:** Use emptyDir (no persistence)

**ArgoCD State:**
| Data | Storage | Recoverable? |
|------|---------|--------------|
| Application definitions | Kubernetes CRDs | ✅ Yes |
| Git repo cache | Rebuilt on restart | ✅ Yes |
| User sessions | Temporary tokens | ✅ Re-login |

**If ArgoCD pod dies:**
1. Pod restarts
2. Re-reads Applications from cluster CRDs
3. Re-clones Git repos
4. Reconciles everything
5. Back to normal in ~30 seconds

**Production guidance:**
- Small clusters: emptyDir is fine
- Large enterprises: Persistent volumes for cache optimization

### Repository Strategy

**Recommendation:** Monorepo for homelab/small teams

| Approach | Best For | Trade-offs |
|----------|----------|------------|
| Monorepo | Single-person, small teams | All context in one place, atomic commits |
| Multi-repo | Large organizations | Per-team RBAC, separate release cadence |

**Monorepo structure:**
```
kubernetes-homelab/
├── infra/                    # Infrastructure provisioning
│   ├── proxmox/
│   └── ansible/
├── platform/                 # Platform services (GitOps managed)
│   ├── argocd/
│   │   ├── install/          # Bootstrap values
│   │   ├── apps/             # App-of-Apps manifests
│   │   └── root-app.yaml
│   └── nginx-ingress/
├── observability/            # Monitoring stack
└── apps/                     # Applications
```

---

## App-of-Apps Pattern

The App-of-Apps pattern enables scalable, declarative management of multiple ArgoCD Applications.

### How It Works

```
root-app (manually bootstrapped once)
    │
    └── watches: platform/argocd/apps/
            │
            ├── argocd-app.yaml ──────▶ ArgoCD (self-managed)
            ├── nginx-ingress-app.yaml ▶ Ingress controller
            └── prometheus-app.yaml ───▶ Monitoring
```

**Workflow:**
1. `root-app` monitors a directory in Git
2. Any `*.yaml` file in that directory becomes an Application
3. ArgoCD deploys and manages each Application
4. Adding a service = committing a YAML file

### Benefits

- **Self-service:** Add services via Git commit
- **Scalable:** One root-app can manage hundreds of applications
- **Discoverable:** All applications visible in ArgoCD UI
- **GitOps native:** Applications themselves are managed declaratively

### Example Application Manifest

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-ingress
  namespace: platform
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/mmrajput/kubernetes-single-cluster.git
    targetRevision: main
    path: platform/nginx-ingress
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ingress-nginx
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## Sync Policies

### Sync Options

| Setting | Purpose | When to Use |
|---------|---------|-------------|
| `automated.selfHeal: true` | Revert manual cluster changes | Enforce Git as source of truth |
| `automated.selfHeal: false` | Allow manual overrides | Debugging, emergencies |
| `automated.prune: true` | Delete resources removed from Git | Most applications |
| `automated.prune: false` | Keep orphaned resources | Databases, stateful workloads |

### Recommendations by Workload Type

| Workload | prune | selfHeal | Reason |
|----------|-------|----------|--------|
| Stateless apps | true | true | Safe to auto-manage |
| Platform services | true | true | Consistency matters |
| Databases | false | false | Protect data |
| ArgoCD itself | false | true | Prevent accidental deletion |

---

## Common Pitfalls

### 1. "Git Has Everything" Misconception

**Reality:** Git has desired state, but cluster has additional dynamic resources:
- ConfigMaps/Secrets created by Operators
- PVCs created by StatefulSets
- CRD instances created by controllers

**Lesson:** Git is source of truth for declared resources, not all cluster state.

### 2. Auto-Sync Everything

**Mistake:** Setting `automated: { prune: true, selfHeal: true }` globally

**Risk:**
- Databases: Auto-prune can cause data loss
- StatefulSets: Careful with prune
- Critical infrastructure: Manual sync preferred

### 3. Forgetting Disaster Recovery

**Mistake:** "Git is my backup!"

**Reality:**
- Git has manifests, not data
- PersistentVolumes need separate backup (Velero)
- GitOps is deployment, not backup

### 4. Secrets in Git

**Never commit secrets to Git**, even in private repositories.

**Solutions:**
- Sealed Secrets (encrypt before commit)
- External Secrets Operator (fetch from Vault/AWS)
- SOPS (encrypt files with GPG)

---

## Enterprise GitOps Patterns

### Multi-Team Structure

```
Git Repositories:
├── platform-infrastructure (Platform Team)
│   ├── argocd/
│   ├── prometheus/
│   └── cert-manager/
│
├── team-payments-apps (Payments Team)
│   ├── payment-api/
│   └── billing-service/
│
└── team-auth-apps (Auth Team)
    ├── oauth-server/
    └── user-management/

ArgoCD Projects:
├── platform    → Can deploy infrastructure
├── payments    → Limited to payments-* namespaces
└── auth        → Limited to auth-* namespaces
```

### Role Separation

**Platform Team:**
- Manages ArgoCD itself
- Deploys platform services
- Sets up ArgoCD Projects for app teams
- Defines deployment policies

**App Teams:**
- Create Applications in their repos
- Self-service deploy via Git PRs
- No direct kubectl access needed

---

## Quick Reference

### ArgoCD CLI Commands

```bash
# Login
argocd login argocd.homelab.local:30080

# List applications
argocd app list

# Get application details
argocd app get <app-name>

# Sync application
argocd app sync <app-name>

# Refresh from Git
argocd app refresh <app-name>

# View application history
argocd app history <app-name>

# Rollback
argocd app rollback <app-name> <history-id>
```

### Troubleshooting

```bash
# Check ArgoCD pods
kubectl get pods -n platform

# View controller logs
kubectl logs -n platform statefulset/argocd-application-controller

# View server logs
kubectl logs -n platform deployment/argocd-server

# Check application status
argocd app get <app-name> --show-operation
```

---

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Architecture](https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/)
- [GitOps Principles](https://opengitops.dev/)
- [App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)

---

**Last Updated:** January 2026
