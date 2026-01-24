## Network Topology

This homelab uses a standard home network setup with Proxmox hypervisor and Kubernetes VMs on a private subnet.

```
Internet
   │
   └─► Home Router (192.168.178.1)
          │
          ├─► Proxmox Host (192.168.178.33)
          │       │
          │       ├─► vmbr0 (Bridge)
          │       │      │
          │       │      ├─► k8s-cp-01 (192.168.178.34)
          │       │      ├─► k8s-worker-01 (192.168.178.35)
          │       │      └─► k8s-worker-02 (192.168.178.36)
          │
          └─► Other home devices (DHCP)
```

## IP Address Allocation

| Device/VM     | IP Address      | Purpose                |
|---------------|-----------------|------------------------|
| Router/Gateway| 192.168.178.1   | Default gateway, DNS   |
| Proxmox Host  | 192.168.178.33  | Hypervisor management  |
| k8s-cp-01     | 192.168.178.34  | Kubernetes control plane|
| k8s-worker-01 | 192.168.178.35  | Kubernetes worker node |
| k8s-worker-02 | 192.168.178.36  | Kubernetes worker node |

## Network Details

- **Subnet:** 192.168.178.0/24
- **Gateway:** 192.168.178.1
- **Primary DNS:** 192.168.178.1 (router)
- **Secondary DNS:** 8.8.8.8 (Google Public DNS)
- **DHCP Range:** 192.168.178.100-254 (managed by router)
- **Static Range:** 192.168.178.30-50 (homelab infrastructure)

## Adapting for Your Network

All scripts and configurations use these IPs as examples. To use different IPs:

1. Update `infra/ansible/inventory.ini`
2. Update `infra/ansible/group_vars/all.yml`
3. Set environment variables when running Proxmox scripts

See individual component READMEs for details.