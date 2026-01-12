# DevContainer Configuration

This directory contains the DevContainer configuration for the Homelab Infrastructure Manager.

## Quick Start

### First Time Setup

1. **Copy environment template:**
   ```bash
   cp .devcontainer/.env.example .devcontainer/.env
   ```

2. **Edit `.devcontainer/.env` with your values:**
   ```bash
   # Find your username
   whoami
   
   # Find your UID and GID
   id -u
   id -g
   
   # Edit .env file
   vim .devcontainer/.env
   ```

3. **Build and start:**
   ```bash
   devcontainer build --workspace-folder .
   devcontainer up --workspace-folder .
   ./scripts/dev-shell.sh
   ```

## Configuration Files

### `.env` (Personal, not in git)
Contains your personal configuration:
- `CONTAINER_USERNAME` - Your WSL username
- `CONTAINER_USER_UID` - Your user ID (1000)
- `CONTAINER_USER_GID` - Your group ID (1000)
- `CONTAINER_HOSTNAME` - Container hostname for prompt

### `.env.example` (Template, in git)
Template file showing all available options with documentation.
Copy this to `.env` and customize.

### `devcontainer.json`
Main DevContainer specification. Uses environment variables from `.env`:
- Build arguments (username, UID, GID)
- Mount points (kubeconfig, SSH, git config)
- Network settings
- Environment variables

### `Dockerfile`
Builds the container image with all infrastructure tools:
- Ubuntu 24.04 LTS base
- kubectl, kubeadm, k9s (CKA-aligned versions)
- helm, argocd, ansible
- etcdctl, crictl, jq, yq
- Starship prompt

### `config/starship.toml`
Starship prompt configuration for beautiful, informative shell prompt.

### `post-create.sh`
Post-creation script that runs after container is built:
- Verifies all tools installed correctly
- Checks configuration mounts
- Tests cluster connectivity

## Sharing This Setup

### To Share With Others

1. **Commit these files to git:**
   - `.devcontainer/devcontainer.json`
   - `.devcontainer/Dockerfile`
   - `.devcontainer/.env.example`
   - `.devcontainer/config/starship.toml`
   - `.devcontainer/post-create.sh`

2. **Never commit:**
   - `.devcontainer/.env` (personal config)

3. **Recipients should:**
   ```bash
   git clone <your-repo>
   cd <repo>
   cp .devcontainer/.env.example .devcontainer/.env
   # Edit .env with their values
   devcontainer build --workspace-folder .
   ```

## Environment Variables

All environment variables support fallback defaults:

```json
"${localEnv:CONTAINER_USERNAME:rajput}"
```

This means:
1. Try to read `CONTAINER_USERNAME` from environment
2. If not set, use `rajput` as default

This allows the DevContainer to work even without `.env` file.

## Customization

### Change Username
Edit `.devcontainer/.env`:
```env
CONTAINER_USERNAME=yourname
```

### Change Tool Versions
Edit `.devcontainer/Dockerfile`:
```dockerfile
ARG KUBECTL_VERSION=1.32.0
```

Then rebuild:
```bash
devcontainer build --workspace-folder . --no-cache
```

### Customize Prompt
Edit `.devcontainer/config/starship.toml`, then rebuild.

## Troubleshooting

### "Permission denied" errors
Check your UID/GID in `.env` matches WSL:
```bash
id -u  # Should match CONTAINER_USER_UID
id -g  # Should match CONTAINER_USER_GID
```

### Username mismatch
Ensure `CONTAINER_USERNAME` in `.env` matches `whoami` output.

### File not found errors
Check that `.env` file exists and is properly formatted.

## Best Practices

1. ✅ **Always use `.env` for personal settings**
2. ✅ **Commit `.env.example` with documentation**
3. ✅ **Never commit `.env` to git**
4. ✅ **Use fallback defaults in `devcontainer.json`**
5. ✅ **Document all environment variables**

## Architecture Decision

This configuration uses environment variables instead of hardcoded values to make the DevContainer:
- **Portable** - Works for anyone with their own username/UID
- **Maintainable** - Single place to update user config
- **Shareable** - Easy to distribute and customize
- **Secure** - Personal configs stay out of git

### Documentation

- **ADR**: See `docs/adr/ADR-004-devcontainer.md` for architectural decisions
- **Detail Guide**: See `docs/devcontainer.md`