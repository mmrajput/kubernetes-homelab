# Vault

HashiCorp Vault deployed as the centralised secrets backend for the homelab cluster.

## Overview

| Property | Value |
|----------|-------|
| Chart | hashicorp/vault 0.32.0 |
| App version | Vault 1.21.2 |
| Namespace | `vault` |
| PSS | restricted |
| Mode | Standalone |
| Storage | Longhorn PVC (5Gi) |
| UI | vault.mmrajputhomelab.org |

## Architecture

Vault runs in standalone mode backed by a Longhorn persistent volume. The Vault agent injector is disabled — External Secrets Operator is the sole secret delivery mechanism. Applications consume standard Kubernetes Secrets and have no direct dependency on Vault.

```
Vault KV v2 (source of truth)
    ↓
ESO ClusterSecretStore (vault-backend, Kubernetes auth)
    ↓
ExternalSecret resources (one per service)
    ↓
Kubernetes Secrets (consumed by pods)
```

## Secrets Engine

| Engine | Mount path | Version |
|--------|-----------|---------|
| KV | `secret/` | v2 |

### Secret Path Conventions

Paths are organised by category:

```
secret/argocd/oidc                    # Keycloak OIDC client for ArgoCD
secret/grafana/oidc                   # Keycloak OIDC client for Grafana
secret/keycloak/admin                 # Keycloak admin credentials
secret/databases/keycloak             # keycloak-db CNPG initdb credentials
secret/databases/nextcloud            # nextcloud-db CNPG initdb credentials
secret/minio/cnpg                     # CNPG Barman WAL archiving credentials
secret/minio/loki                     # Loki S3 credentials
secret/minio/velero                   # Velero S3 credentials
secret/minio/rclone                   # rclone MinIO source credentials
secret/operators/rclone-onedrive      # rclone OneDrive destination credentials
secret/nextcloud/admin                # Nextcloud admin credentials
```

**CLI path:** `secret/<path>`
**ESO `remoteRef.key`:** `secret/data/<path>` (KV v2 requires the `data/` segment)

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

**Unsealing after restart:** Vault does not auto-unseal. If the pod restarts, Vault starts sealed and must be manually unsealed:

```bash
kubectl exec -it -n vault vault-0 -- vault operator unseal
# Run twice with two different unseal keys
```

Check seal status:
```bash
kubectl exec -n vault vault-0 -- vault status
```

**Adding a new secret:**
```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
vault login   # use root token or an admin token
vault kv put secret/databases/myapp username="myuser" password="mypass"
```

**Reading a secret (to verify it exists before creating an ExternalSecret):**
```bash
vault kv get secret/databases/myapp
```

**Checking secret versions:**
```bash
vault kv metadata get secret/databases/myapp
```

> **Security boundary:** Never run `vault kv get` or `kubectl get secret` to verify secrets in normal operations. Instead, verify the ExternalSecret status:
> ```bash
> kubectl get externalsecret <name> -n <namespace>
> # STATUS must be SecretSynced
> ```

## Related Documentation

- [External Secrets Operator README](../external-secrets/README.md)
- [ADR-012: Secret Management Strategy](../../docs/adr/ADR-012-secret-management.md)
- [Data Layer Reference](../../docs/reference/data-layer.md) — full secrets inventory
- [Vault Operations Runbook](../../docs/runbooks/vault-operations.md)
