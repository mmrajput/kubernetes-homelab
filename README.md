# Kubernetes Homelab - Production-Grade Platform Engineering

[![Kubernetes](https://img.shields.io/badge/kubernetes-v1.31-blue.svg)](https://kubernetes.io/)
[![Proxmox](https://img.shields.io/badge/proxmox-8.x-orange.svg)](https://www.proxmox.com/)
[![Ubuntu](https://img.shields.io/badge/ubuntu-24.04_LTS-purple.svg)](https://ubuntu.com/)
[![ArgoCD](https://img.shields.io/badge/argocd-gitops-green.svg)](https://argoproj.github.io/cd/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> **A production-grade 3-node Kubernetes platform built on Proxmox VE, demonstrating enterprise GitOps patterns, infrastructure automation, and platform engineering practices.**

---

## 🎯 Project Overview

This repository contains a fully operational Kubernetes platform running on bare-metal virtualization. The project demonstrates:

- **Infrastructure as Code** — Automated VM provisioning using Cloud-init and Kubernetes deployment via Ansible
- **GitOps Workflows** — ArgoCD with App-of-Apps pattern for declarative cluster management
- **Production Patterns** — Enterprise-grade architecture decisions documented via ADRs
- **Platform Engineering** — Self-service infrastructure with minimal manual intervention

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Physical Layer                              │
│      Beelink SER5 Pro (AMD Ryzen 5 5500U, 32GB RAM, 500GB NVMe)     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                          ┌─────────┴─────────┐
                          │   Proxmox VE 8.x  │
                          │    Hypervisor     │
                          └─────────┬─────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          │                         │                         │
  ┌───────▼────────┐      ┌─────────▼───────┐       ┌─────────▼───────┐
  │  k8s-cp-01     │      │  k8s-worker-01  │       │  k8s-worker-02  │
  │  Control Plane │      │     Worker      │       │     Worker      │
  │  Ubuntu 24.04  │      │  Ubuntu 24.04   │       │  Ubuntu 24.04   │
  │  6GB | 3 vCPU  │      │  7GB | 3 vCPU   │       │  7GB | 3 vCPU   │
  └────────────────┘      └─────────────────┘       └─────────────────┘
          │                         │                         │
          └─────────────────────────┼─────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │      Kubernetes v1.31         │
                    │         Calico CNI            │
                    └───────────────┬───────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
┌───────▼───────┐          ┌────────▼────────┐         ┌────────▼────────┐
│    ArgoCD     │          │  nginx-ingress  │         │  local-path     │
│   (GitOps)    │          │  (NodePort)     │         │  provisioner    │
│  App-of-Apps  │          │  30080/30443    │         │  (Storage)      │
└───────────────┘          └─────────────────┘         └─────────────────┘
```

### Network Topology

| Component | IP Address | Role |
|-----------|------------|------|
| Proxmox Host | 192.168.178.30 | Hypervisor |
| k8s-cp-01 | 192.168.178.34 | Control Plane |
| k8s-worker-01 | 192.168.178.35 | Worker Node |
| k8s-worker-02 | 192.168.178.36 | Worker Node |

### Access Points

| Service | URL | Method |
|---------|-----|--------|
| ArgoCD UI | `http://argocd.homelab.local:30080` | Ingress |
| Kubernetes API | `https://192.168.178.34:6443` | Direct |

---

## 📊 Current Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 0 | Architecture Design & Planning | ✅ Complete |
| Phase 1 | Development Environment (DevContainers) | ✅ Complete |
| Phase 2 | Proxmox Foundation | ✅ Complete |
| Phase 3 | VM Provisioning (Cloud-init) | ✅ Complete |
| Phase 4 | Kubernetes Cluster (kubeadm + Calico) | ✅ Complete |
| Phase 5 | GitOps & Platform Services (ArgoCD) | ✅ Complete |
| Phase 5.5 | First Test Application Deployment | 🔄 Current |
| Phase 6 | Observability Stack | ⏳ Planned |
| Phase 7 | Applications Layer | ⏳ Planned |
| Phase 8 | Distributed Storage (Longhorn) | ⏳ Planned |
| Phase 9 | Backup & Disaster Recovery | ⏳ Planned |
| Phase 10 | Security Hardening | ⏳ Planned |

---

## 📁 Repository Structure

```
kubernetes-homelab/
├── .config/                    # Tool configurations (k9s, helm)
├── .devcontainer/              # Isolated development environment
├── apps/                       # Application deployments
│   └── hello-world/            # Test application
├── docs/
│   ├── adr/                    # Architecture Decision Records
│   ├── architecture/           # Design documentation
│   ├── guides/                 # Setup and operational guides
│   └── runbooks/               # Operational procedures
├── infra/
│   ├── ansible/                # Kubernetes cluster automation
│   ├── kubernetes/             # Bootstrap configurations
│   └── proxmox/                # VM templates and scripts
├── observability/              # Monitoring stack (Phase 6)
├── platform/
│   ├── argocd/                 # GitOps configuration
│   │   ├── apps/               # ArgoCD Application manifests
│   │   ├── install/            # ArgoCD Helm values
│   │   └── root-app.yaml       # App-of-Apps root
│   └── nginx-ingress/          # Ingress controller config
├── resources/                  # Static assets
└── scripts/                    # Automation helpers
```

---

## 🔧 Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| Virtualization | Proxmox VE 8.x | Hypervisor |
| OS | Ubuntu 24.04 LTS | Node operating system |
| Container Runtime | containerd | CRI implementation |
| Kubernetes | v1.31.x (kubeadm) | Container orchestration |
| CNI | Calico | Pod networking & network policy |
| Storage | local-path-provisioner | Dynamic PV provisioning |
| GitOps | ArgoCD | Declarative continuous delivery |
| Ingress | nginx-ingress | HTTP routing (NodePort backend) |
| IaC | Ansible | Infrastructure automation |

---

## 🚀 Key Features

### GitOps with App-of-Apps Pattern

All platform services are managed declaratively through Git:

```
root-app (Bootstrap)
    └── watches: platform/argocd/apps/
        ├── argocd-app.yaml      → ArgoCD self-manages
        └── nginx-ingress-app.yaml → Ingress controller
```

**Workflow:** `git commit` → `git push` → ArgoCD syncs → Cluster updated

### Infrastructure Automation

Single-command cluster deployment:

```bash
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml
```

### Development Environment

Reproducible CLI environment via DevContainers with pinned tool versions:
- kubectl v1.31.4
- helm v3.16.3
- k9s v0.32.7
- argocd CLI

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [Architecture Decisions](docs/adr/) | ADRs explaining key technical choices |
| [Network Topology](docs/architecture/network-topology.md) | Network design and IP allocation |
| [Cluster Sizing](docs/architecture/cluster-sizing.md) | Resource allocation decisions |
| [Setup Guide](docs/guides/setup-guide.md) | Complete installation instructions |
| [DevContainer Guide](docs/guides/devcontainer-setup.md) | Development environment setup |
| [Troubleshooting](docs/guides/troubleshooting-guide.md) | Common issues and solutions |

---

## 🏭 Enterprise Pattern Mapping

This homelab implements patterns used in production environments:

| Homelab Implementation | Enterprise Equivalent |
|------------------------|----------------------|
| Proxmox VE | VMware vSphere / AWS EC2 |
| kubeadm cluster | EKS / AKS / GKE |
| Calico CNI | Cilium / AWS VPC CNI |
| local-path-provisioner | EBS CSI / Azure Disk |
| ArgoCD | ArgoCD / Flux CD |
| nginx-ingress + NodePort | ALB / Cloud Load Balancer |
| /etc/hosts DNS | Route53 / Cloud DNS |

---

## 🛠️ Quick Start

### Prerequisites

- Git
- VS Code with Dev Containers extension (optional)
- SSH access to Proxmox host

### Clone and Setup

```bash
git clone https://github.com/mmrajput/kubernetes-homelab.git
cd kubernetes-homelab

# Open in VS Code with DevContainer
code .
# Select "Reopen in Container" when prompted

# Verify tools
./scripts/verify-tools.sh

# Configure kubectl (copy kubeconfig from control plane)
export KUBECONFIG=~/.kube/config
kubectl get nodes
```

### Access ArgoCD

```bash
# Add to /etc/hosts (Windows: C:\Windows\System32\drivers\etc\hosts)
192.168.178.34 argocd.homelab.local

# Get admin password
kubectl -n platform get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access UI
open http://argocd.homelab.local:30080
```

---

## 📈 Next Steps

### Near-term (Phase 6-7)
- [ ] Observability stack (Prometheus, Grafana, Loki)
- [ ] First production application deployment
- [ ] Secrets management evaluation

### Mid-term (Phase 8-9)
- [ ] Longhorn distributed storage
- [ ] Velero backup with Backblaze B2
- [ ] Disaster recovery procedures

### Long-term (Phase 10+)
- [ ] cert-manager with Let's Encrypt
- [ ] Network policies hardening
- [ ] Multi-cluster considerations

---

## 🤝 Contributing

This is a personal portfolio project demonstrating platform engineering skills. Feedback and suggestions are welcome:

- 🐛 [Report an issue](https://github.com/mmrajput/kubernetes-homelab/issues)
- 💡 [Suggest an improvement](https://github.com/mmrajput/kubernetes-homelab/issues)
- ⭐ Star this repo if you find it useful

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 📫 Connect

- **LinkedIn:** [linkedin.com/in/mahmood-rajput](https://www.linkedin.com/in/mahmood-rajput/)
- **Email:** mahmoodrajput.cloud@gmail.com
- **Blog:** [Technical Posts](https://mmrajput.github.io/blog/)

---

**Last Updated:** 24 January 2026
