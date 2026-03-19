# External Secrets Operator

External Secrets Operator (ESO) synchronises secrets from Vault into Kubernetes Secret objects.

## Overview

| Property | Value |
|----------|-------|
| Chart | external-secrets/external-secrets |
| Version | 2.1.0 |
| Namespace | `external-secrets` |
| PSS | restricted |
| Vault backend | `vault.vault.svc.cluster.local:8200` |
| Auth method | Kubernetes |

## Architecture

ESO watches ExternalSecret resources and reconciles them against the Vault backend via the ClusterSecretStore. Applications consume standard Kubernetes Secrets — they have no direct dependency on Vault or ESO.
```
Vault (source of truth)
    ↓
ClusterSecretStore (vault-backend)
    ↓
ExternalSecret (per service)
    ↓
Kubernetes Secret (consumed by application)
```

## ClusterSecretStore

A single `ClusterSecretStore` named `vault-backend` provides cluster-wide access to the Vault KV v2 engine at `secret/`. All ExternalSecret resources reference this store.

ESO authenticates to Vault using the `external-secrets` ServiceAccount token via the Kubernetes auth method. No static tokens are used.

## Usage

To sync a secret from Vault, create an ExternalSecret in the target namespace:
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-secret
  namespace: my-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: platform/my-service/credentials
        property: password
```

The corresponding secret must exist in Vault at `secret/platform/my-service/credentials` before the ExternalSecret is applied.

## Checking Sync Status
```bash
# Check all ExternalSecrets in a namespace
kubectl get externalsecret -n <namespace>

# Describe for detailed sync status and errors
kubectl describe externalsecret <name> -n <namespace>

# Verify the resulting Kubernetes Secret
kubectl get secret <name> -n <namespace>
```

## Operational Notes

**ClusterSecretStore not ready:** Check Vault is unsealed and the `external-secrets` ServiceAccount exists in the `external-secrets` namespace.
```bash
kubectl get clustersecretstore vault-backend
kubectl describe clustersecretstore vault-backend
```

**ExternalSecret stuck in error state:** Check the Vault path exists and the `external-secrets` policy grants read access to it.
```bash
kubectl describe externalsecret <name> -n <namespace>
```