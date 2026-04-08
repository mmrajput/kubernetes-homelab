# Kubernetes Homelab — Platform Engineering Foundations

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE_8.x-E57000?logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Grafana-Dashboards-F46800?logo=grafana&logoColor=white)](https://grafana.com/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel_·_Access-F38020?logo=cloudflare&logoColor=white)](https://www.cloudflare.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> A 3-node Kubernetes homelab on Proxmox VE — kubeadm, Calico, ArgoCD, full observability, secrets management, identity, and stateful workloads.

---

## What's Next

This repo is the **foundation**. The next iteration — [**kubernetes-platform-engineering**](https://github.com/mmrajput/kubernetes-platform-engineering) — rebuilds the platform with enterprise-grade tooling:

- **Talos Linux** (immutable OS, no SSH)
- **Cilium** with eBPF, kube-proxy replacement, and Gateway API
- **SPIFFE/SPIRE** for workload identity
- **vCluster** for staging/production isolation
- **ArgoCD Hub** multi-cluster GitOps

---

## Architecture

![Platform Architecture](resources/images/platform-architecture.png)

### Legends
- Grey solid                User request traffic (Cloudflare → ingress → workload)
- Grey dashed               Backup and DR flows (Velero → MinIO → rclone → OneDrive)
- Blue dashed               GitOps reconciliation (GitHub → ArgoCD → cluster)
- Purple dashed             TLS certificate issuance and SSO authentication
- Red dashed                Secret injection (Vault → ESO → workloads)
- Green dashed              Metrics scraping and log shipping (Promtail → Loki)
- Green solid               Dashboard query flows (Grafana → Prometheus / Loki)
---

The diagram above illustrates the full platform architecture of the Kubernetes Homelab, deployed on a three-node kubeadm v1.31 cluster with Calico CNI. The platform is organised into six functional concern groups, all managed declaratively via GitOps.

### External Layer
The platform engineer interacts with the cluster exclusively through Git. Code changes are pushed to GitHub (github.com/mmrajput), which triggers the CI/CD pipeline. All external access to cluster services is routed through Cloudflare Tunnel / DNS, providing secure ingress without exposing ports directly to the internet. Cloudflare also handles DNS-01 certificate challenges for TLS automation.

### Networking · TLS · GitOps managed
ingress-nginx serves as the cluster ingress controller, routing external traffic to internal services. cert-manager, integrated with Cloudflare DNS-01, automates TLS certificate issuance and renewal for all exposed endpoints. This layer is fully GitOps managed.

### CI/CD · GitOps managed
ARC (Actions Runner Controller) provides self-hosted GitHub Actions runners inside the cluster, operating in webhook-based scale-to-zero mode. ArgoCD operates in poll-based mode, continuously reconciling cluster state against the Git repository. ARC runners pull upstream images from Docker Hub, scan them with Trivy, mirror them to ghcr.io via crane, and update the pinned image tag in the Git values file. ArgoCD detects the tag change and syncs the cluster — no custom images are built.

### Workloads · GitOps managed
Nextcloud is the primary platform workload, deployed for sovereign file sharing. It connects to the data/storage layer via Longhorn for persistent volume storage and to the security layer for SSO via Keycloak. Nextcloud exercises all platform layers simultaneously: storage, identity, secrets, observability, backup, and networking.

### Data · Storage · Backup · GitOps managed
This is the most interconnected layer of the platform:

Longhorn v1.7.2 (RF=2) is the default StorageClass, providing replicated block storage across worker nodes.
CloudNativePG (CNPG) manages PostgreSQL clusters for stateful workloads. It ships WAL archives continuously to MinIO via Barman, enabling point-in-time recovery.
MinIO (S3-compatible) serves as the central object store, backing Loki log storage, Velero backup storage, and CNPG WAL archiving.
Velero handles filesystem-level backup of persistent volumes (via Kopia as the backup uploader), storing snapshots in MinIO.
Redis provides caching and file-locking for Nextcloud.
A scheduled CronJob runs rclone to sync MinIO data offsite to OneDrive, providing a 3-2-1 backup posture with an offsite DR copy.

### Security · Identity · GitOps managed

HashiCorp Vault (KV v2) is the secrets backend, storing all platform secrets under component-namespaced paths.
External Secrets Operator (ESO) bridges Vault and Kubernetes, synchronising secrets into the appropriate namespaces as native Kubernetes Secret objects.
Keycloak 26 (SSO / OIDC) provides centralised identity for the platform, with SSO integrated across ArgoCD, Grafana, and Nextcloud via the homelab realm.

### Observability · GitOps managed

Prometheus & Alertmanager scrape metrics from all platform components and manage alerting rules.
Grafana visualises metrics from Prometheus and log data from Loki on unified dashboards.
Loki aggregates logs from across the cluster, backed by MinIO for durable log chunk storage.
Promtail (deployed as a DaemonSet) runs on every node, collecting and shipping container and system logs to Loki.

### Data Flow Summary
Traffic enters via Cloudflare → ingress-nginx → workloads. Secrets flow from Vault → ESO → Kubernetes Secrets → workloads. Persistent data is stored on Longhorn, with databases managed by CNPG writing WAL to MinIO. Backups flow from workloads → Velero (Kopia) → MinIO → rclone → OneDrive. Metrics flow from all components → Prometheus → Grafana. Logs flow from all nodes → Promtail → Loki (MinIO-backed) → Grafana.
---

## Current Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 0 | Architecture Design & Planning | ✅ Complete |
| Phase 1 | Development Environment (DevContainers) | ✅ Complete |
| Phase 2 | Virtualization Foundation (Proxmox VE) | ✅ Complete |
| Phase 3 | VM Provisioning (cloud-init + Ansible) | ✅ Complete |
| Phase 4 | Kubernetes Cluster (kubeadm + Calico) | ✅ Complete |
| Phase 5 | GitOps & Platform Services (ArgoCD) | ✅ Complete |
| Phase 6 | Observability Stack (Prometheus + Loki + Grafana) | ✅ Complete |
| Phase 7 | Security Hardening (cert-manager + NetworkPolicies + Vault + ESO) | ✅ Complete |
| Phase 8 | Storage & Backup (Longhorn + MinIO + Velero) | ✅ Complete |
| Phase 9 | Identity & Stateful Workloads (Keycloak + CloudNativePG + Nextcloud) | ✅ Complete |
| Phase 10 | CI/CD Pipeline (ARC + GitHub Actions) | ✅ Complete |

---

## Platform Stack

| Layer | Technology |
|-------|------------|
| Hypervisor | Proxmox VE 8.x |
| OS | Ubuntu 24.04 LTS · cloud-init |
| Kubernetes | v1.31 · kubeadm · 1 control plane · 2 workers |
| CNI | Calico |
| GitOps | ArgoCD (App-of-Apps) |
| Ingress | nginx-ingress · Cloudflare Tunnel |
| Observability | Prometheus · Grafana · Loki · Promtail |
| Security | cert-manager · Vault · External Secrets Operator · Falco |
| Identity | Keycloak · CloudNativePG |
| Storage | Longhorn · MinIO · Velero |
| CI/CD | GitHub Actions ARC · ghcr.io |
| Workloads | Nextcloud · Homepage |

---

## Repository Structure

```
bootstrap/namespaces/    # One-time namespace setup (kubectl apply, not ArgoCD)
platform/
  argocd/               # Root app + AppSets per category
  networking/           # cert-manager, nginx-ingress, NetworkPolicies
  security/             # Vault, Keycloak, External Secrets
  data/                 # CNPG clusters, Longhorn, MinIO, Velero, rclone
  observability/        # Prometheus, Grafana, Loki, Promtail
  ci-cd/                # ARC systems + runners
workloads/              # Helm values per app (staging / production)
infra/                  # Ansible + Proxmox scripts
docs/                   # ADRs, guides, runbooks, reference
scripts/                # Dev shell, diagrams, helpers
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Reproduction Guide](docs/guides/homelab-reproduction-guide.md) | End-to-end guide to reproduce this homelab from scratch |
| [Platform Inventory](docs/reference/platform-inventory.md) | Service endpoints, ArgoCD app inventory |
| [Workload Onboarding](docs/reference/workload-onboarding.md) | Step-by-step guide for adding workloads |
| [Data Layer](docs/reference/data-layer.md) | CNPG, Vault, ESO secrets inventory |
| [Network Topology](docs/architecture/network-topology.md) | Network architecture, Calico, Cloudflare Tunnel, NetworkPolicy |
| [Architecture Decisions](docs/adr/) | ADRs 001–016 with context and rationale |
| [Troubleshooting](docs/guides/troubleshooting.md) | Platform-level troubleshooting across all components |
| [Runbooks](docs/runbooks/) | Operational procedures (backup, DR, Vault, certificates) |

---

## Connect

- **LinkedIn:** [linkedin.com/in/mahmood-rajput](https://www.linkedin.com/in/mahmood-rajput/)
- **Email:** mahmoodrajput.cloud@gmail.com

---

*Last updated: April 2026 · Altdorf 71155, Germany*
