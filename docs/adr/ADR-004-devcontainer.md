# ADR-004: DevContainer for Homelab Infrastructure Management

**Status:** Accepted  
**Date:** 2026-01-11  
**Author:** Mahmood  
**Context:** CKA Certification Preparation & Homelab Management

## Context

Managing Kubernetes infrastructure requires multiple CLI tools (kubectl, helm, k9s, argocd, ansible, etc.). Installing these directly in WSL creates several problems:

1. **Tool pollution**: WSL becomes cluttered with infrastructure tools
2. **Version conflicts**: Different projects may require different tool versions
3. **Reproducibility**: Difficult to replicate environment across machines
4. **CKA preparation**: Need environment matching exam conditions

**Goal:** Create an isolated, reproducible CLI environment for homelab management while keeping WSL minimal and clean.

## Decision

Implement a **DevContainer-based infrastructure management environment** with the following architecture:

### Architecture Components

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

### Key Design Decisions

#### 1. Base Image: Ubuntu 24.04 LTS
**Decision:** Use `ubuntu:24.04` as base image  
**Rationale:**
- Matches cluster VMs exactly (Ubuntu 24.04.3)
- Eliminates "works on my machine" issues
- LTS support until 2029
- Native systemd support (useful for understanding services)

**Alternative Considered:** Microsoft's pre-built devcontainer base images  
**Why Rejected:** Less transparency, harder to understand tool installation, doesn't match cluster OS

#### 2. Tool Version Pinning
**Decision:** Pin all tool versions explicitly in Dockerfile  
**Rationale:**
- **Reproducibility**: Same environment across rebuilds
- **CKA alignment**: kubectl 1.31.4 matches exam version
- **Stability**: Prevents breaking changes from upstream updates
- **Documentation**: Clear record of what versions are used

**Versions Chosen:**
| Tool | Version | Reason |
|------|---------|--------|
| kubectl | 1.31.4 | CKA exam version |
| kubeadm | 1.31.4 | Must match kubectl for cluster ops |
| k9s | 0.32.7 | Latest stable, compatible with K8s 1.31 |
| helm | 3.16.3 | Latest stable Helm 3.x |
| argocd | 2.13.2 | Latest stable release |
| etcdctl | 3.5.17 | Matches etcd in K8s 1.31 |
| crictl | 1.31.1 | CRI tools matching K8s version |
| ansible | 2.17.7 | Latest 2.x stable (ansible-core) |
| yq | 4.44.6 | Latest stable YAML processor |

#### 3. Configuration Management
**Decision:** Mount configs from WSL, not copy them  
**Rationale:**
- **Kubeconfig**: Read-only mount from `~/.kube/config`
  - Survives container restarts
  - Single source of truth
  - Easy to update from cluster
- **SSH keys**: Read-only mount from `~/.ssh/`
  - Secure (read-only prevents modification)
  - No key copying/duplication
  - Works with ssh-agent
- **Git config**: Read-only mount from `~/.gitconfig`
  - Consistent identity across environments
  - No manual reconfiguration needed
- **Tool configs**: Writable mount to `.config/`
  - k9s preferences, argocd settings persist
  - Can be version-controlled if desired

**Security Note:** All mounts are read-only except `.config/` to prevent accidental modification of sensitive files.

#### 4. Network Configuration
**Decision:** Use host network mode  
**Rationale:**
- Direct access to homelab IPs (192.168.x.x)
- No port forwarding complexity
- Matches how kubectl would work from WSL directly
- Simplifies troubleshooting

**Trade-off:** Less network isolation, but acceptable for local homelab use.

#### 5. Container User
**Decision:** Create user `rajput` with UID 1000  
**Rationale:**
- Matches WSL user UID (avoids permission issues)
- More personal than generic `devuser`
- Standard practice for rootless containers

#### 6. DevContainer CLI vs Docker Compose
**Decision:** Use official DevContainer CLI  
**Rationale:**
- **Standard spec**: Uses Microsoft's DevContainer specification
- **Portability**: Works with VS Code, GitHub Codespaces, other tools
- **Community support**: Well-documented, widely adopted
- **Future-proof**: Industry standard for development containers

**Alternative Considered:** Custom docker-compose setup  
**Why Rejected:** Non-standard, less tooling support, reinventing the wheel

#### 7. CKA Exam Alignment
**Decision:** Include all CKA-relevant tools even if not needed immediately  
**Tools:**
- `kubeadm` - Cluster bootstrapping (exam topic)
- `etcdctl` - etcd backup/restore (exam topic)
- `crictl` - Container runtime debugging (exam topic)

**Rationale:**
- Exam environment has these tools available
- Practice in realistic environment
- Build muscle memory for exam commands
- Minimal overhead to include them

#### 8. Tool Installation Method
**Decision:** Manual installation via `curl` with checksum verification  
**Rationale:**
- **Security**: SHA256 verification for kubectl/kubeadm
- **Transparency**: Clear what's being installed and from where
- **Learning**: Understand how tools are distributed
- **Control**: Not reliant on package managers that may lag

**Example:**
```dockerfile
RUN curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" \
    && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

## Consequences

### Positive
1. ✅ **Clean WSL**: Only Docker + DevContainer CLI in WSL
2. ✅ **Reproducible**: Identical environment across rebuilds
3. ✅ **Version control**: Dockerfile documents exact tool versions
4. ✅ **CKA-aligned**: Matches exam environment and tools
5. ✅ **Portable**: Can share with others, works on any machine with Docker
6. ✅ **Isolated**: No tool conflicts with other projects
7. ✅ **Professional**: Follows industry best practices

### Negative
1. ⚠️ **Initial overhead**: Need to install DevContainer CLI
2. ⚠️ **Build time**: First build takes 5-10 minutes
3. ⚠️ **Resource usage**: Container running consumes ~200MB RAM
4. ⚠️ **Learning curve**: Need to understand DevContainer workflow

### Neutral
1. 📝 **Image updates**: Must rebuild when tool versions change
2. 📝 **Disk space**: ~2GB for image (acceptable for modern systems)

## References

- [DevContainer Specification](https://containers.dev/)
- [CKA Exam Curriculum](https://github.com/cncf/curriculum)
- [Kubernetes Release Notes v1.31](https://kubernetes.io/blog/2024/08/13/kubernetes-v1-31-release/)

## Related ADRs

- ADR-001: Homelab Hardware Selection
- ADR-002: Proxmox VE Setup
- ADR-003: Kubernetes Cluster Architecture
- ADR-005: GitOps Implementation (Upcoming)

## Revision History

| Date | Author | Change |
|------|--------|--------|
| 2026-01-11 | Mahmood | Initial version - DevContainer architecture |
