# Ansible Automation for Kubernetes Cluster

## Overview

This directory contains Ansible automation for deploying a production-grade 3-node Kubernetes cluster using kubeadm, containerd, and Calico CNI.

**What 'install-kubernetes.yml' playbook automates:**
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

## Prerequisites

### On Control/Local Machine (WSL/Linux)
```bash
# Install Ansible
sudo apt update
sudo apt install ansible -y

# Verify installation
ansible --version
```

### On Target Nodes
- Ubuntu 24.04 LTS (cloud-init configured)
- SSH access with sudo privileges
- Static IP addresses assigned

## Usage

### 1. Configure Inventory

Create `inventory.ini` with your node IPs:
```ini
[control_plane]
k8s-cp-01 ansible_host=192.168.1.10

[workers]
k8s-worker-01 ansible_host=192.168.1.11
k8s-worker-02 ansible_host=192.168.1.12

[k8s_cluster:children]
control_plane
workers

[k8s_cluster:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_rsa
```

### 2. Test Connectivity
```bash
ansible -i inventory.ini all -m ping
```

Expected output:
```
k8s-cp-01     | SUCCESS => {"ping": "pong"}
k8s-worker-01 | SUCCESS => {"ping": "pong"}
k8s-worker-02 | SUCCESS => {"ping": "pong"}
```

### 3. Run the Playbook

**Full installation:**
```bash
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml
```

**Run specific sections using tags:**
```bash
# Only system preparation
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags preflight

# Only containerd installation
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags containerd

# Only worker join
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags workers

# Verification only
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --tags verify
```

### 4. Access the Cluster

After successful installation:
```bash
# Copy kubeconfig from control plane to your local machine
scp ubuntu@192.168.1.10:~/.kube/config ~/.kube/config

# Verify cluster access
kubectl get nodes
kubectl get pods -A
```

## Configuration Variables

Edit `group_vars/all.yml` to customize:
```yaml
# Kubernetes version
kubernetes_version: "1.31"

# Network configuration
pod_network_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"
apiserver_advertise_address: "192.168.1.10"

# CNI plugin
cni_plugin: "calico"
calico_manifest_url: "https://docs.projectcalico.org/manifests/calico.yaml"

# User configuration
kubernetes_user: "ubuntu"
kubernetes_user_home: "/home/ubuntu"
```

## [Troubleshooting](troubleshooting.md)

## Post-Installation

After cluster is running:

1. **Deploy storage (Phase 4):** Longhorn for persistent volumes
2. **Deploy ingress (Phase 4):** ingress-nginx for external access
3. **Deploy GitOps (Phase 4):** ArgoCD for declarative deployments
4. **Deploy observability (Phase 5):** Prometheus, Grafana, Loki

## CKA Exam Notes

**Key concepts demonstrated:**
- ✅ Container runtime configuration (systemd cgroup driver)
- ✅ Network plugin installation and troubleshooting
- ✅ Cluster bootstrapping with kubeadm
- ✅ Certificate and token management
- ✅ Component health verification

**Commands to memorize for exam:**
Practice these after installation:

1. **Generate new bootstrap token**
```bash
   kubeadm token create --print-join-command
```

2. **Check control plane component logs**
```bash
  # Static pod logs
  kubectl logs -n kube-system kube-apiserver-k8s-cp-01
   
  # Via systemd (kubelet)
  journalctl -u kubelet -f
```

3. **Backup etcd**
```bash
  sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

4. **Drain and cordon nodes**
```bash
  kubectl drain k8s-worker-01 --ignore-daemonsets
  kubectl cordon k8s-worker-02
```

5. **View certificates**
```bash
   sudo kubeadm certs check-expiration
```

## Related Documentation

- [Architecture Overview](../../docs/architecture.md)

**Status:** Ready for execution  
**Last Updated:** 2026-01-05  
**Estimated Duration:** 30-45 minutes
