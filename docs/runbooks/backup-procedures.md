# Backup Procedures Runbook

**Cluster:** mmrajputhomelab.org
**Last Updated:** April 2026

---

## Backup Strategy Overview

Three complementary tools provide a 3-2-1 backup posture:

| Layer | Tool | What it protects | Storage |
|-------|------|-----------------|---------|
| PostgreSQL data | CNPG Barman (WAL archiving) | All CNPG-managed databases | MinIO `cnpg-backups` |
| Kubernetes objects + PVCs | Velero (Kopia uploader) | Namespaced resources and volumes | MinIO `velero` |
| Off-cluster copy | rclone CronJob | Both MinIO buckets | OneDrive `homelab-backups/` |

CNPG PVCs are excluded from Velero (`backup.velero.io/backup-volumes-excludes: pgdata`) — Barman is the authoritative backup path for all PostgreSQL data.

### Backup Schedule

| Backup | Tool | Schedule (UTC) | Retention | Destination |
|--------|------|---------------|-----------|-------------|
| keycloak-db WAL | CNPG Barman | Continuous | 7 days | MinIO `cnpg-backups/keycloak` |
| keycloak-db base backup | CNPG Barman | Daily 02:00 | 7 days | MinIO `cnpg-backups/keycloak` |
| nextcloud-prod-db WAL | CNPG Barman | Continuous | 7 days | MinIO `cnpg-backups/nextcloud-production` |
| nextcloud-prod-db base backup | CNPG Barman | Daily 03:30 | 7 days | MinIO `cnpg-backups/nextcloud-production` |
| Kubernetes resources (prod) | Velero `nightly-full` | Daily 02:00 | 30 days | MinIO `velero` |
| Nextcloud user files | Velero `nextcloud-files` | Every 6 hours | 7 days | MinIO `velero` |
| Offsite sync (all buckets) | rclone CronJob | Daily 04:00 | — | OneDrive `homelab-backups/` |

The rclone job runs after Velero and Barman complete, ensuring the OneDrive copy captures the night's backups.

---

## Velero Operations

### Verify Backup Storage Location

```bash
kubectl get backupstoragelocation -n velero
# Phase must be: Available
```

### List Backups

```bash
velero backup get
# Shows all backups with STATUS, CREATED, EXPIRES, STORAGE LOCATION
```

### Check a Specific Backup

```bash
velero backup describe <backup-name>
velero backup logs <backup-name>
```

### Run a Manual On-Demand Backup

```bash
velero backup create manual-$(date +%Y%m%d) \
  --include-namespaces nextcloud-production,databases \
  --wait
```

### Verify Schedule is Active

```bash
velero schedule get
# Both nightly-full and nextcloud-files should show a recent LAST BACKUP timestamp
```

### Check Backup Storage Usage (MinIO Console)

Navigate to `minio-console.mmrajputhomelab.org` → `velero` bucket → inspect size and object count.

---

## CNPG Barman Operations

### Check WAL Archiving is Running

```bash
# For nextcloud-prod-db
kubectl get cluster nextcloud-prod-db -n databases -o jsonpath='{.status.lastSuccessfulBackup}'

# For keycloak-db
kubectl get cluster keycloak-db -n databases -o jsonpath='{.status.lastSuccessfulBackup}'
```

### List Available Backups

```bash
kubectl get backup -n databases
# Shows all Barman base backups with status
```

### Verify WAL Continuity

```bash
# Check CNPG cluster status — continuousArchiving field shows WAL archiving health
kubectl describe cluster nextcloud-prod-db -n databases | grep -A5 "Continuous Archiving"
```

### Check CNPG Barman Logs

```bash
kubectl logs -n databases -l cnpg.io/cluster=nextcloud-prod-db -c postgres --tail=50 | grep -i backup
```

---

## rclone Offsite Sync Operations

### Check Last Sync Run

```bash
kubectl get cronjob rclone-onedrive-sync -n velero
# Check LAST SCHEDULE and ACTIVE columns

kubectl get jobs -n velero -l app=rclone-onedrive-sync --sort-by=.metadata.creationTimestamp
```

### Check Sync Logs

```bash
# Get the most recent job pod
kubectl logs -n velero -l job-name=<rclone-job-name>
# Look for: "Transferred" lines and "Errors: 0"
```

### Run a Manual Sync

```bash
kubectl create job rclone-manual-$(date +%Y%m%d) \
  --from=cronjob/rclone-onedrive-sync -n velero
kubectl logs -n velero -l job-name=rclone-manual-$(date +%Y%m%d) -f
```

### Verify OneDrive Contents

Access OneDrive via the Microsoft account linked to the rclone config. Navigate to `homelab-backups/` — you should see:
```
homelab-backups/
├── velero/
└── cnpg-backups/
    ├── keycloak/
    └── nextcloud-production/
```

---

## Backup Health Checks (Run Weekly)

```bash
# 1. Velero storage location is available
kubectl get backupstoragelocation -n velero
# Phase: Available

# 2. Velero schedules ran successfully
velero schedule get
# LAST BACKUP: within expected interval

# 3. CNPG clusters have recent base backups
kubectl get backup -n databases

# 4. rclone job last ran successfully
kubectl get jobs -n velero -l app=rclone-onedrive-sync --sort-by=.metadata.creationTimestamp | tail -3

# 5. No Velero backups in Failed state
velero backup get | grep Failed
# Expected: no output
```

---

## Troubleshooting

### Velero backup stuck in "InProgress"

```bash
velero backup describe <backup-name>
# Check "Warnings" and "Errors" sections

kubectl logs -n velero deployment/velero --tail=100 | grep -i error
```

### BackupStorageLocation not Available

```bash
kubectl describe backupstoragelocation default -n velero
# Common causes:
# - MinIO pod not running: kubectl get pods -n minio
# - velero-minio-credentials not synced: kubectl get externalsecret velero-minio-credentials -n velero
# - MinIO bucket "velero" deleted: recreate it in MinIO Console
```

### CNPG WAL archiving failing

```bash
kubectl describe cluster nextcloud-prod-db -n databases
# Look for WAL archiving status and error messages

# Check MinIO credentials
kubectl get externalsecret cnpg-minio-secret -n databases
# STATUS must be SecretSynced

# Check CNPG pod logs
kubectl logs -n databases -l cnpg.io/cluster=nextcloud-prod-db --all-containers --tail=50
```

### rclone sync failing (OneDrive auth)

rclone uses an OAuth token stored in the `rclone-config` secret. Tokens expire — re-authenticate:

```bash
# Check the secret
kubectl get secret rclone-config -n velero

# If token has expired, re-run rclone config manually on a machine with a browser,
# update the secret in Vault at secret/operators/rclone-onedrive,
# and let ESO sync the updated token:
kubectl annotate externalsecret rclone-config -n velero \
  force-sync=$(date +%s) --overwrite
```

---

## Related Documentation

- [Disaster Recovery Runbook](disaster-recovery.md) — restore procedures
- [Data Layer Reference](../reference/data-layer.md) — backup schedules and storage details
- [ADR-014: Backup Strategy](../adr/ADR-014-backup-strategy.md)
