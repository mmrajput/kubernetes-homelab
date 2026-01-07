# Kubernetes Homelab (Production-Grade Learning Environment)

[![Kubernetes](https://img.shields.io/badge/kubernetes-v1.31-blue.svg)](https://kubernetes.io/)
[![Proxmox](https://img.shields.io/badge/proxmox-8.x-orange.svg)](https://www.proxmox.com/)
[![Ubuntu](https://img.shields.io/badge/ubuntu-24.04_LTS-purple.svg)](https://ubuntu.com/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Blog](https://img.shields.io/badge/blog-technical_posts-blue.svg)](https://github.com/mmrajput/blog)

> **A 3-node Kubernetes cluster built on Proxmox for hands-on DevOps/Platform Engineering skill development**

---

## 🎯 Project Goals
This homelab project demonstrates production-grade Kubernetes infrastructure deployment on bare-metal virtualization. Built specifically to:
        - Prepare for CKA certification with hands-on practice.
        - Build production-grade Kubernetes skills for Platform Engineering roles.
        - Learn GitOps, observability and cloud-native patterns.

---

## 📋 Table of Contents

- [Architecture](#architecture)
- [Current Status](#current-status)
- [Repository Structure](#repository-structure)
- [Quick Start](#️quick-start)
- [Contributing](#contributing)
- [License](#license)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Physical Layer                           │
│  Beelink SER5 Pro (AMD Ryzen 5 5500U, 32GB RAM, 500GB NVMe) │
└─────────────────────────────────────────────────────────────┘
                            │
                    ┌───────┴───────┐
                    │  Proxmox VE   │
                    │  Hypervisor   │
                    └───────┬───────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
┌───────▼────────┐  ┌───────▼──────┐  ┌─────────▼──────┐
│  k8s-master-1  │  │ k8s-worker-1 │  │ k8s-worker-2   │
│  Ubuntu 24.04  │  │ Ubuntu 24.04 │  │ Ubuntu 24.04   │
│  6GB | 3vCPU   │  │ 7GB | 3vCPU  │  │ 7GB | 3vCPU    │
└────────────────┘  └──────────────┘  └────────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
                  ┌─────────▼─────────┐
                  │  Kubernetes CNI   │
                  │     (Calico)      │
                  └───────────────────┘
```

---

## 🚀 Current Status
- [x] Phase 0: Planning & Architecture
- [x] Phase 1: Proxmox Foundation Setup  
- [x] Phase 2: VM Creation & Configuration
- [x] Phase 3: Kubernetes Cluster Bootstrap
- [ ] Phase 4: GitOps & Platform Services (In Progress)
- [ ] Phase 5: Observability Stack
- [ ] Phase 6: Application Deployment

---

## 📁 Repository Structure

```ini
├── docs/           # Architecture, setup guides, troubleshooting
├── infra/          # Infrastructure-as-Code (Proxmox VMs, K8s bootstrap)
├── platform/       # Core platform services (ArgoCD, ingress, storage)
├── observability/  # Monitoring stack (Prometheus, Grafana, Loki)
├── apps/           # Demo applications
└── scripts/        # Automation and helper scripts
```

---

## 🔧 Infrastructure Automation

This homelab uses **Ansible** for repeatable Kubernetes cluster deployment:
```
infra/
├── proxmox/       # VM template creation and management
├── ansible/       # Kubernetes cluster automation (kubeadm + Calico)
└── kubernetes/    # Post-installation configurations
```

**Key automation features:**
- One-command cluster deployment via Ansible playbook
- Idempotent operations (safe to re-run)
- CKA exam-aligned documentation in code comments
- Production-grade containerd and Calico configurations

See [infra/ansible/README.md](infra/ansible/README.md) for usage instructions.

---

## 🛠️ Quick Start
> TODOs

Prerequisites and step-by-step setup instructions in [docs/setup-guide.md](docs/setup-guide.md).

---

## 📚 Documentation
> TODOs
- [Architecture Details](docs/architecture.md) - Network topology, resource allocation
- [Setup Guide](docs/setup-guide.md) - Complete rebuild instructions
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

---

## 📝 Related Projects

- [homelab-learning-log](https://github.com/yourusername/homelab-learning-log) - Detailed learning journey and blog posts
- [cka-exam-prep](https://github.com/yourusername/cka-exam-prep) - CKA certification practice (planned)

---

## 🤝 Contributing

This is a personal learning project, but suggestions and feedback are welcome!

### Found an Issue?

- 🐛 [Report a bug](https://github.com/mmrajput/kubernetes-homelab-01/issues)
- 💡 [Suggest an improvement](https://github.com/mmrajput/kubernetes-homelab-01/issues)
- 📖 [Improve documentation](https://github.com/mmrajput/kubernetes-homelab-01/pulls)

### Want to Learn Together?

- ⭐ Star this repo if you find it helpful
- 🔔 Watch for updates as the project evolves
- 💬 Open discussions for questions or ideas

---

## 📄 License

MIT License - feel free to use this as reference for your own learning.

---

## 📫 Connect

- **Blog:** [Technical Blog](https://github.com/mmrajput/blog)
- **LinkedIn:** https://www.linkedin.com/in/mahmood-rajput/
- **Email:** mahmoodrajput.cloud@gmail.com

---

## 📊 Project Stats

![GitHub stars](https://img.shields.io/github/stars/mmrajput/kubernetes-homelab-01?style=social)
![GitHub forks](https://img.shields.io/github/forks/mmrajput/kubernetes-homelab-01?style=social)
![GitHub watchers](https://img.shields.io/github/watchers/mmrajput/kubernetes-homelab-01?style=social)

## References

- [Official kubeadm documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Calico installation guide](https://docs.tigera.io/calico/latest/getting-started/kubernetes/)
- [CKA Exam Curriculum](https://github.com/cncf/curriculum)
- [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) (manual installation for deep learning)

<p align="center">
  <strong>Built with ❤️ for learning and sharing knowledge</strong>
  <br>
  <sub>From Systems Analyst to Platform Engineer</sub>
</p>

**Last Updated:** 05 Jan 2026 

---

                                      Happy Learning! 🚀

---