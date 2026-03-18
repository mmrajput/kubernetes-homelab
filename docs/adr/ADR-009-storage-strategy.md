# ADR-009: Storage Strategy

## Status

Accepted — Updated Phase 8 (2026-03-17)

## Date

2026-01-12 — Initial decision (local-path-provisioner)
2026-03-17 — Updated to include Phase 8 storage architecture

## Context

Kubernetes workloads requiring persistent storage need a storage provisioner to dynamically create PersistentVolumes. Requirements evolved across phases:

**Phase 4-7 requirements:**
- Dynamic PV provisioning (no manual PV creation)
- Support for ReadWriteOnce access mode
- Minimal operational overhead for initial platform setup
- Path to production-grade storage in future phases

**Phase 8 requirements:**
- Replicated block storage for stateful workloads (PostgreSQL, Keycloak)
- S3-compatible object storage for Loki long-term log storage
- S3-compatible object storage for Velero backup target
- Storage class hierarchy matching workload criticality

**Hardware constraint:** Single Beelink SER5 Pro host running three VMs (1 control plane, 2 workers) via Proxmox LVM-thin provisioning on a 500GB NVMe.

## Decisions

### Phase 4-7: local-path-provisioner

Use **local-path-provisioner** for initial platform phases, with planned migration to **Longhorn** in Phase 8.

Options evaluated:
1. Manual PV creation (no provisioner)
2. local-path-provisioner (Rancher)
3. Longhorn (distributed block storage)
4. NFS provisioner
5. OpenEBS

| Criteria | Manual PV | local-path | Longhorn | NFS | OpenEBS |
|----------|-----------|------------|----------|-----|---------|
| Dynamic provisioning | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| Setup complexity | ✅ None | ✅ Single manifest | ⚠️ Medium | ⚠️ External server | ⚠️ Medium |
| Resource overhead | ✅ None | ✅ Minimal | ⚠️ ~500MB/node | ✅ Minimal | ⚠️ Medium |
| Data replication | ❌ No | ❌ No | ✅ Yes | ❌ No (single server) | ✅ Yes |
| Node failure tolerance | ❌ No | ❌ No | ✅ Yes | ❌ No | ✅ Yes |
| Snapshots | ❌ No | ❌ No | ✅ Yes | ❌ No | ✅ Yes |
| Production readiness | ❌ No | ⚠️ Dev/Test | ✅ Yes | ⚠️ Limited | ✅ Yes |

**Key factors:**

1. **Minimal initial overhead** — Platform services (ArgoCD, Prometheus) need storage, but data replication is not critical in early phases.
2. **Fast iteration** — Single kubectl apply to install, no configuration required.
3. **Clear upgrade path** — Longhorn planned for Phase 8 when stateful applications require resilience.
4. **Resource conservation** — Longhorn's per-node overhead (~500MB) deferred until observability and applications are stable.

### Phase 8: Longhorn for Distributed Block Storage

Use **Longhorn v1.7.2** with replication factor 2 as the default StorageClass for production stateful workloads.

**Alternatives considered:**

| Option | Replication | Snapshots | Complexity | Decision |
|--------|-------------|-----------|------------|----------|
| local-path only | ❌ No | ❌ No | ✅ Minimal | ❌ Rejected |
| Longhorn | ✅ Yes | ✅ Yes | ⚠️ Medium | ✅ Selected |
| OpenEBS | ✅ Yes | ✅ Yes | ⚠️ Higher | ❌ Rejected |
| Rook/Ceph | ✅ Yes | ✅ Yes | ❌ High | ❌ Rejected |

**Rationale:**
- RF=2 places one replica on each worker node — single worker failure does not cause data loss
- Longhorn is the de facto standard for on-premises Kubernetes block storage, particularly relevant for sovereign infrastructure operators in the DACH market who cannot use managed cloud storage
- Native CSI integration — standard Kubernetes PVC workflow unchanged
- Built-in snapshot capability aligns with future DR requirements
- Rook/Ceph rejected — excessive resource overhead for single-host homelab
- OpenEBS rejected — higher complexity than Longhorn with no additional benefit at this scale

**Configuration:**
- Replication factor: 2 (one replica per worker node)
- Default StorageClass: yes — all PVCs without explicit StorageClass use Longhorn
- Storage path: `/var/lib/longhorn` on each worker node
- `local-path` retained and explicitly assigned for non-critical workloads

**Single host limitation acknowledged:** Longhorn RF=2 protects against worker VM failure but not Proxmox host failure. Both replicas reside on the same physical machine. Full disaster recovery requires off-cluster backup via Velero (planned).

### Phase 8: MinIO for Object Storage

Use **MinIO** (standalone mode) as the S3-compatible object storage backend, deployed on `local-path` storage within the cluster.

**Purpose:** Two buckets serving distinct purposes:
- `loki` — Loki long-term chunk and index storage
- `velero` — Velero backup target (future phase)

**Alternatives considered:**

| Option | Cost | Off-cluster | Availability | Decision |
|--------|------|-------------|--------------|----------|
| Loki filesystem backend | Free | ❌ No | ⚠️ PVC-bound | ❌ Rejected |
| MinIO on Beelink | Free | ❌ No | ✅ In-cluster | ✅ Selected |
| Cloudflare R2 | Free tier | ✅ Yes | ✅ High | ⚠️ Future |
| AWS S3 | Paid | ✅ Yes | ✅ High | ❌ Rejected |
| MinIO on laptop | Free | ✅ Yes | ⚠️ Unreliable | ❌ Rejected |

**Rationale:**
- MinIO implements the S3-compatible API — Loki and Velero use identical configuration regardless of whether the backend is MinIO, Cloudflare R2, or AWS S3
- Loki requires low-latency, always-available object storage for frequent chunk writes — in-cluster MinIO is the correct choice
- Filesystem backend rejected — no retention management, fills PVC silently, no object lifecycle policies
- Cloudflare R2 identified as the correct future target for Velero backups (off-cluster, free tier, no egress fees) — planned when Velero is in scope
- MinIO on laptop rejected for Loki — laptop availability cannot be guaranteed, causing Loki write failures when laptop is off

**MinIO storage class decision:** `local-path` chosen over Longhorn for MinIO because:
- MinIO itself provides application-level redundancy when clustered
- Single-node MinIO on Longhorn adds block-level replication overhead with no additional resilience on a single-host setup
- Longhorn reserved for stateful application data (PostgreSQL, Keycloak) where RF=2 provides meaningful worker-level protection

**Off-cluster replication:** MinIO bucket replication to an off-cluster target (laptop MinIO + OneDrive sync via rclone) is planned as a future enhancement to address the single-host failure scenario.

## Storage Class Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                    Storage Class Hierarchy                   │
├─────────────────┬───────────────────────────────────────────┤
│ local-path      │ Non-critical, single-node workloads        │
│                 │ Prometheus WAL, Loki WAL, MinIO data        │
│                 │ Fast, simple, no replication               │
├─────────────────┼───────────────────────────────────────────┤
│ longhorn        │ Production stateful workloads (DEFAULT)    │
│ (default)       │ PostgreSQL, Keycloak, application data     │
│                 │ RF=2, worker-level failure tolerance        │
├─────────────────┼───────────────────────────────────────────┤
│ minio           │ Object storage (not a StorageClass)        │
│ (S3 API)        │ Loki chunks/index, Velero backups          │
│                 │ S3-compatible, lifecycle management        │
└─────────────────┴───────────────────────────────────────────┘
```

## Implementation

### Phase 4-7: local-path-provisioner

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
```

Storage class created: `local-path`
Data location on nodes: `/opt/local-path-provisioner/`

### Phase 8: Longhorn

Deployed via ArgoCD Helm chart — `platform/argocd/apps/longhorn-app.yaml`
Values: `platform/longhorn/values.yaml`
Namespace: `longhorn-system` (privileged PSS — requires host disk access)

Prerequisites on worker nodes:
```bash
sudo apt-get install -y open-iscsi nfs-common
sudo systemctl enable iscsid && sudo systemctl start iscsid
```

### Phase 8: MinIO

Deployed via ArgoCD Helm chart — `platform/argocd/apps/minio-app.yaml`
Values: `platform/minio/values.yaml`
Namespace: `minio` (baseline PSS — post-install job containers do not support restricted PSS)
Credentials: Kubernetes secret `minio-credentials` (not stored in Git)

Buckets created automatically via Helm post-install job:
- `loki` — Loki object storage backend
- `velero` — Velero backup target (future)

## Consequences

### Positive

- Stateful workloads (PostgreSQL, Keycloak) have worker-level failure tolerance via Longhorn RF=2
- Loki log retention managed via S3 lifecycle policies instead of PVC capacity limits
- Storage class hierarchy clearly separates concerns — workload type determines storage class
- S3-compatible API abstraction allows future migration from MinIO to Cloudflare R2 or AWS S3 without application changes
- Longhorn and MinIO are both standard components in DACH enterprise on-premises Kubernetes stacks — directly relevant to target roles

### Negative

- No protection against complete host failure — single Beelink is the ultimate single point of failure
- MinIO on `local-path` has no replication — host failure loses all Loki logs and Velero backups
- Longhorn adds ~500MB RAM overhead per worker node
- MinIO post-install jobs cannot run under restricted PSS — minio namespace uses baseline PSS

### Accepted Risks

- **Single host failure** — Accepted for homelab. Mitigated in future by off-cluster Velero backups to Cloudflare R2 or MinIO laptop instance with OneDrive sync.
- **MinIO on local-path** — Loki logs are observability data, not business data. Loss is inconvenient but not catastrophic. Velero backups will target off-cluster storage when Velero is configured.
- **Longhorn on shared NVMe** — No dedicated block device per worker. OS and Longhorn writes compete on the same virtual disk. Acceptable at homelab scale with monitoring in place.

## Future Enhancements

- **Velero** — Kubernetes-native backup and restore with scheduled backup policies (planned)
- **Off-cluster backup target** — Cloudflare R2 for Velero backups (free tier, S3-compatible, no egress fees)
- **MinIO off-cluster replication** — rclone sync to laptop MinIO + OneDrive for Loki data durability
- **Namespace separation** — Move Loki and Promtail to dedicated `logging` namespace, allowing `monitoring` namespace to use restricted PSS

## References

- [local-path-provisioner](https://github.com/rancher/local-path-provisioner)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [MinIO Documentation](https://min.io/docs/)
- [Loki S3 Storage Configuration](https://grafana.com/docs/loki/latest/configure/storage/)
- [Kubernetes Storage Concepts](https://kubernetes.io/docs/concepts/storage/)
- [BSI IT-Grundschutz — Storage Security](https://www.bsi.bund.de/EN/Themen/Unternehmen-und-Organisationen/Standards-und-Zertifizierung/IT-Grundschutz/it-grundschutz_node.html)
