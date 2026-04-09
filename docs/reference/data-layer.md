# Data Layer Reference

## CNPG cluster definitions

All clusters in the `databases` namespace. WAL archiving to MinIO continuous (gzip). Credentials via ESO.

| Cluster | File | Instances | Storage | Backup destination | Schedule |
|---------|------|-----------|---------|-------------------|----------|
| keycloak-db | clusters/keycloak-cluster.yaml | 1 | 5Gi Longhorn | s3://cnpg-backups/keycloak | 02:00 UTC |
| nextcloud-db | clusters/nextcloud-cluster.yaml | 1 | 3Gi Longhorn | none (staging) | — |
| nextcloud-prod-db | clusters/nextcloud-prod-cluster.yaml | 2 (primary + standby, anti-affinity) | 8Gi Longhorn | s3://cnpg-backups/nextcloud-production | 03:30 UTC |

---

## External Secrets inventory

**ClusterSecretStore:** `vault-backend` — Vault KV v2, Kubernetes auth.

| Secret name | Namespace | Vault path | Purpose |
|------------|-----------|-----------|---------|
| argocd-oidc-secret | argocd | secret/data/argocd/oidc | Keycloak OIDC for ArgoCD |
| grafana-oidc-secret | monitoring | secret/data/grafana/oidc | Keycloak OIDC for Grafana |
| keycloak-secrets | keycloak | secret/data/keycloak/admin + secret/data/databases/keycloak | Admin + DB creds |
| keycloak-initdb-secret | databases | secret/data/databases/keycloak | CNPG initdb (username, password) |
| nextcloud-initdb-secret | databases | secret/data/databases/nextcloud | CNPG initdb (username, password) |
| cnpg-minio-secret | databases | secret/data/minio/cnpg | WAL archiving (access-key, secret-key) |
| loki-minio-credentials | monitoring | secret/data/minio/loki | Loki S3 (accessKey, secretKey) |
| velero-minio-credentials | velero | secret/data/minio/velero | Velero S3 (access_key, secret_key) |
| rclone-config | velero | secret/data/minio/rclone + secret/data/operators/rclone-onedrive | rclone.conf |
| nextcloud-staging-secret | nextcloud-staging | secret/data/nextcloud/admin + secret/data/databases/nextcloud | App admin + DB creds |
| nextcloud-production-secret | nextcloud-production | secret/data/nextcloud/admin + secret/data/databases/nextcloud | App admin + DB creds |

---

## Backup strategy

| Backup | Tool | Schedule | TTL | Storage |
|--------|------|----------|-----|---------|
| Kubernetes resources (prod) | Velero | 02:00 UTC nightly | 30 days | MinIO `velero` |
| Nextcloud user files | Velero | Every 6 hours | 7 days | MinIO `velero` |
| keycloak-db WAL + base | CNPG Barman | Continuous + 02:00 UTC | 7 days | MinIO `cnpg-backups/keycloak` |
| nextcloud-prod-db WAL + base | CNPG Barman | Continuous + 03:30 UTC | 7 days | MinIO `cnpg-backups/nextcloud-production` |
| Offsite sync | rclone CronJob | 04:00 UTC daily | — | OneDrive `homelab-backups/` |

rclone syncs both `velero` and `cnpg-backups` MinIO buckets to OneDrive. Runs in `velero` namespace.

---

## Storage classes

| Use case | StorageClass | Notes |
|----------|-------------|-------|
| All databases (CNPG) | longhorn | RF=2 |
| Nextcloud user files | longhorn | RF=2 |
| Redis cache | longhorn | RF=2 |
| Prometheus | local-path | 50Gi |
| Grafana | local-path | 1Gi |
| Loki WAL | local-path | 5Gi |
| MinIO | local-path | 20Gi |
| ARC runner work volumes | local-path | Longhorn causes chown failures |

**Longhorn:** RF=2, ~80GB effective (160GB raw). Workers only — control plane excluded. PVCs expand online.
