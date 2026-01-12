# Homelab DevContainer - Infrastructure Management Environment

**Enterprise-grade, isolated CLI environment for Kubernetes homelab management**

## Overview

This DevContainer provides a **reproducible, isolated environment** for managing your Kubernetes homelab. It keeps your WSL environment clean while giving you all the infrastructure tools you need in a containerized workspace.

### What's Inside

- **Kubernetes Tools**: kubectl, kubeadm, k9s (all CKA-aligned)
- **Package Managers**: Helm
- **GitOps**: ArgoCD CLI
- **Automation**: Ansible
- **Utilities**: etcdctl, crictl, jq, yq, curl, wget

All tools are **pinned to specific versions** for reproducibility.

## Why Use This?

✅ **Clean WSL**: No infrastructure tools cluttering your WSL  
✅ **Reproducible**: Same environment every time, shareable with others  
✅ **CKA-Aligned**: Tools and versions match CKA exam environment  
✅ **Isolated**: No version conflicts with other projects  
✅ **Professional**: Industry-standard DevContainer approach  

# Quick Start Guide

## Prerequisites

### 1. Install DevContainer CLI (First time only)

```bash
# In WSL
npm install -g @devcontainers/cli

# Verify installation
devcontainer --version
```

### 2. Ensure Docker is Running

```bash
# Check Docker
docker --version
docker ps

# If not running, start Docker Desktop on Windows
```

### 3. Prepare Your Environment

Ensure these exist in your WSL home directory:

```bash
# Kubeconfig (required)
ls -la ~/.kube/config

# SSH keys (optional but recommended)
ls -la ~/.ssh/id_*

# Git config (optional but recommended)
ls -la ~/.gitconfig
```

## First Time Setup

### 1. Clone/Navigate to Your Project

```bash
cd ~/kubernetes-homelab-01  # Or wherever you keep this project
```

### 2. Build the DevContainer

```bash
# Build the image (takes 5-10 minutes first time)
devcontainer build --workspace-folder .

# Start the container
devcontainer up --workspace-folder .
```

### 3. Enter the Container

```bash
# Option 1: Use the helper script
./scripts/dev-shell.sh

# Option 2: Use devcontainer directly
devcontainer exec --workspace-folder . bash
```

### 4. Verify Setup

```bash
# Inside the container
./scripts/verify-tools.sh

# Test cluster access
kubectl get nodes

# Test k9s
k9s
```

## Daily Workflow

### Starting Your Day

```bash
# Navigate to project
cd ~/kubernetes-homelab-01

# Enter the container (starts if not running)
./scripts/dev-shell.sh

# You're now in the container with all tools!
```

### Common Tasks

```bash
# Inside the container

# Check cluster status
kubectl get nodes
kubectl get pods -A

# Use K9s TUI
k9s

# Helm operations
helm list -A
helm repo list

# ArgoCD
argocd app list
argocd app sync <app-name>

# Ansible
ansible-playbook playbooks/site.yml
```

### Exiting

```bash
# Simply exit the shell
exit

# The container keeps running in the background
# Next time you run dev-shell.sh, you'll reconnect instantly
```

## Container Management

### Check Container Status

```bash
# List running containers
docker ps | grep homelab

# Check container logs
devcontainer logs --workspace-folder .
```

### Stop Container

```bash
# Stop the container (preserves state)
docker stop <container-id>

# Or use devcontainer CLI
devcontainer stop --workspace-folder .
```

### Restart Container

```bash
# Start stopped container
devcontainer up --workspace-folder .

# Restart running container
devcontainer restart --workspace-folder .
```

### Rebuild Container (After Dockerfile Changes)

```bash
# Rebuild image
devcontainer build --workspace-folder .

# Stop old container and start new one
devcontainer up --workspace-folder .
```

## File Locations

### Inside Container

- **Kubeconfig**: `~/.kube/config` (mounted from WSL, read-only)
- **SSH Keys**: `~/.ssh/` (mounted from WSL, read-only)
- **Git Config**: `~/.gitconfig` (mounted from WSL, read-only)
- **Tool Configs**: `~/.config/` (writable, persists in `.config/` directory)
- **Working Directory**: `/workspaces/kubernetes-homelab-01`

### In WSL

- **DevContainer Config**: `.devcontainer/`
- **Tool Configs**: `.config/` (mounted into container)
- **Scripts**: `scripts/`
- **Documentation**: `docs/`

## Troubleshooting

### Container Won't Start

```bash
# Check Docker is running
docker ps

# Check for port conflicts
docker ps -a | grep homelab

# Remove old containers
docker rm -f <container-id>

# Rebuild from scratch
devcontainer build --workspace-folder . --no-cache
```

### Can't Connect to Cluster

```bash
# Inside container, check kubeconfig
cat ~/.kube/config

# Verify kubeconfig is mounted
ls -la ~/.kube/

# Test connectivity to API server
curl -k https://<your-control-plane-ip>:6443

# Check cluster info
kubectl cluster-info
```

### SSH Keys Not Working

```bash
# Verify keys are mounted
ls -la ~/.ssh/

# Check permissions (should be read-only)
ls -l ~/.ssh/id_*

# Test SSH
ssh -T git@github.com
```

### Tools Not Found

```bash
# Verify tools installation
./scripts/verify-tools.sh

# Check PATH
echo $PATH

# Manually check tool location
which kubectl
which k9s
```

### Performance Issues

```bash
# Check container resource usage
docker stats <container-id>

# Check WSL memory
free -h

# Restart Docker Desktop if needed (from Windows)
```

## Advanced Usage

### Multiple Shell Sessions

```bash
# Terminal 1
./scripts/dev-shell.sh

# Terminal 2 (same container, different shell)
devcontainer exec --workspace-folder . bash
```

### Running One-Off Commands

```bash
# Run command without entering container
devcontainer exec --workspace-folder . kubectl get nodes

# Run script
devcontainer exec --workspace-folder . bash -c "cd scripts && ./deploy.sh"
```

### Updating Tool Versions

1. Edit `.devcontainer/Dockerfile`
2. Change version ARG (e.g., `ARG KUBECTL_VERSION=1.32.0`)
3. Rebuild:
   ```bash
   devcontainer build --workspace-folder .
   devcontainer up --workspace-folder .
   ```

## Tips & Tricks

### Kubectl Aliases (Already Configured)

```bash
# Use 'k' instead of 'kubectl'
k get nodes
k get pods -A

# Tab completion works too
k get po<TAB>
```

### K9s Power User

```bash
# Start K9s
k9s

# Useful shortcuts inside K9s:
# :nodes    - View nodes
# :pods     - View pods
# :svc      - View services
# :ns       - View namespaces
# /         - Filter
# :q        - Quit
```

### Ansible Best Practices

```bash
# Check syntax before running
ansible-playbook --syntax-check playbooks/site.yml

# Dry run
ansible-playbook --check playbooks/site.yml

# Run with verbose output
ansible-playbook -vvv playbooks/site.yml
```

### Git Operations

```bash
# Git works normally with your mounted config
git status
git add .
git commit -m "Your message"
git push

# SSH keys are available for git operations
```

## Getting Help

### Tool-Specific Help

```bash
kubectl --help
k9s help
helm --help
argocd --help
ansible --help
```

### DevContainer Help

```bash
devcontainer --help
devcontainer build --help
devcontainer exec --help
```

### Documentation

- **ADR**: See `docs/ADR-004-devcontainer.md` for architectural decisions
- **Tool Docs**: Each tool has extensive online documentation
- **CKA**: Kubernetes documentation at https://kubernetes.io/docs/

## FAQ

**Q: Do I need to rebuild the container often?**  
A: No, only when you update tool versions in the Dockerfile.

**Q: Will I lose my work if I stop the container?**  
A: No, your git repository and configs are mounted from WSL, not inside the container.

**Q: Can I use VS Code with this container?**  
A: Yes, but it's not necessary. The setup is optimized for CLI-only use.

**Q: How do I update my kubeconfig?**  
A: Update it in WSL (`~/.kube/config`), it's automatically available in the container.

**Q: What if I want different tool versions?**  
A: Edit the Dockerfile version ARGs and rebuild.

**Q: Is this production-ready?**  
A: This is for development/learning. For production, use proper CI/CD pipelines.

## Next Steps

1. ✅ Get comfortable with the dev-shell.sh workflow
2. ✅ Test all tools with verify-tools.sh
3. ✅ Deploy your first Helm chart
4. ✅ Set up ArgoCD
5. ✅ Start working through CKA exercises

---

**Need more help?** Check `docs/ADR-004-devcontainer.md` or the tool-specific documentation.
