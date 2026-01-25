# ADR-009: Storage Strategy

## Status

Accepted

## Date

2026-01-12

## Context

Kubernetes workloads requiring persistent storage need a storage provisioner to dynamically create PersistentVolumes. Requirements:

- Dynamic PV provisioning (no manual PV creation)
- Support for ReadWriteOnce access mode
- Minimal operational overhead for initial platform setup
- Path to production-grade storage in future phases

Options evaluated:
1. Manual PV creation (no provisioner)
2. local-path-provisioner (Rancher)
3. Longhorn (distributed block storage)
4. NFS provisioner
5. OpenEBS

## Decision

Use **local-path-provisioner** for initial platform phases, with planned migration to **Longhorn** in Phase 8.

## Rationale

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

## Implementation

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
```

Storage class created: `local-path`

Data location on nodes: `/opt/local-path-provisioner/`

## Consequences

### Positive

- Immediate dynamic provisioning capability
- Zero configuration required
- Minimal resource footprint
- Sufficient for platform services (ArgoCD, Prometheus)

### Negative

- No data replication (node failure = data loss)
- No snapshots or backup integration
- Not suitable for production stateful workloads
- Data bound to specific node (no pod migration)

### Accepted Risks

- **Data loss on node failure** — Acceptable for current phase. Platform services can be redeployed; observability data is non-critical.
- **No cross-node scheduling** — Pods with PVCs pinned to node where data resides.

## Migration Plan (Phase 8)

```
Phase 5-7: local-path-provisioner
    │
    ▼
Phase 8: Longhorn deployment
    │
    ├── Install Longhorn via GitOps
    ├── Set Longhorn as default StorageClass
    ├── Migrate stateful workloads
    └── Retain local-path for non-critical storage
```

## Alternatives Considered

### Manual PV Creation

Rejected due to:
- Operational overhead for each PVC
- No dynamic provisioning
- Doesn't scale

### Longhorn (Immediate)

Deferred due to:
- Resource overhead premature for platform bootstrapping
- Complexity before core platform is stable
- Planned for Phase 8 when applications require resilience

### NFS Provisioner

Rejected due to:
- Requires external NFS server
- Single point of failure
- Additional infrastructure to manage

### OpenEBS

Rejected due to:
- Higher complexity than Longhorn
- Smaller community in homelab space
- Longhorn better aligned with Rancher/SUSE ecosystem knowledge

## References

- [local-path-provisioner](https://github.com/rancher/local-path-provisioner)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Kubernetes Storage Concepts](https://kubernetes.io/docs/concepts/storage/)
