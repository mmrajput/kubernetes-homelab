# ADR-014: Backup Strategy

**Status:** Accepted
**Date:** March 2026
**Phase:** Phase 8 — Storage & Backup

---

## Context

The platform runs stateful workloads (Nextcloud user files, PostgreSQL databases via CNPG) that require durable, recoverable backups. Two categories of data need different backup approaches:

1. **PostgreSQL data** — managed by CNPG; requires point-in-time recovery capability
2. **Kubernetes objects + PVCs** — application config and user file volumes

MinIO runs in-cluster as the primary backup storage target. An off-cluster copy is needed to survive a complete cluster loss.

---

## Decision

Use three complementary tools providing a **3-2-1 backup posture** (3 copies, 2 media, 1 offsite):

| Tool | What it protects | Storage target |
|------|-----------------|----------------|
| CNPG Barman (WAL archiving) | All PostgreSQL databases | MinIO `cnpg-backups` |
| Velero (Kopia uploader) | Kubernetes objects + non-DB PVCs | MinIO `velero` |
| rclone CronJob (nightly) | Both MinIO buckets | OneDrive `homelab-backups/` |

CNPG PVCs are excluded from Velero (`backup.velero.io/backup-volumes-excludes: pgdata`). Barman is the authoritative path for all PostgreSQL data — using both would create redundant, inconsistent copies.

---

## Rationale

### Why CNPG Barman for databases

CNPG Barman provides continuous WAL archiving — any point after the first base backup is recoverable. File-system snapshots (Velero/Longhorn) cannot provide PITR and may capture an inconsistent database state mid-transaction.

### Why Velero for Kubernetes objects and PVCs

Velero is the Kubernetes-native backup standard. It captures Kubernetes object state (Deployments, ConfigMaps, Secrets, PVCs) consistently. Using Kopia as the file uploader provides efficient incremental backups for Nextcloud user files without full-snapshot overhead.

### Why rclone to OneDrive for offsite

MinIO runs inside the cluster. If the cluster is destroyed along with its storage, MinIO data would be lost. rclone syncs both MinIO buckets nightly to OneDrive, providing an off-cluster copy that survives complete infrastructure failure.

OneDrive was chosen because: free tier (5GB+) is sufficient for homelab backup volumes, authentication uses OAuth (manageable long-term token), and rclone has stable OneDrive support.

### Why not Longhorn snapshots as the primary database backup

Longhorn volume snapshots are node-local and cluster-scoped. They do not provide PITR and do not survive a full cluster rebuild. They are used only as a fast, local recovery layer for non-database volumes.

---

## Consequences

**Positive:**
- PITR available for all PostgreSQL databases from the first base backup
- Kubernetes objects recoverable from Velero for any namespace in the backup scope
- Complete cluster loss is survivable if MinIO data is intact, or recoverable from OneDrive if it is not
- All backup storage is in-cluster (MinIO) — low egress cost, fast restore

**Trade-offs:**
- rclone syncs files, not S3 objects. Restore from OneDrive requires copying data back into a MinIO instance first, then using Velero/Barman normally — this is not instant
- MinIO itself is not redundantly backed up; a MinIO data loss before the nightly rclone runs means up to 24 hours of backup data is unrecoverable
- Vault secrets are not backed up by any of these tools — they must be re-entered manually after a full DR scenario

---

## Alternatives Considered

**Velero for databases too:** Cannot provide PITR. Captures inconsistent state unless using application-aware hooks. CNPG Barman is purpose-built for PostgreSQL and the correct tool.

**Restic instead of rclone for offsite:** Restic provides deduplication and encryption but is more complex to restore from. rclone's direct file sync to OneDrive is simpler to validate and restore from.

**AWS S3 for backup storage:** Requires cloud egress costs and introduces a cloud dependency. MinIO inside the cluster eliminates both.

---

## Related

- [Backup Procedures Runbook](../runbooks/backup-procedures.md)
- [Disaster Recovery Runbook](../runbooks/disaster-recovery.md)
- [Data Layer Reference](../reference/data-layer.md)
