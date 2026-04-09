# Vault Operations Runbook

**Cluster:** mmrajputhomelab.org
**Last Updated:** April 2026

---

## Overview

Vault runs in standalone mode in the `vault` namespace, backed by a 5Gi Longhorn PVC. It does **not** auto-unseal — after any pod restart, Vault must be manually unsealed before ESO can sync secrets.

Unseal keys and root token are in `vault-init.json` on your local machine. This file was generated at initialisation and is never committed to Git.

---

## Checking Vault Status

```bash
kubectl exec -n vault vault-0 -- vault status
```

Key fields:
- `Sealed: false` — normal operating state
- `Sealed: true` — requires unsealing before ESO will work

---

## Unsealing After Pod Restart

Vault restarts sealed. This happens after pod eviction, node restart, or Longhorn volume remount.

```bash
# Run twice with two different unseal keys from vault-init.json
kubectl exec -it -n vault vault-0 -- vault operator unseal <unseal-key-1>
kubectl exec -it -n vault vault-0 -- vault operator unseal <unseal-key-2>

# Verify
kubectl exec -n vault vault-0 -- vault status
# Sealed: false
```

After unsealing, ESO will automatically re-connect to Vault and resume syncing ExternalSecrets. No further action needed.

---

## Logging In to Vault

```bash
# Get a shell inside the Vault pod
kubectl exec -it -n vault vault-0 -- /bin/sh

# Login with root token (from vault-init.json)
vault login <root-token>

# Or login interactively (prompts for token)
vault login
```

> Use the root token only for administrative operations. For day-to-day reads, use a scoped token.

---

## Adding a New Secret

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
vault login <root-token>

# Single-value secret
vault kv put secret/<category>/<name> key="value"

# Multi-value secret
vault kv put secret/databases/myapp username="myuser" password="mypass"
```

Then create an ExternalSecret in the target namespace to sync it to a Kubernetes Secret. See [`platform/security/external-secrets/README.md`](../../platform/security/external-secrets/README.md).

### Path conventions

| Category | Example path | Usage |
|----------|-------------|-------|
| Databases | `secret/databases/<app>` | CNPG initdb credentials |
| MinIO | `secret/minio/<consumer>` | S3 access keys per consumer |
| ArgoCD | `secret/argocd/oidc` | Keycloak OIDC client |
| Grafana | `secret/grafana/oidc` | Keycloak OIDC client |
| Keycloak | `secret/keycloak/admin` | Admin credentials |
| Applications | `secret/<app>/admin` | App-level credentials |
| Operators | `secret/operators/<name>` | Operator-specific tokens |

---

## Rotating a Secret

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
vault login <root-token>

# Write the new value — KV v2 automatically versions it
vault kv put secret/<category>/<name> key="new-value"

# Verify new version
vault kv metadata get secret/<category>/<name>
```

After updating the Vault secret, force ESO to re-sync the ExternalSecret:

```bash
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync=$(date +%s) --overwrite
```

Verify the Kubernetes Secret was updated:

```bash
kubectl get externalsecret <name> -n <namespace>
# STATUS must show SecretSynced with a fresh timestamp
```

---

## Reading a Secret

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
vault login <root-token>

vault kv get secret/<category>/<name>
```

> Only read secrets directly for administrative verification. Applications should never read from Vault directly — they consume Kubernetes Secrets synced by ESO.

---

## Listing Secrets

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
vault login <root-token>

# List all paths under secret/
vault kv list secret/

# List sub-paths
vault kv list secret/databases/
```

---

## Secret Version History

KV v2 retains 10 versions by default.

```bash
# View version metadata
vault kv metadata get secret/<category>/<name>

# Read a specific historical version
vault kv get -version=2 secret/<category>/<name>

# Roll back to a previous version
vault kv rollback -version=2 secret/<category>/<name>
```

---

## Checking the ESO Policy

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
vault login <root-token>

vault policy read external-secrets
# Expected output:
# path "secret/data/*" { capabilities = ["read"] }
# path "secret/metadata/*" { capabilities = ["read", "list"] }
```

If the policy is missing or wrong, re-create it:

```bash
vault policy write external-secrets - <<EOF
path "secret/data/*" { capabilities = ["read"] }
path "secret/metadata/*" { capabilities = ["read", "list"] }
EOF
```

---

## Checking Kubernetes Auth Configuration

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
vault login <root-token>

vault auth list
# Should show: kubernetes/

vault read auth/kubernetes/config
# kubernetes_host should be https://10.96.0.1:443

vault read auth/kubernetes/role/external-secrets
# bound_service_account_names: [external-secrets]
# bound_service_account_namespaces: [external-secrets]
# policies: [external-secrets]
```

---

## Full Secret Inventory

See [`docs/reference/data-layer.md`](../reference/data-layer.md) for the complete inventory of all Vault paths and their corresponding ExternalSecret resources.

---

## Troubleshooting

### Vault pod keeps restarting

```bash
kubectl describe pod vault-0 -n vault
kubectl logs vault-0 -n vault --previous
# Common cause: Longhorn PVC not mounted — check Longhorn volume health
kubectl get volume -n longhorn-system | grep vault
```

### ESO ClusterSecretStore not ready after unsealing

Give ESO 60 seconds to reconnect after unsealing. If it doesn't recover:

```bash
# Restart ESO to force reconnect
kubectl rollout restart deployment external-secrets -n external-secrets
```

### Token expired (Vault login rejected)

The root token does not expire. If you're using a non-root token that has expired, log in again with the root token or generate a new scoped token:

```bash
vault token create -policy=external-secrets -ttl=24h
```

---

## Related Documentation

- [Vault README](../../platform/security/vault/README.md)
- [External Secrets README](../../platform/security/external-secrets/README.md)
- [Data Layer Reference](../reference/data-layer.md)
- [ADR-012: Secret Management](../adr/ADR-012-secret-management.md)
