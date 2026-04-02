# Disaster Recovery Runbook

**Last Updated:** April 2026
**Cluster:** mmrajputhomelab.org
**Hardware:** Beelink SER5 Pro — Proxmox VE
**Kubernetes:** v1.31.4 (kubeadm), Calico CNI

---

## Backup strategy overview

Two complementary tools cover all data planes:

| Data | Tool | Storage | Recovery type |
|---|---|---|---|
| PostgreSQL (CNPG) | Barman (WAL archiving) | MinIO `cnpg-backups` | PITR — any point after first base backup |
| Nextcloud user files PVC | Velero (kopia file-system) | MinIO `velero` | File-system restore |
| Kubernetes objects | Velero | MinIO `velero` | Namespace restore |
| Redis | None — cache only | N/A | Ephemeral, no restore needed |

CNPG PVCs are excluded from Velero (`backup.velero.io/backup-volumes-excludes: pgdata`) — Barman is the authoritative backup path for all PostgreSQL data.

### Off-cluster copy — OneDrive

A nightly rclone CronJob (4:00 AM, after Velero and Barman complete) syncs both MinIO buckets to OneDrive:

```
MinIO (in-cluster) → rclone CronJob → OneDrive: homelab-backups/
                                         ├── velero/
                                         └── cnpg-backups/
```

This provides a true off-cluster DR copy. If the cluster and its storage are destroyed, backups are recoverable from OneDrive by restoring the MinIO data directory and pointing Velero/Barman at the restored MinIO instance.

> **Constraint:** rclone syncs files, not S3 objects. Restore from OneDrive requires copying data back to a MinIO instance first, then using Velero/Barman normally. This is not instant — factor in transfer time for large restores.

---

## Velero backup schedules

| Schedule | Namespaces | Frequency | Retention |
|---|---|---|---|
| `nightly-full` | nextcloud-production, databases, argocd, ingress-nginx, cert-manager, external-secrets, vault, keycloak | Daily 2:00 AM | 30 days |
| `nextcloud-files` | nextcloud-production (Nextcloud pods only) | Every 6 hours | 7 days |

---

## Scenario 1 — Partial restore (namespace or object recovery)

Use this when the cluster is healthy but a namespace or specific objects need to be recovered.

### List available backups

```bash
velero backup get
```

### Restore a specific namespace

```bash
velero restore create --from-backup <backup-name> \
  --include-namespaces nextcloud-production
```

### Restore a single resource

```bash
velero restore create --from-backup <backup-name> \
  --include-resources persistentvolumeclaims \
  --include-namespaces nextcloud-production
```

### Monitor restore progress

```bash
velero restore describe <restore-name>
velero restore logs <restore-name>
```

---

## Scenario 2 — CNPG Point-in-Time Recovery (PITR)

Use this when the PostgreSQL database needs to be restored to a specific point in time (e.g. data corruption, accidental deletion).

PITR is available for any point after the first base backup ran (daily at 3:30 AM).

### Step 1 — Identify the target time

Determine the exact timestamp you want to recover to (UTC):
```
2026-04-01 14:30:00
```

### Step 2 — Scale down Nextcloud

Prevent writes to the database during recovery:
```bash
kubectl scale deployment nextcloud-production -n nextcloud-production --replicas=0
```

### Step 3 — Create a recovery cluster

Create a new CNPG cluster manifest pointing at the MinIO backup and the target time. **Do not commit this to Git** — it is a temporary recovery manifest applied directly.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: nextcloud-prod-db-recovery
  namespace: databases
spec:
  instances: 1

  bootstrap:
    recovery:
      source: nextcloud-prod-db
      recoveryTarget:
        targetTime: "2026-04-01 14:30:00"

  externalClusters:
    - name: nextcloud-prod-db
      barmanObjectStore:
        destinationPath: s3://cnpg-backups/nextcloud-production
        endpointURL: http://minio.minio.svc.cluster.local:9000
        s3Credentials:
          accessKeyId:
            name: cnpg-minio-secret
            key: access-key
          secretAccessKey:
            name: cnpg-minio-secret
            key: secret-key

  storage:
    storageClass: longhorn
    size: 8Gi
```

```bash
kubectl apply -f recovery-cluster.yaml
```

### Step 4 — Monitor recovery

```bash
kubectl get cluster nextcloud-prod-db-recovery -n databases -w
kubectl logs -n databases -l cnpg.io/cluster=nextcloud-prod-db-recovery -f
```

Wait until `STATUS: Cluster in healthy state`.

### Step 5 — Verify data

```bash
kubectl exec -it nextcloud-prod-db-recovery-1 -n databases -- psql -U nextcloud -c "\dt"
```

### Step 6 — Promote the recovery cluster

Once data is verified, update the Nextcloud production values to point to the new cluster service (`nextcloud-prod-db-recovery-rw`) and scale Nextcloud back up. After confirming everything works, delete the old primary cluster and rename/promote the recovery cluster.

> **Note:** Renaming a CNPG cluster requires deleting and recreating it. Plan a short maintenance window.

### Step 7 — Clean up

```bash
kubectl delete -f recovery-cluster.yaml
rm recovery-cluster.yaml
```

---

## Scenario 3 — Full DR (cluster destroyed)

Use this when the entire cluster is lost. Estimated recovery time: 2–4 hours.

### Prerequisites

- Proxmox VE accessible
- MinIO data intact (runs on the cluster — see note below)
- GitHub repository accessible
- Vault backup or ability to re-enter secrets

> **MinIO note:** MinIO runs inside the cluster. If the cluster is destroyed but the Proxmox VMs still have their disks intact, MinIO PVC data (on Longhorn) survives on the worker node disks and can be recovered. If disks are also lost, off-site backup of MinIO data would be needed. This is a known homelab constraint.

### Step 1 — Rebuild the cluster

Follow the [Cluster Rebuild Runbook](cluster-rebuild.md) through Phase 2 (bootstrap complete, ArgoCD running).

### Step 2 — Restore platform namespaces via ArgoCD

ArgoCD will sync all platform components from Git automatically once it is running. Verify all apps are healthy:

```bash
kubectl get applications -n argocd
```

### Step 3 — Re-populate Vault secrets

Vault is not backed up by Velero (secrets must never be in object storage). Re-enter all secrets manually following the Vault path conventions in CLAUDE.md. Required paths:

```
secret/databases/nextcloud
secret/nextcloud/admin
secret/nextcloud/config
secret/minio/cnpg
secret/minio/loki
secret/minio/velero
secret/operators/argocd
secret/operators/grafana
secret/operators/keycloak
```

### Step 4 — Restore Kubernetes objects from Velero

Once Velero is running and the BackupStorageLocation is available:

```bash
# Verify BSL is reachable
kubectl get backupstoragelocation -n velero

# List available backups
velero backup get

# Restore all critical namespaces
velero restore create dr-restore \
  --from-backup <latest-nightly-full-backup>
```

Monitor:
```bash
velero restore describe dr-restore
```

### Step 5 — Verify CNPG database recovery

CNPG will automatically replay WAL from MinIO on startup if the `backup` block is present in the cluster spec (it is). Monitor:

```bash
kubectl get cluster nextcloud-prod-db -n databases -w
```

Expected: `STATUS: Cluster in healthy state` with 2 ready instances.

### Step 6 — Verify Nextcloud

```bash
# Check pods are running
kubectl get pods -n nextcloud-production

# Check application responds
curl -I https://nextcloud.mmrajputhomelab.org
```

### Step 7 — Verify Velero schedules are active

```bash
velero schedule get
```

Both `nightly-full` and `nextcloud-files` should show `LAST BACKUP` with a recent timestamp after the next scheduled run.

---

## Verification checklist (run after any restore)

- [ ] `kubectl get nodes` — all 3 nodes Ready
- [ ] `kubectl get applications -n argocd` — all apps Synced/Healthy
- [ ] `kubectl get cluster -n databases` — CNPG clusters healthy, 2 replicas
- [ ] `kubectl get backupstoragelocation -n velero` — Phase: Available
- [ ] `velero backup get` — backups visible
- [ ] Nextcloud responds at `https://nextcloud.mmrajputhomelab.org`
- [ ] Test login with a known user account
- [ ] Verify user files are present

---

## Key locations

| Resource | Location |
|---|---|
| Velero backups | MinIO `velero` bucket |
| CNPG WAL + base backups | MinIO `cnpg-backups/nextcloud-production` |
| Cluster rebuild procedure | `docs/runbooks/cluster-rebuild.md` |
| Backup procedures | `docs/runbooks/backup-procedures.md` |
| Vault secret paths | `CLAUDE.md` — Secret management workflow |
