# Installing Proxmox VE on Beelink SER5 Pro

## Overview

| | |
|---|---|
| **Hardware** | Beelink SER5 Pro (AMD Ryzen 5 5500U, 32GB RAM, 500GB NVMe) |
| **Software** | Proxmox VE 8.x |

This guide documents the complete process of installing Proxmox VE on a Beelink SER5 Pro mini PC for a production-grade Kubernetes homelab environment.

### Why Proxmox?

- **Type 1 Hypervisor** — Bare-metal virtualization for optimal performance
- **Enterprise Features** — Snapshots, backups, clustering, HA support
- **Web-Based Management** — Accessible from any device
- **Free and Open Source** — No licensing costs
- **KVM/LXC Support** — Run both VMs and containers

---

## Hardware Specifications

```
CPU:     AMD Ryzen 5 5500U (6 cores / 12 threads, up to 4.0GHz)
RAM:     32GB DDR4 (27 GiB usable)
Storage: 500GB NVMe SSD (476GB usable)
Network: 1x Gigabit Ethernet (Realtek)
```

### Resource Allocation Plan

```
Proxmox Host:     ~7GB RAM reserved
Kubernetes VMs:   ~20GB RAM allocated
  - Control Plane: 6GB RAM, 3 vCPU, 50GB disk
  - Worker 1:      7GB RAM, 3 vCPU, 100GB disk
  - Worker 2:      7GB RAM, 3 vCPU, 100GB disk
```

**Power Consumption:** ~25-35W average

---

## Prerequisites

### Required Items

1. **Hardware:**
   - Beelink SER5 Pro mini PC
   - Monitor + HDMI cable (temporary, for initial setup)
   - USB keyboard (temporary)
   - Ethernet cable
   - USB flash drive (8GB minimum)

2. **Software Downloads:**
   - Proxmox VE ISO: [proxmox.com/downloads](https://www.proxmox.com/en/downloads)
   - Rufus (Windows): [rufus.ie](https://rufus.ie/) or balenaEtcher (cross-platform)

3. **Network Information:**
   - Router IP address (e.g., 192.168.178.1)
   - Desired static IP for Proxmox (e.g., 192.168.178.33)
   - Network subnet mask (usually /24)

---

## Installation Process

### Step 1: Create Bootable USB

**Using Rufus (Windows):**

1. Download Proxmox VE ISO
2. Insert USB flash drive
3. Launch Rufus and configure:
   ```
   Device:           [Your USB drive]
   Boot selection:   [Proxmox VE ISO]
   Partition scheme: MBR
   Target system:    BIOS or UEFI
   File system:      FAT32
   ```
4. Click **START**
5. Select **"Write in ISO Image mode"** when prompted
6. Wait for completion (~5 minutes)

### Step 2: Configure BIOS Settings

1. **Access BIOS:**
   - Power on Beelink
   - Press **DEL** or **F2** repeatedly

2. **Required Settings:**
   ```
   Boot Mode:
     → UEFI (or UEFI with CSM)
     → Disable Secure Boot
   
   Virtualization:
     → AMD-V / SVM Mode: ENABLED
     → IOMMU: ENABLED (if available)
   
   Boot Priority:
     → 1st: USB Device
     → 2nd: NVMe SSD
   
   Power Settings (Optional):
     → After Power Loss: Power On
   ```

3. **Save & Exit:** Press F10

### Step 3: Install Proxmox VE

1. **Boot Menu:** Select **Install Proxmox VE (Graphical)**

2. **EULA:** Click **I agree**

3. **Target Harddisk:**
   ```
   Target Disk:  500GB NVMe SSD
   Filesystem:   ext4
   hdsize:       500 (full disk)
   swapsize:     8
   ```

4. **Location and Timezone:**
   ```
   Country:   Germany
   Timezone:  Europe/Berlin
   Keyboard:  Your preference
   ```

5. **Administration Password:**
   ```
   Password:  [Strong password]
   Email:     your-email@example.com
   ```

6. **Network Configuration:**
   ```
   Management Interface:  enp1s0
   Hostname (FQDN):       pve.homelab.local
   IP Address:            192.168.178.33
   Netmask:               255.255.255.0
   Gateway:               192.168.178.1
   DNS Server:            192.168.178.1
   ```

7. **Install:** Review and click **Install** (10-15 minutes)

8. **Complete:** Remove USB and reboot

---

## Post-Installation Configuration

### First Login

```
pve login: root
Password: [your password]
```

### Step 1: Verify Network

```bash
# Check IP configuration
ip addr show

# Test connectivity
ping -c 4 8.8.8.8
ping -c 4 google.com
```

### Step 2: Configure Repositories

```bash
# Disable enterprise repo (requires subscription)
echo "# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise" > /etc/apt/sources.list.d/pve-enterprise.list

# Add community repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list

# Update system
apt update
apt upgrade -y
```

### Step 3: Verify SSH Access

```bash
# From your workstation
ssh root@192.168.178.33
```

---

## Network Configuration

### Bridge Architecture

```
Router (192.168.178.1)
    ↓ Ethernet
enp1s0 (physical NIC)
    ↓
vmbr0 (Linux bridge)
    ↓
VMs (192.168.178.34-36)
```

### Configuration File

`/etc/network/interfaces`:

```bash
auto lo
iface lo inet loopback

iface enp1s0 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.178.33/24
    gateway 192.168.178.1
    bridge-ports enp1s0
    bridge-stp off
    bridge-fd 0
    dns-nameservers 192.168.178.1 8.8.8.8

source /etc/network/interfaces.d/*
```

### Verify Network

```bash
ip link show
brctl show
ip route show
```

---

## WiFi Considerations

**WiFi is not recommended for Proxmox hosts:**

1. **Bridge Incompatibility** — WiFi adapters don't support traditional bridging
2. **Performance** — Higher latency (5-20ms vs <1ms Ethernet)
3. **Stability** — Packet loss under load affects Kubernetes components

**Recommendation:** Use Ethernet connection only.

---

## Remote Access

### Web UI

```
URL:      https://192.168.178.33:8006
Username: root
Password: [your password]
Realm:    Linux PAM standard authentication
```

### SSH

```bash
ssh root@192.168.178.33
```

---

## Troubleshooting

### Network Issues

```bash
# Check interface status
ip link show

# Check IP address
ip addr show vmbr0

# Bring interface up
ip link set vmbr0 up

# Set IP manually if needed
ip addr add 192.168.178.33/24 dev vmbr0
ip route add default via 192.168.178.1
```

### Repository Errors (401 Unauthorized)

```bash
# Disable enterprise repo
echo "# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise" > /etc/apt/sources.list.d/pve-enterprise.list
apt update
```

### Web UI Unreachable

```bash
# Check service status
systemctl status pveproxy

# Verify port listening
netstat -tulpn | grep 8006

# Restart services
systemctl restart pveproxy pvedaemon
```

### Virtualization Not Available

```bash
# Check CPU support
egrep -c '(vmx|svm)' /proc/cpuinfo

# Check modules
lsmod | grep kvm

# Load module
modprobe kvm_amd
```

---

## Next Steps

After Proxmox installation is complete:

1. **Create VM Template** — See [vm-templates/README.md](../../infra/proxmox/vm-templates/README.md)
2. **Provision Kubernetes VMs** — Run automation scripts
3. **Install Kubernetes** — See [Ansible README](../../infra/ansible/README.md)

---

## References

- [Proxmox Official Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox Forums](https://forum.proxmox.com/)
- [ADR-002: Hypervisor Selection](../adr/ADR-002-hypervisor-selection.md)

---

**Last Updated:** January 2026
