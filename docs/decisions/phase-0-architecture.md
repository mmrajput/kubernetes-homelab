# Phase 0: Architecture & Planning Decisions

Date: 2025-12-27
Status: ✅ Completed

## Hardware Configuration
Hardware: Beelink SER5 Pro
  - CPU: AMD Ryzen 7 5800H (16 threads)
  - RAM: 32GB DDR4
  - Storage: 500GB NVMe SSD
  - Network: Gigabit Ethernet

## Hypervisor
Proxmox VE Allocation:
  - Proxmox overhead: ~2GB
  - Available for VMs: ~30GB

## Cluster Architecture

```
Kubernetes Cluster:
  ├── k8s-cp-01 (Control Plane)
  │   ├── vCPU: 4 cores
  │   ├── RAM: 8GB
  │   └── Disk: 50GB
  │
  ├── k8s-worker-01
  │   ├── vCPU: 4 cores
  │   ├── RAM: 10GB
  │   └── Disk: 100GB (for Longhorn storage)
  │
  └── k8s-worker-02
      ├── vCPU: 4 cores
      ├── RAM: 10GB
      └── Disk: 100GB (for Longhorn storage)

Total Allocation: 12 vCPU, 28GB RAM, 250GB disk
```

**Why these numbers?**
- **Control plane 8GB**: Enough for etcd, API server, scheduler, controller-manager under load
- **Workers 10GB each**: Can run Prometheus, Grafana, Loki, AND application workloads simultaneously
- **100GB worker disks**: Proper Longhorn distributed storage with meaningful capacity
- **4 vCPU per node**: Multi-threaded workloads (databases, monitoring) won't bottleneck

## Technology Choices
- CNI: Calico (rationale: production standard, CKA-aligned)
- Storage: Longhorn (rationale: distributed, cloud-native)
- Observability: Prometheus + Grafana + Loki
- GitOps: ArgoCD

## Deferred to Future Phases
- True VLAN implementation (kubernetes-homelab-02 project)
- Advanced GitOps (app-of-apps pattern)
- Multi-cluster federation

## Next Phase
→ Phase 2: VM Creation & Configuration