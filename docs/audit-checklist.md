# Documentation Audit Checklist

Use this checklist at the start of any documentation review session. Hand it to Claude with:
> "Before suggesting any changes, work through `docs/audit-checklist.md` for every file you review."

Derived from issues found during the April 2026 documentation audit.

---

## 1. URL and Hostname Accuracy

- [ ] No `*.homelab.local` URLs remain in any `platform/` or `docs/` markdown file
- [ ] All service URLs match the actual ingress hostnames in `platform/networking/nginx-ingress/` and workload values files
- [ ] Verify: `grep -r "homelab.local" --include="*.md" .`

---

## 2. Namespace Accuracy

- [ ] ArgoCD namespace is `argocd`, not `platform`
- [ ] All `kubectl` commands in docs reference the correct namespace for each resource
- [ ] Verify: `grep -r "namespace: platform\|-n platform" --include="*.md" .`

---

## 3. Integration Claims — Verify Against Helm Values

For any statement claiming a feature is integrated or configured (SSO, auth, backup, monitoring), verify it against the actual Helm values file before accepting it as true.

| Claim type | Where to verify |
|------------|----------------|
| SSO / OIDC configured | `workloads/<app>/production-values.yaml` |
| Database configured | `workloads/<app>/production-values.yaml` — `externalDatabase` block |
| Backup configured | `workloads/<app>/production-values.yaml` — annotations and Velero schedules |
| Storage class | `workloads/<app>/production-values.yaml` — `persistence.storageClass` |
| Secret source | `platform/security/external-secrets/stores/` |

**Example mistake caught:** README stated "SSO integrated across ArgoCD, Grafana, and Nextcloud" — Nextcloud Helm values had no OIDC configuration. SSO was configured manually via Admin UI, not via the chart.

---

## 4. Secret Path Conventions

- [ ] Vault README and ESO examples use actual cluster paths (`secret/databases/`, `secret/minio/`, `secret/argocd/`) not generic placeholders (`secret/platform/`, `secret/apps/`)
- [ ] ESO `remoteRef.key` examples include the KV v2 `data/` segment (`secret/data/<path>`)
- [ ] Cross-reference all paths against `docs/reference/data-layer.md`

---

## 5. Storage Backend Claims

- [ ] Loki storage backend is verified against actual Helm values — is it filesystem PVC or MinIO?
- [ ] Any "planned future migration" notes are checked against git log to confirm if they shipped
- [ ] Prometheus storage class is `local-path` (intentional — not a gap to fix)
- [ ] Verify: `grep -r "filesystem\|local-path\|longhorn\|minio" platform/observability/*/values.yaml`

---

## 6. Bootstrap and Install Procedure Accuracy

- [ ] ArgoCD install method is raw manifest (`kubectl apply`), not `helm install`
- [ ] Bootstrap recovery procedures do not reference `kubectl delete namespace argocd` as a first step
- [ ] ArgoCD app namespace is `argocd` in all bootstrap commands
- [ ] `CreateNamespace=false` is noted — namespaces are managed via `bootstrap/namespaces/`

---

## 7. CI/CD Pipeline Description

- [ ] No statement claims "CI builds images" — the pipeline pulls, scans, and mirrors upstream images only
- [ ] ARC runners are triggered by manual `workflow_dispatch`, not by every code push
- [ ] ArgoCD polls Git every 120s — it is not webhook-triggered by default

---

## 8. Cross-Reference Link Validity

Run the following and verify every linked file exists:

```bash
# Find all markdown links
grep -r "\[.*\](.*.md)" --include="*.md" . | grep -oP '\(.*?\.md\)' | tr -d '()' | sort -u

# Check for common broken patterns
grep -r "gitops-using-argocd-guide" --include="*.md" .
grep -r "docs/guide/" --include="*.md" .   # typo: should be docs/guides/
grep -r "platform/grafana/" --include="*.md" .   # wrong path
grep -r "platform/loki/" --include="*.md" .      # wrong path
grep -r "platform/prometheus/" --include="*.md" . # wrong path
```

---

## 9. ADR Index Completeness

- [ ] Every `.md` file in `docs/adr/` is listed in `docs/adr/adr-README.md`
- [ ] All links in the ADR index use consistent paths (`docs/adr/ADR-0XX-*.md`)
- [ ] Run: `ls docs/adr/*.md | xargs -I{} basename {} | sort` and compare against the index

---

## 10. "Planned" vs "Implemented" State

Check every forward-looking note against git log and actual deployed manifests:

- [ ] No "Phase X: planned" notes for phases already marked Complete in README
- [ ] No "Future: S3/MinIO" notes for storage backends already using MinIO
- [ ] No "Production differences: OAuth2/OIDC" notes for services already using OIDC
- [ ] Verify: `grep -ri "planned\|future\|phase [0-9]" --include="*.md" platform/`

---

## 11. Directory Structure Accuracy

- [ ] Directory trees in READMEs match the actual repo structure
- [ ] File paths referenced in prose match actual file locations
- [ ] Verify key paths:
  ```bash
  ls platform/networking/nginx-ingress/
  ls platform/observability/grafana/
  ls platform/observability/loki/
  ls platform/observability/prometheus/
  ls platform/security/vault/
  ls platform/security/external-secrets/
  ```

---

## 12. Tone and Framing

- [ ] No CKA exam tips or exam-focused framing in operational docs
- [ ] Troubleshooting guides cover the full platform stack, not just cluster installation issues
- [ ] "Production differences" sections do not describe features already implemented as future work

---

## Sign-off

After working through this checklist, summarise:
1. Files with factual errors found
2. Files with stale content found
3. Broken links found
4. Claims that could not be verified against the codebase (flag for human review)
