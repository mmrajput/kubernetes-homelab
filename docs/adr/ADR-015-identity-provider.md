# ADR-015: Identity Provider Selection

**Status:** Accepted
**Date:** March 2026
**Phase:** Phase 9 — Identity & Stateful Workloads

---

## Context

The platform needs centralised identity for Single Sign-On (SSO) across multiple services: ArgoCD, Grafana, and Nextcloud. Without a centralised identity provider, each service manages its own users independently — creating credential sprawl and no unified access control.

Requirements:
- OIDC provider (all target services support OIDC)
- Self-hosted (data sovereignty — no cloud IdP dependency)
- Kubernetes-native deployment
- Supports group-based role mapping (ArgoCD admin group, Grafana roles)
- PostgreSQL backend (CNPG already available in the cluster)

---

## Decision

Deploy **Keycloak** (via `keycloakx` Helm chart v7.1.9, Keycloak 26.5.5) as the centralised OIDC identity provider.

- Realm: `homelab`
- HTTP path: `/` (not `/auth` — Keycloak 17+ default)
- PostgreSQL backend: `keycloak-db` CNPG cluster
- OIDC clients: `argocd`, `grafana`, `nextcloud`
- Group: `argocd-admins` → ArgoCD admin + Grafana admin role mapping

---

## Rationale

| Criteria | Keycloak | Authentik | Dex | Zitadel |
|----------|----------|-----------|-----|---------|
| OIDC support | Full | Full | Limited (federation only) | Full |
| Self-hosted | Yes | Yes | Yes | Yes |
| Kubernetes support | Helm chart | Helm chart | Helm chart | Helm chart |
| Group-based RBAC | Yes | Yes | Via upstream IdP | Yes |
| Admin UI | Comprehensive | Comprehensive | Minimal | Comprehensive |
| PostgreSQL backend | Native | Native | Requires separate DB | Native |
| Maturity | Very high (Red Hat) | High | High (CNCF) | Medium |
| Complexity | High | Medium | Low | Medium |

**Keycloak was chosen because:**
- It is the industry standard for enterprise OIDC/SAML — directly transferable skills to production environments
- Native group-based RBAC that ArgoCD and Grafana both support natively (`argocd-admins` group → admin role)
- First-class PostgreSQL backend with CNPG (Barman WAL backup coverage extends to identity data)
- Nextcloud has a well-tested Keycloak OIDC integration

**Dex was rejected** because it is a federation layer, not a standalone IdP — it requires an upstream identity source.

**Authentik** would also have worked, but Keycloak's wider enterprise adoption makes it more portfolio-relevant.

---

## Consequences

**Positive:**
- Single set of credentials for ArgoCD, Grafana, and Nextcloud
- Group membership controls access level across all services without per-service configuration
- Keycloak realm export enables identity backup and migration
- CNPG backs up Keycloak's PostgreSQL database (PITR available)

**Trade-offs:**
- Keycloak is operationally complex — realm configuration is not GitOps managed (no native Kubernetes operator for realm state in this setup)
- Keycloak requires `proxy-buffer-size: 128k` in nginx for its large JWT tokens (Keycloak-specific)
- If Keycloak is unavailable, all SSO-gated services are inaccessible (though ArgoCD has a local admin fallback)
- Cold-start dependency: Keycloak must be configured before ESO can sync OIDC client secrets

---

## Known Configuration Requirements

- nginx: `proxy-buffer-size: 128k` for Keycloak ingress (JWT tokens exceed default 4k buffer)
- Realm HTTP path: `/` — Keycloak 17+ no longer uses the `/auth` prefix
- CNPG initdb secret keys: exactly `username` and `password`
- ESO label required on OIDC secrets for ArgoCD to read them: `app.kubernetes.io/part-of: argocd`

---

## Alternatives Considered

**No centralised IdP (per-service credentials):** Rejected — creates credential sprawl and no unified revocation path.

**Cloud IdP (Google, Azure AD):** Rejected — requires cloud dependency and external authentication for an otherwise self-contained homelab.

---

## Related

- [Workload Onboarding Guide](../reference/workload-onboarding.md) — OIDC integration for new workloads
- [Data Layer Reference](../reference/data-layer.md) — Keycloak secret paths
- [ADR-012: Secret Management](ADR-012-secret-management.md)
