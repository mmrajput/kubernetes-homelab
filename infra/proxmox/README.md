# Proxmox VE Foundation Setup

## Overview

This directory contains documentation and automation for the Proxmox Virtual Environment hypervisor that serves as the foundation for the Kubernetes homelab infrastructure.

**Proxmox Role:**
- Hypervisor layer providing VM isolation and resource management
- Hosts all Kubernetes cluster nodes (1 control plane + 2 workers)
- Provides network bridge for VM connectivity
- Manages storage allocation and disk provisioning

## Hardware Specifications

**Host Machine:** Beelink SER5 Pro Mini PC

| Component | Specification | Notes |
|-----------|--------------|-------|
| CPU | AMD Ryzen 5 5500U (6C/12T) | 2.1 GHz base, 4.0 GHz boost |
| RAM | 32 GB DDR4 | 27 GiB usable after iGPU allocation |
| Storage | 500 GB NVMe SSD | M.2 PCIe Gen3 |
| Network | 2x Gigabit Ethernet | One for management, one unused |
| GPU | AMD Radeon iGPU | 5 GiB allocated for display |

## Resource Allocation

**Proxmox Host Overhead:** ~7GB RAM reserved for hypervisor

**Kubernetes VMs:** 20GB RAM total allocated

| Node | VM ID | vCPUs | RAM | Disk | IP Address |
|------|-------|-------|-----|------|------------|
| k8s-cp-01 | 1001 | 3 | 6GB | 50GB | 192.168.178.34 |
| k8s-worker-01 | 2001 | 3 | 7GB | 100GB | 192.168.178.35 |
| k8s-worker-02 | 2002 | 3 | 7GB | 100GB | 192.168.178.36 |
| **Total** | - | **9/12** | **20/27GB** | **250/450GB** | - |

**Headroom:** 3 vCPUs, 7GB RAM, 200GB disk available for expansion.

## Network Configuration

See [Network Topology](../../docs/network-topology.md) for complete details.

**Quick Reference:**
- **Proxmox Host:** 192.168.178.33
- **Gateway:** 192.168.178.1
- **DNS:** 192.168.178.1, 8.8.8.8
- **Subnet:** 192.168.178.0/24

## Installation

### Prerequisites

- Beelink SER5 Pro with Ethernet cable connected
- USB drive (8GB minimum) for Proxmox installation media
- Access to another computer for USB creation
- Router with DHCP enabled

### Step 1: Create Proxmox Installation Media

**On Linux/macOS:**
```bash
# Download Proxmox VE ISO (version 8.x)
wget https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso

# Write to USB drive (replace /dev/sdX with your USB device)
sudo dd if=proxmox-ve_*.iso of=/dev/sdX bs=1M status=progress
sync
```

**On Windows:**
- Download ISO from https://www.proxmox.com/en/downloads
- Use Rufus or Etcher to write ISO to USB drive

### Step 2: Install Proxmox VE

1. **Boot from USB:**
   - Insert USB into Beelink SER5 Pro
   - Power on and press F7 to enter boot menu
   - Select USB drive

2. **Installation Wizard:**
   - Select "Install Proxmox VE (Graphical)"
   - Accept EULA
   - Select target disk: `/dev/nvme0n1` (500GB NVMe)
   - Filesystem: ext4 (default)

3. **Location and Time Zone:**
   - Country: Germany
   - Time zone: Europe/Berlin
   - Keyboard: English (US)

4. **Administration Password:**
   - Set root password (save in password manager)
   - Email: your-email@example.com (for system alerts)

5. **Network Configuration:**
   ```
   Management Interface: enp1s0 (first Ethernet port)
   Hostname (FQDN):      pve.home.lab
   IP Address (CIDR):    192.168.178.33/24
   Gateway:              192.168.178.1
   DNS Server:           192.168.178.1
   ```

6. **Installation:**
   - Review settings
   - Click "Install"
   - Wait 5-10 minutes for installation to complete
   - Reboot and remove USB drive

### Step 3: Initial Configuration

**Access Proxmox Web Interface:**
```bash
# From your workstation browser
https://192.168.178.33:8006

# Login credentials:
Username: root
Password: [password you set during installation]
```

**Accept self-signed certificate warning** (this is expected for local homelab).

**Post-Installation Tasks:**

1. **Update System:**
   ```bash
   # SSH into Proxmox host
   ssh root@192.168.178.33

   # Update package lists
   apt update

   # Upgrade installed packages
   apt full-upgrade -y

   # Reboot if kernel was updated
   reboot
   ```

2. **Disable Enterprise Repository** (requires subscription):
   ```bash
   # Comment out enterprise repo
   sed -i 's/^deb/# deb/' /etc/apt/sources.list.d/pve-enterprise.list

   # Add no-subscription repository
   echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list

   # Update package lists
   apt update
   ```

3. **Remove Subscription Notice** (optional):
   ```bash
   # Backup original file
   cp /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak

   # Remove subscription popup
   sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid subscription'\),)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

   # Clear browser cache and refresh web interface
   ```

4. **Configure NTP** (accurate time for Kubernetes):
   ```bash
   # Verify NTP is running
   systemctl status chrony

   # Check time synchronization
   chronyc tracking
   ```

## Storage Configuration

Proxmox uses LVM (Logical Volume Manager) by default:

**Storage Layout:**
```
/dev/nvme0n1 (500GB NVMe SSD)
├── /dev/nvme0n1p1 - EFI System Partition (1GB)
├── /dev/nvme0n1p2 - Boot (1GB)
└── /dev/nvme0n1p3 - LVM PV (498GB)
    ├── pve-root (96GB) - Proxmox root filesystem
    ├── pve-swap (8GB) - Swap space
    └── pve-data (394GB) - VM disk storage (thin-provisioned)
```

**Storage Pools:**

| Storage | Type | Content | Usage |
|---------|------|---------|-------|
| local | Directory | ISO images, CT templates | ISO/template storage |
| local-lvm | LVM-Thin | VM disks | VM disk images |

**Check available storage:**
```bash
# View storage summary
pvesm status

# Check LVM thin pool usage
lvs
```

## VM Template Creation

VM templates enable rapid, consistent VM provisioning using cloud-init.

**Template Strategy:**
- Create base Ubuntu 24.04 template with cloud-init
- Clone template for each Kubernetes node
- Customize via cloud-init user-data

See [`vm-templates/`](vm-templates/) directory for automation scripts:
- `create-template.sh` - Download and create Ubuntu cloud-init template
- `create-k8s-controlplane.sh` - Create control plane VM from template
- `create-k8s-workers.sh` - Create worker VMs from template in batch
- `destroy-cluster.sh` - Safely destroy VMs for rebuild testing

## Networking Details

### Bridge Configuration

Proxmox creates a Linux bridge (`vmbr0`) for VM networking. This acts as a virtual switch that connects VMs to the physical network:

```
Physical Network:
  Router (192.168.178.1)
    ↓ Ethernet cable
  enp1s0 (physical NIC on Proxmox host)
    ↓ bridged to
  vmbr0 (Linux bridge - virtual switch)
    ↓ VMs connect here
  VMs get IPs from router's DHCP or static assignments
```

**View bridge configuration:**
```bash
ip addr show vmbr0

# Output shows bridge IP and status:
# 3: vmbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP
#     inet 192.168.178.33/24 brd 192.168.178.255 scope global vmbr0
```

**Bridge Configuration File:** `/etc/network/interfaces`
```bash
# Loopback interface (internal system communication)
auto lo
iface lo inet loopback

# Physical Network Interface
# The physical NIC is configured without an IP (manual mode)
# because the bridge will handle the IP configuration
auto enp1s0
iface enp1s0 inet manual

# Bridge Interface for VMs
# This is what VMs connect to and what has the Proxmox host IP
auto vmbr0
iface vmbr0 inet static
    address 192.168.178.33/24  # Proxmox host IP
    gateway 192.168.178.1      # Router for internet access
    bridge-ports enp1s0        # Attach physical NIC to bridge
    bridge-stp off             # Disable Spanning Tree Protocol (not needed)
    bridge-fd 0                # No forwarding delay (faster startup)
    dns-nameservers 192.168.178.1 8.8.8.8  # DNS servers
```

**How VMs use the bridge:**
- VMs connect to `vmbr0` just like they're plugged into a physical switch
- VMs can get IPs via DHCP from router, or use static IPs
- VMs can communicate with each other and reach the internet
- Proxmox host and VMs share the same physical network

### Firewall Configuration

Proxmox firewall is **disabled** for homelab simplicity:
- All traffic allowed between VMs and host
- Router provides external firewall protection
- Kubernetes NetworkPolicies handle pod-level security

**To verify firewall status:**
```bash
# Check datacenter-level firewall
pve-firewall status

# Should show: Status: disabled
```

## Troubleshooting

### Cannot Access Web Interface

**Symptom:** Browser cannot connect to https://192.168.178.33:8006

**Diagnosis:**
```bash
# Check if Proxmox services are running
systemctl status pveproxy
systemctl status pvedaemon
systemctl status pve-cluster

# Check if port 8006 is listening
netstat -tlnp | grep 8006

# Verify network connectivity
ping 192.168.178.1  # Ping gateway
ip addr show vmbr0  # Check IP configuration
```

**Solutions:**
- Restart Proxmox services: `systemctl restart pveproxy pvedaemon`
- Verify firewall is disabled: `systemctl stop pve-firewall`
- Check physical network cable connection
- Verify router DHCP hasn't changed Proxmox IP

### Storage Full

**Symptom:** Cannot create new VMs, "no space left on device"

**Diagnosis:**
```bash
# Check filesystem usage
df -h

# Check LVM thin pool usage
lvs

# Check VM disk usage
pvesm status
```

**Solutions:**
```bash
# Remove old/unused VM disks
qm list  # List all VMs
qm destroy <VMID>  # Remove VM and its disks

# Remove old ISO images
rm /var/lib/vz/template/iso/*.iso

# Extend LVM if needed (advanced)
lvextend -l +100%FREE /dev/pve/data
```

### Network Bridge Not Working

**Symptom:** VMs cannot get IP addresses or access network

**Diagnosis:**
```bash
# Check bridge status
ip link show vmbr0

# Should show: state UP

# Check bridge ports
bridge link

# Should show: enp1s0 state UP
```

**Solutions:**
```bash
# Restart networking
systemctl restart networking

# Or reboot host
reboot

# Verify /etc/network/interfaces configuration
cat /etc/network/interfaces
```

### Time Synchronization Issues

**Symptom:** Kubernetes certificates fail, time is incorrect

**Diagnosis:**
```bash
# Check current time
date

# Check NTP synchronization
chronyc tracking

# Check NTP sources
chronyc sources
```

**Solutions:**
```bash
# Restart chrony service
systemctl restart chrony

# Force time sync
chronyc -a makestep

# Verify sync
timedatectl status
```

### Emergency Recovery

**If Proxmox becomes unresponsive:**

1. **Physical access to Beelink:**
   - Connect monitor and keyboard
   - Press Ctrl+Alt+F2 to access console

2. **Network recovery:**
   ```bash
   # Manually configure network
   ip addr add 192.168.178.33/24 dev vmbr0
   ip route add default via 192.168.178.1
   
   # Test connectivity
   ping 192.168.178.1
   ```

3. **Service recovery:**
   ```bash
   # Restart all Proxmox services
   systemctl restart pve*
   
   # Check logs for errors
   journalctl -u pveproxy -f
   ```

## Best Practices

### Regular Maintenance

```bash
# Weekly: Update packages
apt update && apt full-upgrade -y

# Monthly: Clean old kernels (keep last 2)
pve-efiboot-tool kernel list
pve-efiboot-tool kernel remove <old-kernel-version>

# Check storage usage
pvesm status
```

### Backup Strategy

**Proxmox configuration backup:**
```bash
# Backup network configuration
cp /etc/network/interfaces /root/backups/interfaces.backup

# Backup VM configurations (stored in /etc/pve/)
tar -czf /root/backups/pve-config-$(date +%F).tar.gz /etc/pve/
```

**VM backups handled separately** (see Phase 4 backup automation).

### Security Considerations

**For homelab use:**
- ✅ Proxmox runs on isolated home network behind router firewall
- ✅ No port forwarding from internet to Proxmox
- ✅ Strong root password stored in password manager
- ✅ SSH access restricted to local network only

**Not implemented** (production environments should have):
- ❌ Two-factor authentication
- ❌ Separate admin accounts (using root is fine for homelab)
- ❌ Certificate management (self-signed is acceptable)

## Resource Monitoring

**Check host resource usage:**

```bash
# CPU, memory, load average
top

# Detailed CPU usage
mpstat 1

# Memory breakdown
free -h
cat /proc/meminfo

# Disk I/O
iostat -x 1

# Network traffic
iftop -i vmbr0
```

**Via Web Interface:**
- Navigate to: pve (host node) → Summary
- View real-time graphs for CPU, memory, network, disk

## Next Steps

After Proxmox foundation is ready:

1. ✅ **Create VM template** → See [`vm-templates/README.md`](vm-templates/README.md)
2. ✅ **Create cluster VMs** → Run automation scripts in `vm-templates/`
3. ✅ **Install Kubernetes** → See [`../ansible/README.md`](../ansible/README.md)

**Quick cluster deployment:**
```bash
cd vm-templates/
./create-template.sh              # Once: Create Ubuntu template
./create-k8s-controlplane.sh      # Create control plane
./create-k8s-workers.sh           # Create workers
# Cluster VMs ready in ~5 minutes
```

**Cluster rebuild/testing:**
```bash
cd vm-templates/
./destroy-cluster.sh --all        # Destroy all VMs
# Re-run creation scripts to rebuild
```

## References

- [Official Proxmox Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox VE Administration Guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.html)
- [Proxmox Community Forums](https://forum.proxmox.com/)

## Related Documentation

- [Network Topology](../../docs/network-topology.md) - Complete network architecture
- [VM Templates](vm-templates/README.md) - Automated VM provisioning
- [Setup Guide](../../docs/setup-guide.md) - End-to-end rebuild instructions
- [Troubleshooting Guide](../../docs/troubleshooting.md) - Common issues across all components
