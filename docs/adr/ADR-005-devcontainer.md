# ADR-005: DevContainer for Infrastructure Management

## Status

Accepted

## Date

2025-12-25

## Context

Managing Kubernetes infrastructure requires multiple CLI tools (kubectl, helm, k9s, argocd, ansible, etc.). Installing these directly in WSL creates problems:

- Tool pollution and version conflicts across projects
- Difficulty replicating environment across machines
- No alignment with specific Kubernetes versions

Requirements:
- Isolated, reproducible CLI environment
- Pinned tool versions matching cluster (v1.31.x)
- Access to homelab network (192.168.178.x)
- Persistent configuration across container restarts

## Decision

Use a **DevContainer** with Ubuntu 24.04 base image, pinned tool versions, and mounted configurations from WSL.

### Architecture Components

Implement a **DevContainer-based infrastructure management environment** with the following architecture:

```
┌─────────────────────────────────────────────────┐
│              Windows 11 + WSL2                  │
│  ┌──────────────────────────────────────────┐   │
│  │         WSL Ubuntu (Minimal)             │   │
│  │  - Docker Engine                         │   │
│  │  - DevContainer CLI                      │   │
│  │  - Git                                   │   │
│  │  - ~/.kube/config (mounted)              │   │
│  │  - ~/.ssh/ keys (mounted)                │   │
│  └─────────────┬────────────────────────────┘   │
│                │                                │
│                ▼                                │
│  ┌──────────────────────────────────────────┐   │
│  │    DevContainer (Ubuntu 24.04)           │   │
│  │  ┌────────────────────────────────────┐  │   │
│  │  │ Infrastructure Tools (Pinned)      │  │   │
│  │  │  - kubectl v1.31.4 (CKA version)   │  │   │
│  │  │  - kubeadm v1.31.4                 │  │   │
│  │  │  - k9s v0.32.7                     │  │   │
│  │  │  - helm v3.16.3                    │  │   │
│  │  │  - argocd v2.13.2                  │  │   │
│  │  │  - etcdctl v3.5.17                 │  │   │
│  │  │  - crictl v1.31.1                  │  │   │
│  │  │  - ansible 2.17.x                  │  │   │
│  │  │  - jq, yq, curl, wget              │  │   │
│  │  └────────────────────────────────────┘  │   │
│  │                                          │   │
│  │  User: rajput (UID 1000)                 │   │
│  │  Network: Host mode (access cluster IPs) │   │
│  └──────────────────────────────────────────┘   │
│                │                                │
│                ▼                                │
│  ┌──────────────────────────────────────────┐   │
│  │  Proxmox Homelab Network                 │   │
│  │  - Control Plane: 192.168.x.x:6443       │   │
│  │  - Worker Nodes: 192.168.x.x             │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## Rationale

| Criteria | DevContainer | WSL Direct Install | Docker Compose |
|----------|--------------|-------------------|----------------|
| Isolation | ✅ Full | ❌ None | ✅ Full |
| Reproducibility | ✅ Dockerfile defines all | ❌ Manual tracking | ⚠️ Partial |
| Version pinning | ✅ Explicit in Dockerfile | ⚠️ Package manager dependent | ✅ Explicit |
| IDE integration | ✅ VS Code native | ⚠️ Manual setup | ❌ None |
| Portability | ✅ Standard spec | ❌ Machine-specific | ⚠️ Custom setup |
| Industry adoption | ✅ GitHub Codespaces, etc. | N/A | ⚠️ Varies |

**Key factors:**

1. **Tool version pinning** — kubectl v1.31.4, helm v3.16.3, etc. explicitly defined in Dockerfile. Prevents unexpected breakage from upstream updates.

2. **OS alignment** — Ubuntu 24.04 base matches cluster VMs exactly, eliminating "works on my machine" issues.

3. **Configuration persistence** — Mount `~/.kube/config`, `~/.ssh/`, and `~/.gitconfig` read-only from WSL. Single source of truth, survives container rebuilds.

4. **Network access** — Host network mode provides direct access to homelab IPs without port forwarding complexity.

## Tool Versions

| Tool | Version | Rationale |
|------|---------|-----------|
| kubectl | 1.31.4 | Matches cluster version |
| kubeadm | 1.31.4 | Cluster lifecycle management |
| helm | 3.16.3 | Latest stable |
| k9s | 0.32.7 | Terminal UI for cluster |
| argocd | 2.13.2 | GitOps CLI |
| etcdctl | 3.5.17 | Backup/restore operations |
| crictl | 1.31.1 | Container runtime debugging |
| ansible | 2.17.x | Infrastructure automation |

## Consequences

### Positive

- Clean WSL with only Docker and DevContainer CLI
- Reproducible environment defined in version control
- Portable across machines (share Dockerfile)
- IDE integration with VS Code Remote Containers

### Negative

- Initial setup overhead (DevContainer CLI installation)
- First build takes 5-10 minutes
- ~2GB disk space for container image
- Learning curve for DevContainer workflow

## Alternatives Considered

### Direct WSL Installation

Rejected due to:
- No isolation between projects
- Version conflicts when working on multiple clusters
- Manual tracking of installed tools

### Custom Docker Compose

Rejected due to:
- Non-standard approach
- Less tooling support than DevContainer spec
- No IDE integration benefits

## References

- [DevContainer Specification](https://containers.dev/)
- [VS Code Remote Containers](https://code.visualstudio.com/docs/devcontainers/containers)
