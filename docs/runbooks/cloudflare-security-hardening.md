# Cloudflare Security Hardening Runbook

**Cluster:** mmrajputhomelab.org  
**Date:** 2026-03-22  
**Status:** Active  
**Related ADR:** ADR-007-networkpolicy-and-pss.md

---

## Context

On the night of 2026-03-21, an automated scanning/attack event was detected against `mmrajputhomelab.org` via Cloudflare Analytics. The attack was identified through a sharp spike in traffic volume and error rates, prompting a review and hardening of Cloudflare edge security rules.

This runbook documents the observed attack indicators, the mitigations applied, the known limitations of the free tier, and the escalation procedure for future incidents.

---

## Observed Attack Indicators

The following metrics were captured in Cloudflare Analytics during the incident:

| Metric | Value | Change |
|---|---|---|
| Encrypted requests | 31.83k | ↑ 1.1k% |
| 4xx errors | 10.99k | ↑ 6.81k% |
| 4xx error rate | 34.53% | ↑ 474.4% |
| 5xx errors | 197 | ↑ 258.18% |
| Cached requests rate | 0.17% | ↓ 80.49% |

**Interpretation:**

- The 1.1k% spike in encrypted requests indicates a sudden volumetric surge, consistent with automated scanning or a bot-driven probe
- A 34.53% 4xx error rate at that volume means the majority of requests were probing paths that do not exist — classic behaviour of vulnerability scanners (wp-admin, .env, phpmyadmin, etc.)
- The near-zero cache rate (0.17%) confirms that almost all requests bypassed cache and hit the origin — amplifying backend load
- The 5xx spike indicates some requests reached the cluster and triggered upstream errors before mitigations were in place

**Positive indicators:**

- 100% encrypted bandwidth (TLSv1.3) — no plain HTTP traffic reached origin
- HTTP/3 handled 29.92k of 31.83k requests — expected for Cloudflare edge behaviour

---

## Mitigations Applied

### 1. Bot Fight Mode

**Location:** Security → Bots → Bot Fight Mode  
**Status:** Enabled

Blocks known malicious bots and automated scanners at the Cloudflare edge before they reach the origin. No configuration required. This is the most effective free-tier control for volumetric bot traffic.

---

### 2. Rate Limiting Rule

**Location:** Security → WAF → Rate Limiting Rules  
**Rule name:** Block aggressive request rate per IP  
**Status:** Active (1/1 used on free tier)

| Field | Value |
|---|---|
| Match | Hostname equals `mmrajputhomelab.org` |
| Characteristic | IP |
| Requests | 20 |
| Period | 10 seconds |
| Action | Block |
| Block duration | 10 seconds |

**Rationale:** Equivalent to approximately 120 requests per minute per IP. No legitimate user browsing homelab services (ArgoCD, Grafana, Keycloak, Nextcloud) will approach this threshold under normal operation. Automated scanners will trigger it within seconds.

**Known limitation:** The free tier caps block duration at 10 seconds. A persistent scanner can resume after the window expires. This rule functions as a speed bump, not a hard block. Primary defence is Bot Fight Mode and the custom WAF rule below.

---

### 3. Custom WAF Rule — Scanner Path Block

**Location:** Security → WAF → Custom Rules  
**Rule name:** Block common scanner paths  
**Status:** Active (1/5 used on free tier)

**Expression:**

```
(http.request.uri.path contains "/wp-admin") or
(http.request.uri.path contains "/.env") or
(http.request.uri.path contains "/phpmyadmin") or
(http.request.uri.path contains "/xmlrpc.php") or
(http.request.uri.path contains "/.git") or
(http.request.uri.path contains "/config.php") or
(http.request.uri.path contains "/admin") or
(http.request.uri.path contains "/.aws")
```

**Action:** Block (permanent, no timeout)

**Rationale:** This cluster runs Kubernetes services, not WordPress or PHP applications. Any request targeting these paths is unambiguously a scanner or bot. A permanent block is the correct response. Unlike the rate limiting rule, this block has no expiry — matching requests are dropped at the edge indefinitely.

---

## Current Security Posture Summary

| Layer | Control | Status |
|---|---|---|
| Bot traffic | Bot Fight Mode | ✅ Active |
| Scanner paths | Custom WAF rule (1/5 used) | ✅ Active |
| Rate limiting | 20 req / 10s per IP | ✅ Active (1/1 used) |
| Encryption | TLSv1.3, 100% HTTPS | ✅ Enforced by Cloudflare |
| Managed rules | Cloudflare Managed Ruleset | ❌ Pro plan required |

---

## Known Limitations (Free Tier)

| Limitation | Impact | Mitigation |
|---|---|---|
| Rate limit block duration capped at 10 seconds | Persistent scanners resume after timeout | Bot Fight Mode handles known bots independently |
| Rate limiting period minimum 10 seconds (no 1-minute window) | Threshold tuning is coarser | 20 req/10s is still effective against automated tools |
| Managed Rules require Pro plan ($20/month) | No pattern-based WAF rules (SQLi, XSS, path traversal) | Custom WAF rules cover the most common scanner paths manually |
| 1 rate limiting rule on free tier | Cannot create per-service rate limit rules | Single global hostname rule covers all services |

---

## Recommended Future Rules (Remaining Custom Rule Slots: 4/5)

As additional services are deployed, use remaining custom rule slots for:

| Priority | Rule | Trigger |
|---|---|---|
| High | Keycloak brute-force path block | When Keycloak is live — block `/auth/realms/*/protocol/openid-connect/token` at high rate |
| High | IP allowlist for home IP | Prevent own IP from being caught by rate limiting rule |
| Medium | Nextcloud scanner paths | When Nextcloud is live — block `/ocs/`, `/remote.php/` scanner probes |
| Low | Country-based challenge | If attack traffic concentrates from unexpected regions |

---

## Escalation: Under Attack Mode

If a future attack overwhelms the active rules (sustained high 5xx rate, origin becoming unreachable), enable Under Attack Mode:

**Location:** Cloudflare Dashboard → Overview → Quick Actions → Under Attack Mode

This forces a JavaScript challenge on every visitor before any request reaches the origin. It will also challenge legitimate users, so it should only be active during an ongoing attack and disabled once traffic normalises.

**Disable after:** traffic returns to baseline in the Analytics dashboard (typically within 1–4 hours of attack cessation).

---

## Alerting

To avoid discovering attacks after the fact via the Analytics dashboard, configure Cloudflare Notifications:

**Location:** Notifications → Add Notification

Recommended alerts:
- **Security Events Alert** — triggers on WAF rule spike
- **DDoS Attack Alert** — triggers on volumetric detection
- **Traffic Anomalies** — triggers on unusual request volume

Deliver to email initially. Future enhancement: route webhook to n8n endpoint for automated incident response workflow (planned Phase 12).

---

## Enterprise Relevance

This configuration demonstrates defence-in-depth at the CDN layer, consistent with BSI IT-Grundschutz baseline protection requirements for internet-facing services (NET.1.1, APP.3.1). Key principles applied:

- Traffic filtering at the network perimeter before reaching application layer
- Separation of concerns: bot filtering, rate limiting, and path-based blocking as independent controls
- 100% TLS enforcement with TLSv1.3 — no plaintext traffic reaches origin
- All traffic proxied through Cloudflare Tunnel (cloudflared) — origin IP is never exposed

For sovereign infrastructure deployments (Dataport, IONOS, BWI GmbH), equivalent controls would be implemented via on-premises WAF (e.g., ModSecurity with OWASP CRS), ingress-nginx rate limiting annotations, and NetworkPolicy at the Kubernetes layer — all of which are active in this cluster independent of Cloudflare.

---

## References

- [Cloudflare WAF Custom Rules documentation](https://developers.cloudflare.com/waf/custom-rules/)
- [Cloudflare Rate Limiting documentation](https://developers.cloudflare.com/waf/rate-limiting-rules/)
- `docs/adr/ADR-007-networkpolicy-and-pss.md` — NetworkPolicy and Pod Security Standards
- `docs/runbooks/cluster-rebuild.md` — cluster recovery procedure
