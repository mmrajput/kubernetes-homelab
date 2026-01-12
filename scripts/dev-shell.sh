#!/bin/bash
# Quick access script for homelab DevContainer
# Usage: ./scripts/dev-shell.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Starting homelab DevContainer shell..."

# Check if devcontainer CLI is installed
if ! command -v devcontainer &> /dev/null; then
    echo "❌ Error: devcontainer CLI not found"
    echo ""
    echo "Install it with:"
    echo "  npm install -g @devcontainers/cli"
    exit 1
fi

# Check if container is running, if not start it
if ! devcontainer exec --workspace-folder "$PROJECT_ROOT" echo "test" &> /dev/null; then
    echo "📦 Container not running, starting it first..."
    devcontainer up --workspace-folder "$PROJECT_ROOT"
fi

# Open shell in container
echo "✅ Opening shell in DevContainer..."
devcontainer exec --workspace-folder "$PROJECT_ROOT" bash
