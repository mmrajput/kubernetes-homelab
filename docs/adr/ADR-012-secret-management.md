# ADR-012: Secret Management Strategy

## Status
Accepted

## Context
The homelab requires a secret management solution for storing and distributing sensitive credentials (database passwords, API keys, TLS certificates) to platform services. Secrets must not be stored in Git in plaintext. The solution must integrate with the existing GitOps workflow and Kubernetes-native tooling.

## Decision
Deploy HashiCorp Vault as the secrets backend with External Secrets Operator (ESO) as the Kubernetes-native synchronisation layer.

- Vault runs in standalone mode on a Longhorn-backed PVC
- Vault agent injector is disabled — ESO is the sole secret delivery mechanism
- KV v2 secrets engine enabled at `secret/` path
- Kubernetes auth method used for ESO authentication — no static tokens
- ESO ClusterSecretStore provides a single cluster-wide integration point
- Applications consume standard Kubernetes Secrets — no direct Vault dependency at the application layer

## Alternatives Considered

**Sealed Secrets:** Encrypts secrets for Git storage but requires managing encryption keys and provides no centralised audit trail or secret rotation capability.

**Vault agent injector:** Injects secrets as files into pod sidecars. Adds complexity and couples application pods to Vault availability. ESO provides the same outcome via standard Kubernetes Secrets with less operational overhead.

**External Secrets Operator with AWS Secrets Manager:** Not applicable — data sovereignty requirements mandate on-premises secret storage. Cloud-based backends are incompatible with the sovereign infrastructure positioning of this homelab.

## Consequences

**Positive:**
- Secrets never stored in Git
- Centralised audit trail via Vault audit log
- Secret rotation without redeployment — ESO refreshInterval handles re-sync
- Applications have no direct Vault dependency
- Kubernetes auth eliminates static credential management for ESO

**Negative:**
- Vault is a critical dependency — if Vault is sealed or unavailable, ESO cannot sync new or rotated secrets
- Standalone mode has no HA — acceptable for homelab, not for production
- Vault unseal keys must be protected outside the cluster

## References
- [HashiCorp Vault Helm Chart](https://github.com/hashicorp/vault-helm)
- [External Secrets Operator](https://external-secrets.io)
- BSI IT-Grundschutz APP.4.4: Kubernetes secret handling requirements