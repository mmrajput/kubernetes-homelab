# Phase 3: Kubernetes Cluster Bootstrap using Ansible

## Overview

This directory contains Ansible automation for deploying a production-grade 3-node Kubernetes cluster using kubeadm, containerd, and Calico CNI.

**What the `install-kubernetes.yml` playbook automates:**
- ✅ System preparation (swap disable, kernel modules, sysctl parameters)
- ✅ Container runtime installation (containerd with systemd cgroup driver)
- ✅ Kubernetes package installation (kubeadm, kubelet, kubectl)
- ✅ Control plane initialization with kubeadm
- ✅ Calico CNI plugin deployment
- ✅ Worker node joining
- ✅ Cluster health verification

**CKA Exam Alignment:**
This playbook demonstrates knowledge of CKA exam domain "Cluster Architecture, Installation & Configuration (25%)" with detailed comments explaining each step.

## Architecture

```
Control Plane (k8s-cp-01):
├── kube-apiserver
├── kube-controller-manager
├── kube-scheduler
├── etcd
└── kubelet

Worker Nodes (k8s-worker-01, k8s-worker-02):
└── kubelet
```

**Cluster Specifications:**
- **Kubernetes Version:** 1.31 (configurable in `group_vars/all.yml`)
- **Container Runtime:** containerd (CRI-compatible)
- **CNI Plugin:** Calico
- **Pod Network CIDR:** 10.244.0.0/16
- **Service CIDR:** 10.96.0.0/12

**Node Resources:**

| Node | IP Address | vCPUs | RAM | Role |
|------|------------|-------|-----|------|
| k8s-cp-01 | 192.168.178.34 | 3 | 6GB | Control Plane |
| k8s-worker-01 | 192.168.178.35 | 3 | 7GB | Worker |
| k8s-worker-02 | 192.168.178.36 | 3 | 7GB | Worker |

## Prerequisites

### On Control Machine (Your Workstation/WSL)
```bash
# Install Ansible (if not already installed)
sudo apt update
sudo apt install ansible -y

# Verify installation
ansible --version
# Should show: ansible [core 2.15+]
```

### On Target Nodes (Kubernetes VMs)
- ✅ Ubuntu 24.04 LTS installed via cloud-init
- ✅ SSH access with sudo privileges
- ✅ Static IP addresses assigned (192.168.178.34-36)
- ✅ Hostname properly set (k8s-cp-01, k8s-worker-01, k8s-worker-02)
- ✅ All nodes can reach internet for package downloads

**If you used the Proxmox VM automation scripts, all prerequisites are already met.**

## Directory Structure

```
infra/ansible/
├── README.md                          # This file
├── inventory.ini                      # Cluster node definitions (Created by user, not included in Git repo.)
├── group_vars/
│   └── all.yml                       # Cluster-wide variables
├── playbooks/
│   └── install-kubernetes.yml        # Main installation playbook
├── roles/                            # Future: modular playbooks
└── troubleshooting.md                # Common issues and solutions
```

## Usage

### 1. Configure Inventory

**Your `inventory.ini` should contain:**

```ini
[control_plane]
k8s-cp-01 ansible_host=192.168.178.34

[workers]
k8s-worker-01 ansible_host=192.168.178.35
k8s-worker-02 ansible_host=192.168.178.36

[k8s_cluster:children]
control_plane
workers

[k8s_cluster:vars]
ansible_user=mahmood
ansible_ssh_private_key_file=~/.ssh/id_ed25519_homelab
```

**Important:** Update these values if:
- You used a different username during VM creation
- Your SSH key has a different name
- You're using a different subnet

### 2. Test Connectivity

**Before running the playbook, verify Ansible can reach all nodes:**

```bash
# From your workstation (where Ansible is installed)
cd ~/kubernetes-homelab/infra/ansible

# Test ping module
ansible -i inventory.ini all -m ping

# Expected output:
# k8s-cp-01     | SUCCESS => {"changed": false, "ping": "pong"}
# k8s-worker-01 | SUCCESS => {"changed": false, "ping": "pong"}
# k8s-worker-02 | SUCCESS => {"changed": false, "ping": "pong"}
```

**If ping fails:**
```bash
# Check SSH connectivity manually
ssh -i ~/.ssh/id_ed25519_homelab mahmood@192.168.178.34

# Verify SSH key permissions
chmod 600 ~/.ssh/id_ed25519_homelab
chmod 644 ~/.ssh/id_ed25519_homelab.pub

# Test Ansible can gather facts
ansible -i inventory.ini all -m setup -a "filter=ansible_hostname"
```

### 3. Review Configuration

**Before installation, review `group_vars/all.yml`:**

```bash
# Check current configuration
cat group_vars/all.yml

# Verify these critical values match your setup:
# - kubernetes_version: "1.31"
# - pod_network_cidr: "10.244.0.0/16"
# - service_cidr: "10.96.0.0/12"
# - apiserver_advertise_address: "192.168.178.34"
# - kubernetes_user: "mahmood"
```

### 4. Run the Playbook

**Full installation (recommended for first run):**

```bash
# Run complete installation
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml

# Estimated duration: 15-20 minutes
# What happens:
# - Pre-flight checks on all nodes (~2 min)
# - Install containerd on all nodes (~3 min)
# - Install Kubernetes packages (~5 min)
# - Initialize control plane (~2 min)
# - Deploy Calico CNI (~3 min)
# - Join worker nodes (~2 min)
# - Verify cluster health (~1 min)
```

**Run specific sections using tags:**

```bash
# Only system preparation (useful for testing)
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags preflight

# Only containerd installation
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags containerd

# Only Kubernetes package installation
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags kubernetes-packages

# Initialize control plane only
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags control-plane

# Install CNI only
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags cni

# Join workers only (if control plane already initialized)
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags workers

# Verification only
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags verify
```

**Dry run (check without making changes):**

```bash
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --check
```

### 5. Access the Cluster

**After successful installation:**

```bash
# Option 1: Copy kubeconfig from control plane to your workstation
scp mahmood@192.168.178.34:~/.kube/config ~/.kube/config

# Option 2: SSH and merge into existing config
# (Use this if you already have other clusters configured)
ssh mahmood@192.168.178.34 'cat ~/.kube/config' > /tmp/k8s-homelab-config
KUBECONFIG=~/.kube/config:/tmp/k8s-homelab-config kubectl config view --flatten > ~/.kube/config.new
mv ~/.kube/config.new ~/.kube/config

# Verify cluster access
kubectl get nodes

# Expected output:
# NAME            STATUS   ROLES           AGE   VERSION
# k8s-cp-01       Ready    control-plane   5m    v1.31.x
# k8s-worker-01   Ready    <none>          3m    v1.31.x
# k8s-worker-02   Ready    <none>          3m    v1.31.x

# Check all pods
kubectl get pods -A

# Should see:
# - kube-system pods (apiserver, controller-manager, scheduler, etcd)
# - calico-system pods (calico-node, calico-kube-controllers)
# All should be Running or Completed
```

**Set context name for clarity:**

```bash
# Rename context to something memorable
kubectl config rename-context kubernetes-admin@kubernetes homelab

# Verify
kubectl config get-contexts
```

## Configuration Variables

Edit `group_vars/all.yml` to customize:

```yaml
# Kubernetes version (major.minor only, not patch)
kubernetes_version: "1.31"

# Network configuration
pod_network_cidr: "10.244.0.0/16"      # Must match Calico config
service_cidr: "10.96.0.0/12"           # Default Kubernetes service range
apiserver_advertise_address: "192.168.178.34"  # Control plane IP

# CNI plugin
cni_plugin: "calico"
calico_manifest_url: "https://docs.projectcalico.org/manifests/calico.yaml"

# User configuration
kubernetes_user: "mahmood"             # Your SSH username
kubernetes_user_home: "/home/mahmood"  # User home directory

# System configuration
kernel_modules:
  - overlay
  - br_netfilter

sysctl_config:
  net.bridge.bridge-nf-call-iptables: 1
  net.bridge.bridge-nf-call-ip6tables: 1
  net.ipv4.ip_forward: 1

# Containerd configuration
containerd_config_dir: "/etc/containerd"

# Additional kubeadm init arguments (optional)
kubeadm_init_extra_args: ""
```

## Playbook Behavior

### Idempotency

The playbook is designed to be idempotent (safe to run multiple times):

- ✅ Checks if cluster is already initialized before running `kubeadm init`
- ✅ Verifies Calico is installed before deploying
- ✅ Checks if workers already joined before running `kubeadm join`
- ✅ Uses `changed_when: false` for read-only tasks

**You can safely re-run the entire playbook** without breaking the cluster.

### Error Handling

The playbook includes error handling for common issues:

- ⚠️ Stops if swap is still enabled after disable
- ⚠️ Fails if containerd doesn't start properly
- ⚠️ Verifies all system pods are running before completion
- ⚠️ Provides detailed output for troubleshooting

### What Gets Modified

**On all nodes:**
- `/etc/fstab` - Swap entries removed/commented
- `/etc/modules-load.d/k8s.conf` - Kernel modules
- `/etc/sysctl.d/k8s.conf` - Network parameters
- `/etc/containerd/config.toml` - Containerd configuration
- `/etc/apt/sources.list.d/` - Kubernetes repository
- Installed packages: containerd, kubeadm, kubelet, kubectl

**On control plane:**
- `/etc/kubernetes/` - Cluster certificates and configs
- `/etc/kubernetes/manifests/` - Static pod definitions
- `~/.kube/config` - kubectl configuration for user

**On workers:**
- `/etc/kubernetes/kubelet.conf` - Worker authentication

## Troubleshooting

For detailed troubleshooting, see [troubleshooting.md](troubleshooting.md).

## Next Steps

After cluster is running successfully:

### Phase 4: Platform Services
1. **Storage:** Deploy Longhorn for persistent volumes
2. **Ingress:** Deploy ingress-nginx for external access
3. **GitOps:** Deploy ArgoCD for declarative deployments
4. **Load Balancing:** Deploy MetalLB for LoadBalancer services
5. **Certificates:** Deploy cert-manager for TLS automation

### Essential Commands for CKA Exam

**Practice these after your cluster is running:**

#### 1. Cluster Information
```bash
# Get cluster info
kubectl cluster-info
kubectl cluster-info dump  # Detailed diagnostic info

# Check component status
kubectl get componentstatuses  # Deprecated but may appear on exam

# Modern way to check control plane health
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
```

#### 2. Node Management
```bash
# List nodes with details
kubectl get nodes -o wide

# Describe node (shows capacity, conditions, pods)
kubectl describe node k8s-worker-01

# Drain node (for maintenance)
kubectl drain k8s-worker-01 --ignore-daemonsets --delete-emptydir-data

# Cordon node (prevent new pods)
kubectl cordon k8s-worker-02

# Uncordon node
kubectl uncordon k8s-worker-02
```

#### 3. Certificate Management
```bash
# Check certificate expiration
sudo kubeadm certs check-expiration

# Renew certificates
sudo kubeadm certs renew all

# View certificate details
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout
```

#### 4. Token Management
```bash
# List current tokens
sudo kubeadm token list

# Create new bootstrap token
sudo kubeadm token create --print-join-command

# Create token with custom TTL
sudo kubeadm token create --ttl 24h
```

#### 5. Etcd Backup & Restore
```bash
# Backup etcd
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
sudo ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db

# Restore etcd (advanced - practice in test environment)
sudo ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --data-dir=/var/lib/etcd-backup
```

#### 6. Component Logs
```bash
# Control plane component logs (static pods)
kubectl logs -n kube-system kube-apiserver-k8s-cp-01
kubectl logs -n kube-system kube-controller-manager-k8s-cp-01
kubectl logs -n kube-system kube-scheduler-k8s-cp-01
kubectl logs -n kube-system etcd-k8s-cp-01

# Kubelet logs (via systemd)
sudo journalctl -u kubelet -f        # Follow
sudo journalctl -u kubelet --since "10 minutes ago"

# Containerd logs
sudo journalctl -u containerd -f
```

#### 7. Network Troubleshooting
```bash
# Check CNI plugin status
kubectl get pods -n kube-system -l k8s-app=calico-node

# Test pod-to-pod connectivity
kubectl run test-pod --image=nicolaka/netshoot -it --rm -- bash
# Inside pod: ping <other-pod-ip>

# Check service endpoints
kubectl get endpoints

# View network policies
kubectl get networkpolicies -A
```

## Cluster Rebuild Workflow

**Complete cluster rebuild process:**

```bash
# 1. Destroy existing cluster VMs
cd ~/kubernetes-homelab/infra/proxmox/vm-templates
./destroy-cluster.sh --all

# 2. Recreate VMs from template
./create-k8s-controlplane.sh
./create-k8s-workers.sh

# 3. Wait for cloud-init (handled by scripts)
# ~90 seconds

# 4. Reinstall Kubernetes
cd ~/kubernetes-homelab/infra/ansible
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml

# 5. Verify cluster
kubectl get nodes
kubectl get pods -A

# Total time: ~10 minutes from destroy to running cluster
```

## Related Documentation

- [Proxmox Setup](../proxmox/README.md) - Hypervisor and VM provisioning
- [VM Templates](../proxmox/vm-templates/README.md) - Automated VM creation
- [Architecture Overview](../../docs/architecture.md) - Complete homelab design
- [Network Topology](../../docs/network-topology.md) - Network configuration
- [Troubleshooting Guide](troubleshooting.md) - Ansible-specific issues

## Maintenance

### Updating Kubernetes Version

```bash
# 1. Update group_vars/all.yml
kubernetes_version: "1.32"  # Change to desired version

# 2. Re-run playbook (handles upgrades)
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml

# Note: This installs new packages but doesn't upgrade control plane
# Control plane upgrades require kubeadm upgrade commands (not automated)
```

### Adding New Worker Nodes

```bash
# 1. Create new VM (e.g., k8s-worker-03)
cd ../proxmox/vm-templates
# Edit create-k8s-workers.sh to add worker-03

# 2. Update inventory.ini
[workers]
k8s-worker-01 ansible_host=192.168.178.35
k8s-worker-02 ansible_host=192.168.178.36
k8s-worker-03 ansible_host=192.168.178.37  # Add this

# 3. Run worker join tag
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags workers --limit k8s-worker-03
```

---

**Status:** Production-ready  
**Last Updated:** 2026-01-07  
**Playbook Version:** 1.0  
**Estimated Install Duration:** 15-20 minutes
