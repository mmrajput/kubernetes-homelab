# Kubernetes Cluster Automation with Ansible

## Overview

Ansible automation for deploying a production-grade 3-node Kubernetes cluster using kubeadm, containerd, and Calico CNI.

**What `install-kubernetes.yml` automates:**

- System preparation (swap disable, kernel modules, sysctl)
- Container runtime installation (containerd with systemd cgroup)
- Kubernetes package installation (kubeadm, kubelet, kubectl)
- Control plane initialization
- Calico CNI deployment
- Worker node joining
- Cluster health verification

## Cluster Architecture

```
Control Plane (k8s-cp-01):
├── kube-apiserver
├── kube-controller-manager
├── kube-scheduler
├── etcd
└── kubelet

Worker Nodes (k8s-worker-01, k8s-worker-02):
└── kubelet

┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   k8s-cp-01     │     │ k8s-worker-01   │     │ k8s-worker-02   │
│  Control Plane  │     │     Worker      │     │     Worker      │
│ 192.168.178.34  │     │ 192.168.178.35  │     │ 192.168.178.36  │
│   3 vCPU / 6GB  │     │  3 vCPU / 7GB   │     │  3 vCPU / 7GB   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

| Component | Value |
|-----------|-------|
| Kubernetes Version | 1.31.x |
| Container Runtime | containerd |
| CNI Plugin | Calico |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |

## Directory Structure

```
infra/ansible/
├── README.md                    # This file
├── inventory.ini                # Node definitions (user-created)
├── group_vars/
│   └── all.yml                  # Cluster-wide variables
├── playbooks/
│   └── install-kubernetes.yml   # Main installation playbook
└── troubleshooting.md           # Common issues and solutions
```

## Prerequisites

**On target nodes (Kubernetes VMs):**
- Ubuntu 24.04 LTS (via cloud-init)
- SSH access with sudo privileges
- Static IPs assigned
- Internet access for package downloads

**If using Proxmox VM automation scripts, prerequisites are already met.**

## Usage

### 1. Configure Inventory

Create `inventory.ini`:

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

```bash
cd infra/ansible

# Verify Ansible can reach all nodes
ansible -i inventory.ini all -m ping

# Expected output:
# k8s-cp-01     | SUCCESS => {"ping": "pong"}
# k8s-worker-01 | SUCCESS => {"ping": "pong"}
# k8s-worker-02 | SUCCESS => {"ping": "pong"}
```

### 3. Review Configuration

```bash
# Verify group_vars/all.yml matches your setup
cat group_vars/all.yml
```

### 4. Run the Playbook

**Full installation:**

```bash
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml

# Duration: ~15-20 minutes
```

**Run specific sections:**

```bash
# System preparation only
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags preflight

# Containerd installation
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags containerd

# Kubernetes packages
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags kubernetes-packages

# Control plane initialization
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags control-plane

# CNI deployment
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags cni

# Worker joining
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags workers

# Verification
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags verify
```

**Dry run:**

```bash
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --check
```

### 5. Access the Cluster

```bash
# Copy kubeconfig from control plane
scp mahmood@192.168.178.34:~/.kube/config ~/.kube/config

# Verify cluster access
kubectl get nodes

# Expected output:
# NAME            STATUS   ROLES           AGE   VERSION
# k8s-cp-01       Ready    control-plane   5m    v1.31.x
# k8s-worker-01   Ready    <none>          3m    v1.31.x
# k8s-worker-02   Ready    <none>          3m    v1.31.x
```

## Configuration Variables

Key variables in `group_vars/all.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `kubernetes_version` | 1.31 | Kubernetes minor version |
| `pod_network_cidr` | 10.244.0.0/16 | Pod network range |
| `service_cidr` | 10.96.0.0/12 | Service network range |
| `apiserver_advertise_address` | 192.168.178.34 | Control plane IP |
| `kubernetes_user` | mahmood | SSH user for kubeconfig |
| `cni_plugin` | calico | CNI plugin choice |

## Playbook Behavior

### Idempotency

The playbook is safe to run multiple times:

- Checks if cluster is initialized before `kubeadm init`
- Verifies CNI before deploying
- Checks worker join status before `kubeadm join`

### What Gets Modified

**All nodes:**
- `/etc/fstab` — Swap disabled
- `/etc/modules-load.d/k8s.conf` — Kernel modules
- `/etc/sysctl.d/k8s.conf` — Network parameters
- `/etc/containerd/config.toml` — Container runtime config
- Packages: containerd, kubeadm, kubelet, kubectl

**Control plane:**
- `/etc/kubernetes/` — Certificates and configs
- `~/.kube/config` — kubectl configuration

## Common Operations

### Adding a Worker Node

```bash
# 1. Update inventory.ini with new node
[workers]
k8s-worker-01 ansible_host=192.168.178.35
k8s-worker-02 ansible_host=192.168.178.36
k8s-worker-03 ansible_host=192.168.178.37  # New

# 2. Run worker tag for new node only
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml \
  --tags workers --limit k8s-worker-03
```

### Cluster Rebuild

```bash
# 1. Destroy VMs
cd infra/proxmox/vm-templates
./destroy-cluster.sh --all

# 2. Recreate VMs
./create-k8s-controlplane.sh
./create-k8s-workers.sh

# 3. Reinstall Kubernetes
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml

# Total time: ~10 minutes
```

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues.

**Quick checks:**

```bash
# SSH connectivity
ssh -i ~/.ssh/id_ed25519_homelab mahmood@192.168.178.34

# Ansible facts
ansible -i inventory.ini all -m setup -a "filter=ansible_hostname"

# Kubelet status (on node)
sudo systemctl status kubelet
sudo journalctl -u kubelet --since "10 minutes ago"
```

## Related Documentation

- [Proxmox VM Provisioning](../proxmox/README.md)
- [Architecture Decisions](../../docs/adr/)
- [Network Topology](../../docs/architecture/network-topology.md)

---

**Last Updated:** January 2026
