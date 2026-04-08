# External Secrets Operator

External Secrets Operator (ESO) synchronises secrets from Vault into Kubernetes Secret objects.

## Overview

| Property | Value |
|----------|-------|
| Chart | external-secrets/external-secrets 2.1.0 |
| Namespace | `external-secrets` |
| PSS | restricted |
| API version | `external-secrets.io/v1` |
| Vault backend | `http://vault.vault.svc.cluster.local:8200` |
| Auth method | Kubernetes (ServiceAccount token) |

## Architecture

```
Vault KV v2 (source of truth)
    ↓
ClusterSecretStore: vault-backend  (cluster-wide, Kubernetes auth)
    ↓
ExternalSecret resources (one per service, in target namespace)
    ↓
Kubernetes Secrets (consumed by application pods)
```

Applications consume standard Kubernetes Secrets — they have no direct dependency on Vault or ESO.

## ClusterSecretStore

A single `ClusterSecretStore` named `vault-backend` provides cluster-wide access to the Vault KV v2 engine mounted at `secret/`. All ExternalSecret resources reference this store.

ESO authenticates to Vault using the `external-secrets` ServiceAccount token via the Kubernetes auth method. No static tokens or long-lived credentials are used.

## Writing an ExternalSecret

```yaml
apiVersion: external-secrets.io/v1      # NOT v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secret
  namespace: my-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-app-secret
    creationPolicy: Owner
  data:
    - secretKey: password               # key in the resulting Kubernetes Secret
      remoteRef:
        key: secret/data/databases/myapp   # KV v2: always include data/ segment
        property: password              # field inside the Vault secret
```

**Key convention:** `remoteRef.key` uses the API path (`secret/data/<category>/<name>`), not the logical CLI path (`secret/<category>/<name>`). The `data/` segment is required for KV v2.

### Path examples

| Vault CLI path | ESO remoteRef.key |
|---------------|-------------------|
| `secret/argocd/oidc` | `secret/data/argocd/oidc` |
| `secret/databases/nextcloud` | `secret/data/databases/nextcloud` |
| `secret/minio/loki` | `secret/data/minio/loki` |
| `secret/nextcloud/admin` | `secret/data/nextcloud/admin` |

## Checking Sync Status

```bash
# List all ExternalSecrets in a namespace
kubectl get externalsecret -n <namespace>
# STATUS column must show SecretSynced

# Describe for detailed sync events and errors
kubectl describe externalsecret <name> -n <namespace>
```

> Do not run `kubectl get secret <name>` to verify secret contents. Check the ExternalSecret STATUS instead.

## Operational Notes

**ClusterSecretStore not ready:**
```bash
kubectl get clustersecretstore vault-backend
kubectl describe clustersecretstore vault-backend
# Common cause: Vault is sealed. Unseal it first.
```

**ExternalSecret in error state:**
```bash
kubectl describe externalsecret <name> -n <namespace>
# Common causes:
# - Vault path does not exist (create the secret in Vault first)
# - remoteRef.key missing the data/ segment
# - API version is v1beta1 instead of v1
# - external-secrets policy in Vault does not cover the path
```

**Forcing a re-sync:**
```bash
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync=$(date +%s) --overwrite
```

## ArgoCD label requirement

ESO secrets used by ArgoCD itself must carry this label so ArgoCD can read them:
```yaml
labels:
  app.kubernetes.io/part-of: argocd
```

## Related Documentation

- [Vault README](../vault/README.md)
- [ADR-012: Secret Management Strategy](../../docs/adr/ADR-012-secret-management.md)
- [Data Layer Reference](../../docs/reference/data-layer.md) — full ExternalSecret inventory
