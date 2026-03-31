# Vault

HashiCorp Vault deployed as the centralised secrets backend for the homelab cluster.

## Overview

| Property | Value |
|----------|-------|
| Chart | hashicorp/vault |
| Version | 0.32.0 (Vault 1.21.2) |
| Namespace | `vault` |
| PSS | restricted |
| Mode | Standalone |
| Storage | Longhorn PVC (5Gi) |
| UI | vault.mmrajputhomelab.org |

## Architecture

Vault runs in standalone mode backed by a Longhorn persistent volume. The Vault agent injector is disabled — External Secrets Operator is the sole secret delivery mechanism. Applications consume standard Kubernetes Secrets and have no direct dependency on Vault.

## Secrets Engine

| Engine | Path | Version |
|--------|------|---------|
| KV | `secret/` | v2 |

Secret paths follow this convention:
```
secret/platform/<service>/<secret-name>   # Platform services
secret/apps/<app>/<secret-name>           # Application secrets
```

## Authentication

Kubernetes auth method is enabled. ESO authenticates to Vault using its ServiceAccount token — no static tokens or credentials are used.

| Property | Value |
|----------|-------|
| Auth method | kubernetes |
| Mount path | `kubernetes/` |
| ESO role | `external-secrets` |
| Bound ServiceAccount | `external-secrets` in `external-secrets` namespace |
| Token TTL | 1h |

## Initialisation

Vault was initialised with Shamir secret sharing:

- Key shares: 3
- Threshold: 2

Unseal keys and root token are stored in `vault-init.json` locally — this file is in `.gitignore` and was never committed to Git.

## Policies

| Policy | Access |
|--------|--------|
| `external-secrets` | `read` on `secret/data/*`, `read/list` on `secret/metadata/*` |

## Operational Notes

**Unsealing after restart:** Vault does not auto-unseal. If the pod restarts, Vault will start in a sealed state and must be manually unsealed:
```bash
kubectl exec -it -n vault vault-0 -- vault operator unseal
# Run twice with two different unseal keys
```

**Adding a new secret:**
```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
vault login
vault kv put secret/platform/<service>/<name> key="value"
```

**Checking secret versions:**
```bash
vault kv metadata get secret/platform/<service>/<name>
```