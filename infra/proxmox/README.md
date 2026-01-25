# Proxmox Infrastructure

## Overview

Proxmox Virtual Environment (VE) 8.x serves as the hypervisor layer for the Kubernetes homelab, providing VM isolation, resource management, and network bridging.

## Host Specifications

**Hardware:** Beelink SER5 Pro Mini PC

| Component | Specification |
|-----------|---------------|
| CPU | AMD Ryzen 5 5500U (6C/12T) |
| RAM | 32 GB DDR4 (27 GiB usable) |
| Storage | 500 GB NVMe SSD |
| Network | Gigabit Ethernet |

## Resource Allocation

| Node | VM ID | vCPUs | RAM | Disk | IP Address |
|------|-------|-------|-----|------|------------|
| k8s-cp-01 | 1001 | 3 | 6GB | 50GB | 192.168.178.34 |
| k8s-worker-01 | 2001 | 3 | 7GB | 100GB | 192.168.178.35 |
| k8s-worker-02 | 2002 | 3 | 7GB | 100GB | 192.168.178.36 |
| **Total** | - | **9/12** | **20/27GB** | **250/450GB** | - |

**Available headroom:** 3 vCPUs, 7GB RAM, 200GB disk

## Network Configuration

| Component | Value |
|-----------|-------|
| Proxmox Host | 192.168.178.33 |
| Gateway | 192.168.178.1 |
| DNS | 192.168.178.1, 8.8.8.8 |
| Bridge | vmbr0 |

```
Router (192.168.178.1)
    ↓
enp1s0 (physical NIC)
    ↓
vmbr0 (Linux bridge)
    ↓
VMs (192.168.178.34-36)
```

## Storage Layout

```
/dev/nvme0n1 (500GB NVMe)
├── nvme0n1p1 - EFI (1GB)
├── nvme0n1p2 - Boot (1GB)
└── nvme0n1p3 - LVM PV (498GB)
    ├── pve-root (96GB)
    ├── pve-swap (8GB)
    └── pve-data (394GB) - VM disks
```

| Storage | Type | Content |
|---------|------|---------|
| local | Directory | ISO images, templates |
| local-lvm | LVM-Thin | VM disk images |

## VM Provisioning

VM templates enable rapid provisioning using cloud-init. See [`vm-templates/`](vm-templates/) for automation:

| Script | Purpose |
|--------|---------|
| `create-template.sh` | Create Ubuntu 24.04 cloud-init template |
| `create-k8s-controlplane.sh` | Create control plane VM |
| `create-k8s-workers.sh` | Create worker VMs |
| `destroy-cluster.sh` | Destroy VMs for rebuild |

**Quick deployment:**

```bash
cd vm-templates/
./create-template.sh           # Once: create base template
./create-k8s-controlplane.sh   # Create control plane
./create-k8s-workers.sh        # Create workers
```

**Cluster rebuild:**

```bash
cd vm-templates/
./destroy-cluster.sh --all
# Re-run creation scripts
```

## Access

**Web Interface:**
```
URL: https://192.168.178.33:8006
User: root
```

**SSH:**
```bash
ssh root@192.168.178.33
```

## Common Commands

```bash
# List all VMs
qm list

# Start/stop VM
qm start <VMID>
qm stop <VMID>

# View VM config
qm config <VMID>

# Check storage usage
pvesm status

# Check LVM thin pool
lvs
```

## Troubleshooting

### Web Interface Unreachable

```bash
# Check services
systemctl status pveproxy pvedaemon

# Restart if needed
systemctl restart pveproxy pvedaemon

# Verify port listening
ss -tlnp | grep 8006
```

### Storage Full

```bash
# Check usage
df -h
pvesm status

# List VMs for cleanup
qm list
qm destroy <VMID>
```

### Network Issues

```bash
# Check bridge status
ip link show vmbr0

# Restart networking
systemctl restart networking
```

## Maintenance

```bash
# Update packages (weekly)
apt update && apt full-upgrade -y

# Backup configuration
tar -czf /root/pve-config-$(date +%F).tar.gz /etc/pve/
```

## Related Documentation

- [Installing Proxmox VE on Beelink SER5 Pro](../../docs/guides/proxmox-installation.md)
- [VM Templates](vm-templates/README.md) — Automated VM provisioning
- [Ansible Automation](../ansible/README.md) — Kubernetes installation
- [Network Topology](../../docs/architecture/network-topology.md) — Network design
- [ADR-002: Hypervisor Selection](../../docs/adr/ADR-002-hypervisor-selection.md)

---

**Last Updated:** January 2026
