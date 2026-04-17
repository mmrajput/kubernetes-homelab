# DevContainer — Homelab Infrastructure Manager

Isolated CLI environment for Kubernetes cluster management, matching the Ubuntu 24.04 LTS base of the cluster VMs.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Desktop (Windows) or Docker Engine (Linux) | Must be running before starting the container |
| `devcontainer` CLI | `npm install -g @devcontainers/cli` |
| WSL2 (Windows) | Required for bind-mounting `~/.kube`, `~/.ssh`, `~/.gitconfig` |
| `~/.kube/config` on the host | Needed to reach the cluster from inside the container |

---

## First-Time Setup

1. **Clone the repository:**
   ```bash
   git clone <repo-url>
   cd kubernetes-homelab-01
   ```

2. **Copy the environment template:**
   ```bash
   cp .devcontainer/.env.example .devcontainer/.env
   ```

3. **Fill in your values** — find them with:
   ```bash
   whoami   # → CONTAINER_USERNAME
   id -u    # → CONTAINER_USER_UID
   id -g    # → CONTAINER_USER_GID
   ```

   Edit `.devcontainer/.env`:
   ```env
   CONTAINER_USERNAME=yourname
   CONTAINER_USER_UID=1000
   CONTAINER_USER_GID=1000
   CONTAINER_HOSTNAME=homelab-devcontainer   # optional, used in shell prompt
   ```

4. **Build and start the container:**
   ```bash
   devcontainer build --workspace-folder .
   devcontainer up --workspace-folder .
   devcontainer exec --workspace-folder . bash
   ```

   First build takes ~5–10 min. `post-create.sh` runs automatically after the container starts.

5. **Verify the setup** (optional, inside the container):
   ```bash
   bash ~/.devcontainer/verify-tools.sh
   kubectl get nodes
   ```

---

## Installed Tools

| Tool | Version | Purpose |
|------|---------|---------|
| kubectl | 1.31.4 | Kubernetes CLI |
| kubeadm | 1.31.4 | Cluster bootstrap / operations |
| k9s | 0.32.7 | TUI for Kubernetes |
| helm | 3.16.3 | Package manager |
| argocd | 2.13.2 | GitOps CLI |
| etcdctl | 3.5.17 | etcd management |
| crictl | 1.31.1 | Container runtime CLI |
| yq | 4.44.6 | YAML processor |
| jq | system | JSON processor |
| ansible | 10.7.0 / core 2.17.7 | Config management |
| python3 | system | Runtime for Ansible + kubernetes/jmespath libs |
| diagrams | 0.24.4 | Architecture-as-code (requires graphviz) |
| graphviz | system | Graph rendering backend for diagrams |
| ollama | 0.9.3 | Local LLM inference |
| ping, dig, nc, traceroute | system | Network diagnostics |

---

## Directory Contents

```
.devcontainer/
├── devcontainer.json       # Container spec (mounts, env, postCreate)
├── Dockerfile              # Container image definition
├── .env.example            # Template — copy to .env and customize
├── .env                    # Personal config (gitignored)
├── post-create.sh          # Runs after build: verifies tools, checks mounts, pulls Ollama model
├── verify-tools.sh         # Manual tool verification script
└── cleanup-devcontainer.sh # Docker cleanup: removes old images, build cache
```

---

## Host Directory Mounts

| Host path (WSL) | Container path | Mode |
|-----------------|----------------|------|
| `~/.kube` | `~/.kube` | read-only |
| `~/.ssh` | `~/.ssh` | read-only |
| `~/.gitconfig` | `~/.gitconfig` | read-only |
| `~/.ollama` | `~/.ollama` | read-write (model storage) |
| `.config/` (repo root) | `~/.config` | read-write (k9s, argocd configs) |

---

## Ollama (Local LLM)

Ollama is installed and starts automatically when you open a terminal. The default model (`qwen2.5:7b`) is pulled during `post-create.sh`.

To change the model, set `OLLAMA_MODEL` as a build arg before rebuilding:
```bash
# In .devcontainer/.env or as an env var:
OLLAMA_MODEL=qwen2.5:14b
```

Suggested models by available RAM: `8 GB → qwen2.5:7b` · `16 GB → qwen2.5:14b` · `32 GB → qwen2.5:32b`

To pull a model manually inside the container:
```bash
ollama pull qwen2.5:14b
```

---

## Rebuilding

After changing the `Dockerfile` or tool versions:

```bash
devcontainer build --workspace-folder . --no-cache
devcontainer up --workspace-folder .
```

---

## Maintenance

**Clean up old Docker images and build cache** (run from the WSL host, not inside the container):
```bash
bash .devcontainer/cleanup-devcontainer.sh
```

Keeps the two newest DevContainer images and the `ubuntu:24.04` base; removes stopped containers and build cache.

---

## Troubleshooting

**"Permission denied" in the container**
Your UID/GID in `.env` must match your WSL user:
```bash
id -u   # must equal CONTAINER_USER_UID
id -g   # must equal CONTAINER_USER_GID
```

**`kubectl` cannot reach the cluster**
`~/.kube/config` is bind-mounted read-only. If the file doesn't exist on the WSL host, create or copy it there before rebuilding. Verify inside the container:
```bash
kubectl cluster-info
```

**Tools show wrong versions**
Run `verify-tools.sh` to get a full report, then rebuild without cache if versions mismatch.

**`.env` not picked up**
Ensure the file is at `.devcontainer/.env` (not `.env` at repo root) and contains no Windows-style line endings (`\r\n`).

---

## Further Reading

- **ADR:** `docs/adr/ADR-005-devcontainer.md` — architectural decisions behind this setup
- **Setup guide:** `docs/guides/devcontainer-setup.md` — detailed walkthrough
