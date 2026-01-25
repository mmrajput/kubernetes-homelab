# ADR-002: Hypervisor Selection

## Status

Accepted

## Date

2025-12-15

## Context

This homelab requires a virtualization layer to run multiple Kubernetes nodes on a single physical host (Beelink SER5 Pro, 32GB RAM, 500GB NVMe). The hypervisor must support:

- Running 3+ VMs concurrently (1 control plane, 2+ workers)
- Efficient resource utilization on consumer hardware
- Cloud-init support for automated VM provisioning
- Snapshot/backup capabilities for disaster recovery
- Low operational overhead for a single operator

Options evaluated:

1. **Proxmox VE** — Open-source, Debian-based, KVM/QEMU
2. **VMware ESXi** — Industry standard, free tier available
3. **Bare-metal Kubernetes** — No hypervisor, direct installation
4. **Hyper-V** — Windows-based, included with Windows Pro

## Decision

Use **Proxmox VE 8.x** as the hypervisor platform.

## Rationale

| Criteria | Proxmox VE | VMware ESXi | Bare-metal | Hyper-V |
|----------|------------|-------------|------------|---------|
| Cost | ✅ Free, open-source | ⚠️ Free tier limited | ✅ Free | ⚠️ Windows license |
| Cloud-init support | ✅ Native | ⚠️ Requires customization | N/A | ❌ Limited |
| Web UI | ✅ Full-featured | ✅ Full-featured | N/A | ⚠️ Requires Windows |
| CLI/API automation | ✅ Excellent (qm, pvesh) | ⚠️ PowerCLI/vSphere | N/A | ⚠️ PowerShell |
| Community/docs | ✅ Strong | ✅ Strong | N/A | ⚠️ Enterprise focus |
| Resource overhead | ✅ Low (~1GB) | ⚠️ Higher | ✅ None | ⚠️ Higher |
| Snapshot/backup | ✅ Built-in | ✅ Built-in | ❌ Manual | ✅ Built-in |
| Learning value | ✅ Linux/KVM skills | ⚠️ Proprietary | ⚠️ Limited | ❌ Windows-specific |

**Key factors:**

1. **Cloud-init integration** — Proxmox has native cloud-init support, enabling automated VM provisioning with static IPs, SSH keys, and hostname configuration. This mirrors cloud provider patterns (AWS EC2, Azure VMs).

2. **Open-source tooling** — Skills transfer directly to production environments using KVM/QEMU (OpenStack, oVirt, cloud providers).

3. **Resource efficiency** — Minimal hypervisor overhead leaves more RAM/CPU for Kubernetes workloads.

4. **API-driven operations** — `qm` CLI and REST API enable Infrastructure as Code patterns for VM lifecycle management.

## Consequences

### Positive

- Full control over virtualization layer with open-source tooling
- Cloud-init enables repeatable, automated VM provisioning
- Web UI simplifies day-to-day operations (console access, snapshots)
- Skills transferable to enterprise Linux virtualization
- Strong community support and documentation

### Negative

- No native HA without additional Proxmox nodes (acceptable for homelab)
- Learning curve for Proxmox-specific tooling (qm, pvesh)
- Not directly equivalent to cloud provider experience (AWS/Azure/GCP)

### Risks Mitigated

- **Vendor lock-in**: Open-source, can migrate VMs to any KVM-based platform
- **Disaster recovery**: Built-in snapshot and backup capabilities
- **Automation**: Cloud-init + API enables Infrastructure as Code

## Alternatives Considered

### VMware ESXi

Rejected due to:
- Free tier limitations (no API access, limited vCPUs)
- Proprietary tooling doesn't align with open-source homelab goals

### Bare-metal Kubernetes

Rejected due to:
- No isolation between experiments (breaking cluster affects everything)
- No snapshot capability for quick rollback
- Cannot simulate multi-node scenarios on single host

### Hyper-V

Rejected due to:
- Requires Windows host (adds complexity and licensing)
- Cloud-init support is limited
- Skills less transferable to Linux-centric platform engineering roles

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Cloud-init with Proxmox](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Proxmox API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
