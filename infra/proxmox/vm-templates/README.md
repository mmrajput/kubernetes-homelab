# Phase 2: VM Creation & Configuration

# VM Template and Provisioning Scripts

## Overview

This directory contains automation scripts for creating Kubernetes cluster VMs using Proxmox's cloud-init template system. The template-based approach ensures consistent, reproducible VM deployments with minimal manual configuration.

## Template-Based Provisioning Strategy

**Why templates?**
- ✅ **Consistency:** All VMs start from identical base configuration
- ✅ **Speed:** Clone VMs in seconds vs. manual installation in minutes
- ✅ **Automation:** Cloud-init handles OS configuration declaratively
- ✅ **Reproducibility:** Rebuild entire cluster with four scripts

**Traditional vs. Template Approach:**

```
Traditional Manual Method:              Template Method:
┌─────────────────────┐                ┌─────────────────────┐
│ Install Ubuntu ISO  │                │ Create template     │
│ (15 minutes)        │                │ (once, 5 minutes)   │
└──────────┬──────────┘                └──────────┬──────────┘
           │                                      │
           v                                      v
┌─────────────────────┐                ┌─────────────────────┐
│ Manual OS install   │                │ Clone VMs           │
│ (10 minutes)        │                │ (30 seconds each)   │
└──────────┬──────────┘                └──────────┬──────────┘
           │                                      │
           v                                      v
┌─────────────────────┐                ┌─────────────────────┐
│ Configure network   │                │ Cloud-init auto-    │
│ Configure SSH       │                │ configures network, │
│ Update packages     │                │ SSH, and packages   │
│ (5 minutes)         │                │ (automatic)         │
└─────────────────────┘                └─────────────────────┘

Total: ~30 min per VM                  Total: ~1 min per VM
```

## Directory Structure

```
infra/proxmox/vm-templates/
├── README.md                           # Overview of template system
├── create-template.sh                  # Step 1: Create Ubuntu cloud-init template
├── create-k8s-controlplane.sh          # Step 2: Create control plane from template
├── create-k8s-workers.sh               # Step 3: Create workers (you already have this)
└── destroy-cluster.sh                  # Bonus: Clean slate rebuild
```

## Scripts

### 1. `create-template.sh`
**Purpose:** Download Ubuntu 24.04 cloud image and create reusable Proxmox template

**What it does:**
- Downloads official Ubuntu cloud image (2.2GB compressed)
- Verifies SHA256 checksum for security
- Creates Proxmox VM with cloud-init support
- Converts VM to template (Template ID 9000)

**When to run:**
- Once during initial setup
- After Proxmox reinstall
- To upgrade to newer Ubuntu LTS release

**Usage:**
```bash
# SSH into Proxmox host
ssh root@192.168.178.33

# Navigate to scripts directory
cd /root/scripts/vm-templates  # Or wherever you stored these

# Make executable
chmod +x create-template.sh

# Run script
./create-template.sh
```

**Output:**
```
Template ID: 9000
Template Name: ubuntu-2404-template
Image: Ubuntu 24.04 LTS (Noble Numbat)
```

### 2. `create-k8s-controlplane.sh`
**Purpose:** Clone template and create Kubernetes control plane node

**What it does:**
- Clones Template 9000 to VM 1001
- Configures 6GB RAM, 3 vCPUs, 50GB disk
- Sets static IP: 192.168.178.34
- Injects SSH key via cloud-init
- Waits for cloud-init completion

**Prerequisites:**
```bash
# Generate SSH key (if not exists)
ssh-keygen -t ed25519 -C "homelab" -f ~/.ssh/id_ed25519_homelab

# Copy public key to Proxmox
scp ~/.ssh/id_ed25519_homelab.pub root@192.168.178.33:/tmp/
```

**Configuration:**
Edit script variables for your environment:
```bash
# Network (change if using different subnet)
VM_IP="192.168.178.34"
VM_GATEWAY="192.168.178.1"

# Cloud-init user
CLOUD_INIT_USER="mahmood"  # Change to your username

# SSH key location on Proxmox host
SSH_KEY_PATH="/tmp/id_ed25519_homelab.pub"
```

**Usage:**
```bash
# On Proxmox host
./create-k8s-controlplane.sh

# Follow prompts to confirm configuration
# Wait ~90 seconds for cloud-init to complete
```

**Verification:**
```bash
# Test SSH access
ssh -i ~/.ssh/id_ed25519_homelab mahmood@192.168.178.34

# Once logged in, verify:
cloud-init status --wait   # Should show "done"
df -h /                    # Should show ~50GB disk
ip addr show               # Should show 192.168.178.34
ping -c 3 google.com       # Test internet connectivity
```

### 3. `create-k8s-workers.sh`
**Purpose:** Clone template and create multiple worker nodes in batch

**What it does:**
- Clones Template 9000 to VMs 2001-2002 (or more)
- Configures 7GB RAM, 3 vCPUs, 100GB disk per worker
- Sets static IPs: 192.168.178.35-36
- Creates all workers in parallel

**Configuration:**
Edit the `WORKERS` array to add/remove workers:
```bash
declare -A WORKERS=(
  ["2001"]="k8s-worker-01|192.168.178.35|3|7168|100"
  ["2002"]="k8s-worker-02|192.168.178.36|3|7168|100"
  # Add more: ["2003"]="k8s-worker-03|192.168.178.37|3|7168|100"
)
```

**Usage:**
```bash
# On Proxmox host
./create-k8s-workers.sh

# Workers are created in parallel
# Wait ~90 seconds for all to complete
```

### 4. `destroy-cluster.sh`
**Purpose:** Safely destroy Kubernetes cluster VMs with confirmation prompts

**What it does:**
- Provides interactive menu for selective or complete destruction
- Backs up VM configurations before deletion
- Gracefully shuts down VMs before destroying
- Supports command-line arguments for automation

**When to use:**
- Cluster rebuild testing
- Resource cleanup
- Starting fresh after experimentation
- Disaster recovery practice

**Usage:**
```bash
# Interactive mode (recommended)
./destroy-cluster.sh

# Destroy all cluster VMs
./destroy-cluster.sh --all

# Destroy only workers (keep control plane)
./destroy-cluster.sh --workers-only

# Destroy control plane only
./destroy-cluster.sh --control-plane

# Quick destroy without prompts (use carefully!)
./destroy-cluster.sh --all --force
```

**Safety features:**
- Multiple confirmation prompts (unless `--force`)
- Automatic VM config backup to `/root/vm-backups/`
- Graceful shutdown with timeout fallback
- Template preserved by default

## Cloud-Init Configuration

Cloud-init is a standard for automating cloud instance initialization. Our VMs use it for:

**Network Configuration:**
- Static IP assignment (no DHCP dependency)
- DNS server configuration
- Search domain for short hostnames

**User Setup:**
- Create non-root user with sudo access
- Inject SSH public key (password auth disabled)
- Set proper permissions automatically

**System Initialization:**
- Expand root filesystem to full disk size
- Run package updates (optional)
- Install QEMU guest agent for better VM management

**How cloud-init works:**

```
VM Boot Sequence:
1. BIOS → Boot from scsi0 (our cloned disk)
2. GRUB → Load Linux kernel
3. Kernel → Mount root filesystem
4. Init → systemd starts services
5. Cloud-init → Reads config from IDE2 (cloud-init drive)
   ├── Configures network (static IP from qm set --ipconfig0)
   ├── Creates user (from qm set --ciuser)
   ├── Adds SSH key (from qm set --sshkeys)
   ├── Expands disk (cloud-init handles resize automatically)
   └── Marks status as "done"
6. SSH → Now accessible at configured IP
```

**Cloud-init status checking:**
```bash
# Check if cloud-init finished
cloud-init status --wait

# Possible outputs:
# status: done     → Success, VM is ready
# status: running  → Still configuring, wait
# status: error    → Something failed, check logs

# View detailed logs
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

## VM Numbering Scheme

Organized by role for clarity:

| VM ID Range | Purpose | Naming Convention |
|-------------|---------|-------------------|
| 9000        | Templates | `ubuntu-2404-template` |
| 1001-1009   | Control Plane | `k8s-cp-01`, `k8s-cp-02` (HA future) |
| 2001-2099   | Worker Nodes | `k8s-worker-01`, `k8s-worker-02`, ... |
| 3001-3099   | Future: Monitoring | `monitoring-01`, `logging-01` |

**Why this scheme?**
- Logical grouping by role
- Easy to identify VM purpose from ID
- Room for horizontal scaling (up to 99 workers)
- Follows enterprise conventions

## Network IP Allocation

Static IPs for predictable cluster networking:

```
192.168.178.0/24 Subnet Layout:
├── .1    → Router/Gateway
├── .33   → Proxmox Host
├── .34   → k8s-cp-01 (Control Plane)
├── .35   → k8s-worker-01
├── .36   → k8s-worker-02
└── .37-50 → Reserved for future cluster expansion
```

**Why static IPs vs. DHCP?**
- ✅ Kubernetes requires stable control plane endpoint
- ✅ No dependency on DHCP lease duration
- ✅ Easier troubleshooting (IP = hostname mapping)
- ✅ Direct Ansible inventory configuration

## Resource Allocation Summary

| Node | VM ID | vCPUs | RAM | Disk | IP Address |
|------|-------|-------|-----|------|------------|
| Template | 9000 | 2 | 2GB | 10GB | N/A (template) |
| k8s-cp-01 | 1001 | 3 | 6GB | 50GB | 192.168.178.34 |
| k8s-worker-01 | 2001 | 3 | 7GB | 100GB | 192.168.178.35 |
| k8s-worker-02 | 2002 | 3 | 7GB | 100GB | 192.168.178.36 |
| **Total Used** | - | **9** | **20GB** | **250GB** | - |

**Available headroom (Beelink SER5 Pro):**
- CPU: 12 threads total, 9 allocated (3 threads reserved for Proxmox)
- RAM: 27GB usable, 20GB allocated (7GB free buffer)
- Disk: 450GB usable, 250GB allocated (200GB free for logs/data)

## Troubleshooting

### Template creation fails: "Image checksum mismatch"

**Cause:** Download corruption or MITM attack

**Fix:**
```bash
# Delete corrupted image
rm /var/lib/vz/template/iso/ubuntu-24.04-server-cloudimg-amd64.img

# Re-download
./create-template.sh
```

### VM clone fails: "Template does not exist"

**Cause:** Template not created yet

**Fix:**
```bash
# Verify template exists
qm list | grep 9000

# If missing, create it
./create-template.sh
```

### Cloud-init never completes (status: running forever)

**Cause:** Network misconfiguration, wrong gateway

**Diagnosis:**
```bash
# SSH into Proxmox, access VM console
qm terminal 1001

# Login with: ubuntu / ubuntu (if first boot)
# Check cloud-init logs
sudo cat /var/log/cloud-init.log | tail -50
```

**Common issues:**
- Wrong gateway: `qm set 1001 --ipconfig0 ip=192.168.178.34/24,gw=192.168.178.1`
- DNS failure: `qm set 1001 --nameserver "192.168.178.1 8.8.8.8"`
- SSH key path wrong: Verify `SSH_KEY_PATH` in script points to actual public key

### Cannot SSH into VM: "Connection refused"

**Cause:** VM not finished booting or SSH key issue

**Fix:**
```bash
# Wait for cloud-init
ssh mahmood@192.168.178.34 'cloud-init status --wait'

# Verify SSH key is correct
cat /tmp/id_ed25519_homelab.pub  # On Proxmox
cat ~/.ssh/id_ed25519_homelab.pub  # On workstation (should match)

# Check VM console for errors
qm terminal 1001
```

### Disk still shows 2GB after resize

**Cause:** Resize done while VM was running

**Fix:**
```bash
# Stop VM
qm stop 1001

# Resize disk
qm resize 1001 scsi0 50G

# Start VM
qm start 1001

# Cloud-init will auto-expand filesystem on next boot
```

## Disaster Recovery: Rebuild Entire Cluster

**Complete cluster rebuild in under 10 minutes:**

```bash
# Step 1: Destroy all VMs using automation script
./destroy-cluster.sh --all

# Step 2: Recreate from scripts
./create-k8s-controlplane.sh
./create-k8s-workers.sh

# Step 3: Wait for cloud-init (all VMs in parallel)
sleep 90

# Step 4: Install Kubernetes
cd ../../ansible
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml

# Total time: ~10 minutes for full cluster rebuild
```

**Manual VM destruction (if destroy-cluster.sh unavailable):**
```bash
qm stop 1001 && qm destroy 1001 --purge  # Control plane
qm stop 2001 && qm destroy 2001 --purge  # Worker 1
qm stop 2002 && qm destroy 2002 --purge  # Worker 2
```

## Best Practices

**✅ DO:**
- Keep template updated with security patches
- Use ed25519 SSH keys (modern, secure)
- Verify checksums before creating templates
- Document any custom cloud-init configurations
- Test scripts in sequence on fresh Proxmox install
- Use destroy-cluster.sh for safe VM cleanup

**❌ DON'T:**
- Don't modify running VMs manually (treat as immutable)
- Don't use DHCP for Kubernetes nodes
- Don't skip checksum verification (security risk)
- Don't clone running VMs (stop them first)
- Don't forget to copy SSH keys before running scripts
- Don't use `qm destroy` directly (use destroy-cluster.sh instead)

## Adapting for Your Environment

**Different network subnet:**
```bash
# Edit scripts and change:
VM_GATEWAY="10.0.1.1"
BASE_IP="10.0.1"  # In create-k8s-workers.sh
```

**Different resource allocation:**
```bash
# Edit create-k8s-controlplane.sh:
VM_MEMORY=8192   # 8GB RAM
VM_CORES=4       # 4 vCPUs

# Edit create-k8s-workers.sh:
WORKERS["2001"]="k8s-worker-01|10.0.1.35|4|10240|200"
#                                        ^   ^     ^
#                                        |   |     └─ Disk (GB)
#                                        |   └─────── RAM (MB)
#                                        └───────────── vCPUs
```

**Add more workers:**
```bash
# Edit create-k8s-workers.sh:
declare -A WORKERS=(
  ["2001"]="k8s-worker-01|192.168.178.35|3|7168|100"
  ["2002"]="k8s-worker-02|192.168.178.36|3|7168|100"
  ["2003"]="k8s-worker-03|192.168.178.37|3|7168|100"  # Add this
  ["2004"]="k8s-worker-04|192.168.178.38|3|7168|100"  # And this
)

# Also update destroy-cluster.sh:
WORKER_IDS=(2001 2002 2003 2004)  # Add new VM IDs
```

## Complete Workflow Example

**First-time setup:**
```bash
# 1. Create template (once)
./create-template.sh

# 2. Create cluster VMs
./create-k8s-controlplane.sh
./create-k8s-workers.sh

# 3. Verify all VMs are accessible
ssh mahmood@192.168.178.34 'hostname'  # k8s-cp-01
ssh mahmood@192.168.178.35 'hostname'  # k8s-worker-01
ssh mahmood@192.168.178.36 'hostname'  # k8s-worker-02

# 4. Install Kubernetes
cd ../../ansible
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml
```

**Rebuild cluster for testing:**
```bash
# 1. Destroy existing cluster
./destroy-cluster.sh --all

# 2. Recreate (template still exists)
./create-k8s-controlplane.sh
./create-k8s-workers.sh

# 3. Reinstall Kubernetes
cd ../../ansible
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml

# Total time: ~5 minutes
```

## Next Steps

After VMs are created and verified:

1. ✅ **Install Kubernetes:** `cd ../../ansible && ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml`
2. ✅ **Configure kubectl:** `scp mahmood@192.168.178.34:~/.kube/config ~/.kube/config`
3. ✅ **Deploy platform services:** See `../../../platform/` directory
4. ✅ **Setup monitoring:** See `../../../observability/` directory

## References

- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)

## Related Documentation

- [Proxmox Setup](../README.md) - Hypervisor installation and configuration
- [Ansible Automation](../../ansible/README.md) - Kubernetes installation playbooks
- [Architecture Overview](../../../docs/architecture.md) - Complete homelab design
