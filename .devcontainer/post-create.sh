#!/bin/bash
# Post-creation script for Homelab DevContainer
# Runs after container is created to verify setup

set -e

echo "🚀 Homelab DevContainer - Post-Creation Setup"
echo "=============================================="

# Verify all tools are installed
echo ""
echo "📦 Verifying tool installations..."

verify_tool() {
    local tool=$1
    local version_cmd=$2
    
    if command -v "$tool" &> /dev/null; then
        echo "✅ $tool: $($version_cmd)"
    else
        echo "❌ $tool: NOT FOUND"
        return 1
    fi
}

verify_tool "kubectl" "kubectl version --client --short 2>/dev/null | head -1"
verify_tool "kubeadm" "kubeadm version -o short"
verify_tool "k9s" "k9s version -s 2>/dev/null | head -1"
verify_tool "helm" "helm version --short"
verify_tool "argocd" "argocd version --client --short 2>/dev/null | head -1"
verify_tool "etcdctl" "etcdctl version | head -1"
verify_tool "crictl" "crictl --version"
verify_tool "jq" "jq --version"
verify_tool "yq" "yq --version"
verify_tool "ansible" "ansible --version | head -1"

# Check SSH key mount
echo ""
echo "🔑 Checking SSH keys..."
if [ -d ~/.ssh ] && [ -f ~/.ssh/id_rsa ] || [ -f ~/.ssh/id_ed25519 ]; then
    echo "✅ SSH keys mounted"
    ls -la ~/.ssh/ | grep -E "id_(rsa|ed25519)" || echo "⚠️  No SSH keys found"
else
    echo "⚠️  SSH directory not mounted or no keys found"
fi

# Check kubeconfig
echo ""
echo "☸️  Checking Kubernetes configuration..."
if [ -f ~/.kube/config ]; then
    echo "✅ kubeconfig found at ~/.kube/config"
    
    # Try to connect to cluster (non-fatal if it fails)
    if kubectl cluster-info &> /dev/null; then
        echo "✅ Successfully connected to cluster:"
        kubectl get nodes -o wide 2>/dev/null || echo "⚠️  Could not list nodes (may need VPN/network)"
    else
        echo "⚠️  kubeconfig exists but cannot connect to cluster"
        echo "   This is normal if your cluster is not running or requires VPN"
    fi
else
    echo "❌ No kubeconfig found at ~/.kube/config"
    echo "   Mount your kubeconfig from WSL or copy it manually"
fi

# Check git configuration
echo ""
echo "🔧 Checking Git configuration..."
if [ -f ~/.gitconfig ]; then
    echo "✅ Git config mounted"
    git config --get user.name &> /dev/null && echo "   User: $(git config --get user.name)"
    git config --get user.email &> /dev/null && echo "   Email: $(git config --get user.email)"
else
    echo "⚠️  No git config found - you may need to configure git manually"
fi

# Create config directories if they don't exist
echo ""
echo "📁 Setting up configuration directories..."
mkdir -p ~/.config/k9s
mkdir -p ~/.config/argocd
echo "✅ Config directories created"

# Display helpful information
echo ""
echo "=============================================="
echo "✨ DevContainer setup complete!"
echo ""
echo "📚 Quick Reference:"
echo "   kubectl alias: k"
echo "   Kubeconfig: ~/.kube/config"
echo "   Tool configs: ~/.config/"
echo ""
echo "🎯 Next steps:"
echo "   1. Verify cluster access: kubectl get nodes"
echo "   2. Test k9s: k9s"
echo "   3. Check helm: helm list -A"
echo ""
echo "📖 Documentation: docs/adr/ADR-004-devcontainer.md"
echo "=============================================="
