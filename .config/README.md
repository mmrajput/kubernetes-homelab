# Tool Configuration Directory

This directory is mounted into the DevContainer at `~/.config/` to persist tool configurations.

## Stored Configurations

- **k9s**: `k9s/` - K9s TUI preferences and skins
- **argocd**: `argocd/` - ArgoCD CLI configuration

## Note

This directory is writable inside the container to allow tools to save their configurations.
Files here will persist across container restarts.
