# ADR-016: Reference Workload Selection

**Status:** Accepted
**Date:** March 2026
**Phase:** Phase 9 — Identity & Stateful Workloads

---

## Context

The platform needs a reference workload that:
1. Validates the entire platform stack end-to-end
2. Is realistic (not a toy application)
3. Exercises all platform layers: storage, databases, secrets, identity, observability, backup, and networking
4. Is self-hostable and useful in a homelab context
5. Has an existing Helm chart for GitOps deployment

A reference workload that exercises only 2–3 platform layers does not demonstrate platform completeness. The workload should stress-test the integration between layers.

---

## Decision

Deploy **Nextcloud** (Helm chart `nextcloud 9.0.4`, app `33.0.0`) as the primary platform reference workload.

Deployed in two environments:
- `nextcloud-staging` — single CNPG instance, no scheduled backup
- `nextcloud-production` — 2-instance CNPG with anti-affinity, Velero backup every 6 hours, Barman WAL archiving

---

## Rationale

### Platform layer coverage

| Platform layer | How Nextcloud exercises it |
|---------------|---------------------------|
| Storage | Longhorn PVC for user files |
| Databases | CNPG PostgreSQL cluster (staging + production) |
| Secrets | ESO syncs DB credentials and app admin password from Vault |
| Identity | Keycloak OIDC SSO (homelab realm) |
| Observability | Prometheus metrics scraping, Loki log aggregation |
| Backup | Velero for user files PVC, CNPG Barman for database PITR |
| Networking | Cloudflare Tunnel → nginx-ingress, NetworkPolicy default-deny |
| CI/CD | ARC runners update the image tag; ArgoCD promotes to staging then production |

No other candidate workload exercises all eight layers simultaneously.

### Self-hostable and useful

Nextcloud provides real value: sovereign file storage, calendar, contacts, and document editing. It is not a contrived demo application — it runs as a production workload in the homelab.

### Staging / Production parity

Deploying Nextcloud to both environments validates the workload onboarding pattern, demonstrates environment promotion via CI/CD, and tests the production CNPG HA configuration (2 instances, anti-affinity, WAL archiving).

---

## Consequences

**Positive:**
- Single workload validates the entire platform in a realistic scenario
- CNPG HA (primary + standby with anti-affinity) is exercised in production — validates CNPG replication and NetworkPolicy bidirectional port 5432 rules
- Velero + Barman restore paths are tested against a real application
- Keycloak OIDC integration is validated end-to-end

**Trade-offs:**
- Nextcloud is a complex application — configuration is non-trivial (PHP tuning, Redis session locking, OIDC client setup)
- PHP applications produce noisy logs — Loki storage fills faster than with leaner workloads
- Nextcloud upgrades require careful ordering (DB migration before app server start)

---

## Alternatives Considered

**WordPress:** Uses MySQL, not PostgreSQL — does not exercise CNPG. Rejected.

**Gitea/Forgejo:** Does not exercise Keycloak OIDC natively. Would work but covers fewer platform layers.

**A custom demo app:** Contrived; not useful beyond validation. Rejected in favour of a real application.

**Vaultwarden:** Good OIDC integration but does not exercise CNPG or large PVC storage. Useful as a *second* workload, not as the reference workload.

---

## Related

- [Workload Onboarding Guide](../reference/workload-onboarding.md)
- [Data Layer Reference](../reference/data-layer.md) — Nextcloud secret paths and CNPG clusters
- [Backup Procedures](../runbooks/backup-procedures.md) — Nextcloud-specific backup schedules
- [ADR-014: Backup Strategy](ADR-014-backup-strategy.md)
- [ADR-015: Identity Provider](ADR-015-identity-provider.md)
