# ADR-013: CI/CD Pipeline Strategy

## Status

Accepted

## Date

2026-03-26

## Last Updated

2026-03-31

## Context

Phase 10 introduces a CI/CD pipeline to automate application deployment from version
selection through to production. The platform already has ArgoCD managing all GitOps
deployments. The pipeline must integrate with this existing pattern rather than bypass it.

Two categories of workload exist in this homelab:
- Upstream third-party applications (Wiki.js, Nextcloud) — no custom image build required
- Future custom application images — would require a build stage

For upstream applications, the deployment artifact is a Helm values file with a pinned
image tag. Promoting a new version means updating that tag in Git and allowing ArgoCD to
deploy the change.

## Decision

### CI/CD Platform: GitHub Actions

GitHub Actions is selected over Tekton, Jenkins, and GitLab CI.

Tekton requires significant operator overhead on a resource-constrained cluster. Jenkins
carries substantial operational complexity for minimal benefit at this scale. GitHub Actions
is the dominant industry standard for open-source and mixed cloud/on-premises workflows,
provides native integration with ghcr.io and the existing GitHub repository, and requires
zero additional cluster infrastructure for the hosted runner tier.

**Portability note:** Gitea Actions uses identical workflow YAML syntax to GitHub Actions.
Switching to a fully sovereign stack (Gitea + Harbor) requires only endpoint and credential
changes — pipeline stages, ArgoCD flow, and cluster configuration remain identical. This
maps directly to BSI IT-Grundschutz and Schrems II requirements for data residency, where
CI/CD infrastructure may need to remain fully on-premises.

### Pipeline Model: Upstream Image Promotion (Not Build-From-Source)

Wiki.js and Nextcloud publish versioned images to Docker Hub. Building wrapper images adds
operational risk (base image maintenance, custom layer CVEs) with no functional benefit.
The pipeline treats version selection as the trigger: an operator selects a target version,
the pipeline scans the upstream image, and on success mirrors it to the internal registry
and commits the updated tag to the GitOps repository.

This model maps directly to how platform teams manage third-party software in regulated
environments: pin the version, scan before promotion, document the promotion in Git history.

### Image Registry: ghcr.io as Internal Mirror

Scanned and approved images are mirrored to `ghcr.io/mmrajput/<app>` before deployment.
The cluster pulls from this internal mirror, not directly from Docker Hub. This provides:
- Audit trail — only images that passed the security gate exist in the internal registry
- Rate limit immunity — Docker Hub pull limits do not affect cluster operations
- Sovereign image copy — images are under operator control, not subject to upstream deletion

A self-hosted registry (Harbor) was considered for fully air-gapped scenarios relevant to
BSI KRITIS environments but adds registry operational overhead out of scope for this phase.
The pipeline architecture supports substituting Harbor without restructuring the workflow.

### Self-Hosted Runner: Actions Runner Controller (ARC) Scale Sets

A self-hosted runner is deployed via ARC v0.14.0 using the scale set pattern
(`gha-runner-scale-set-controller` + `gha-runner-scale-set`). The runner operates in
`containerMode: kubernetes` with GitHub App authentication (App ID: 3200126).

Key decisions and constraints discovered during implementation:
- `containerMode: kubernetes` enforces job container requirement by default —
  overridden via `ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=false`
- Work volumes use `local-path` StorageClass, not Longhorn — Longhorn volumes are
  provisioned as root (uid 0) and cannot be chowned without `CAP_CHOWN`, which conflicts
  with `restricted` PSS. Ephemeral CI work directories do not require replication.
- Runner namespace `arc-runners` runs at `restricted` PSS — all security context
  requirements satisfied by the runner pod spec
- `sudo` is not available in runner pods — `allowPrivilegeEscalation: false` sets the
  `no_new_privs` flag. All tools installed to `~/.local/bin`, PATH persisted via
  `$GITHUB_PATH`
- ARC CRDs exceed ArgoCD's 262144 byte annotation limit — `ServerSideApply=true`
  required, consistent with CloudNativePG operator pattern

### Daemonless Image Operations: crane

All image operations use `crane` (google/go-containerregistry) rather than Docker CLI.
`containerMode: kubernetes` provides no Docker daemon — crane operates purely via registry
HTTP APIs, requiring no daemon, no privileged containers, and no DinD sidecars.

`crane copy` performs registry-to-registry transfers without downloading layers to the
runner pod, making it faster than docker pull + docker push for large images.

### Vulnerability Scanning: Trivy Binary (Not trivy-action)

Trivy is used for container image scanning. The `aquasecurity/trivy-action` GitHub Action
was evaluated but rejected — it spawns a job container internally, which conflicts with
ARC `containerMode: kubernetes`. The Trivy binary is installed directly to `~/.local/bin`
at pipeline runtime.

Scan scope is limited to OS packages (`--vuln-type os`) — Node.js application dependency
CVEs in vendored `node_modules` are the upstream developer's responsibility. Platform
operators cannot remediate application dependency CVEs by changing the image tag.

A `.trivyignore` file documents accepted CVEs with rationale and review dates, consistent
with BSI IT-Grundschutz SYS.1.6.A15 vulnerability management requirements.

### Promotion Strategy: Manual Dispatch with Environment Selection

The pipeline is triggered via `workflow_dispatch` with two inputs: `image_tag` and
`environment` (staging/production). Image promotion is a conscious operator decision,
not an automatic reaction to every upstream push.

This differs from the originally planned branch-based promotion (main → staging, tags →
production). The manual dispatch model was selected because:
- Upstream image versions are independent of Git branch state
- Operators need explicit control over which version enters production
- The audit trail (Git history of bot commits) provides equivalent traceability

The pipeline ends after committing the updated values file to Git. ArgoCD detects the
change via its default polling interval (3 minutes) and syncs the cluster automatically.
No explicit ArgoCD trigger is required — this avoids granting the runner service account
`patch` access to ArgoCD Application objects, which would allow spec modification beyond
annotation.

### ArgoCD Application Lifecycle: workloads/disabled/ Pattern

ArgoCD Application manifests are never deleted from Git when a workload is retired.
Instead, manifests are moved to `platform/argocd/apps/workloads/disabled/`, which is
excluded from the root-app directory recursion via:
```yaml
directory:
  recurse: true
  exclude: 'workloads/disabled/*'
```

This preserves institutional knowledge while preventing ArgoCD from managing retired
workloads. Re-enabling a workload requires only a `git mv` back to the active directory.

## Consequences

- The pipeline cannot catch CVEs introduced by the upstream vendor between scans. A
  scheduled re-scan workflow is the mitigation, to be added in a future phase.
- OS-only Trivy scan scope means application dependency CVEs are not gated. Accepted
  tradeoff — platform operators cannot remediate upstream application CVEs.
- Manual dispatch promotion requires operator awareness of available upstream versions.
  A scheduled workflow to check for new upstream releases is the future mitigation.
- Branch protection rules on `main` must be configured to prevent direct pushes that
  bypass the pipeline scan gate.
- `local-path` work volumes are node-local and not replicated. Acceptable for ephemeral
  CI workspaces — no data persistence requirement.
- ArgoCD polling delay (up to 3 minutes) between Git commit and cluster sync is acceptable
  for image promotion. Time-critical deployments can trigger a manual ArgoCD sync.

## Alternatives Considered

| Option | Rejected Reason |
|---|---|
| Tekton | Cluster resource overhead; complex CRD surface for this use case |
| Jenkins | Operational complexity; no advantage over GitHub Actions |
| Build wrapper image | Adds CVE surface; no functional benefit for upstream apps |
| Harbor self-hosted registry | Out of scope for Phase 10; architecture supports future addition |
| Multi-repo GitOps split | Correct for build-from-source; unnecessary complexity for promotion-only |
| trivy-action | Spawns job container — incompatible with ARC containerMode: kubernetes |
| docker pull/push | Requires Docker daemon — incompatible with ARC containerMode: kubernetes |
| kubectl annotate for ArgoCD trigger | Requires patch RBAC on Application objects — allows spec modification; rejected in favour of Git polling |
| Branch-based promotion | Upstream image versions are independent of Git branch state; manual dispatch provides better operator control |
| DinD (Docker-in-Docker) | Requires privileged containers — incompatible with restricted PSS |