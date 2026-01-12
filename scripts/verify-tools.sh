#!/bin/bash
# Tool verification script
# Runs inside the DevContainer to verify all tools are correctly installed
# Usage: ./scripts/verify-tools.sh

set +e

echo "🔍 Homelab DevContainer - Tool Verification"
echo "==========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

verify_tool() {
    local tool_name=$1
    local command=$2
    local expected_version=$3
    
    echo -n "Testing $tool_name... "
    
    if command -v "$command" &> /dev/null; then
        # Special handling for different tools' version commands
        case "$command" in
            kubectl)
                version_output=$(kubectl version --client 2>/dev/null | grep -oP 'Client Version: \K.*' || kubectl version --client --short 2>/dev/null | head -1 || echo "unknown")
                ;;
            kubeadm)
                version_output=$(kubeadm version -o short 2>/dev/null || echo "unknown")
                ;;
            k9s)
                version_output=$(k9s version -s 2>/dev/null | grep Version | awk '{print $2}' || echo "unknown")
                ;;
            argocd)
                version_output=$(argocd version --client --short 2>/dev/null | head -1 || echo "unknown")
                ;;
            helm)
                version_output=$(helm version --short 2>/dev/null || echo "unknown")
                ;;
            etcdctl)
                version_output=$(etcdctl version 2>/dev/null | head -1 | awk '{print $3}' || echo "unknown")
                ;;
            crictl)
                version_output=$(crictl --version 2>/dev/null | awk '{print $3}' || echo "unknown")
                ;;
            ansible)
                version_output=$(ansible --version 2>/dev/null | head -1 || echo "unknown")
                ;;
            *)
                version_output=$($command --version 2>&1 | head -1 || echo "unknown")
                ;;
        esac
        
        if [ -n "$expected_version" ]; then
            if echo "$version_output" | grep -q "$expected_version"; then
                echo -e "${GREEN}✅ PASS${NC} ($version_output)"
                ((PASSED++))
            else
                echo -e "${YELLOW}⚠️  VERSION MISMATCH${NC}"
                echo "   Expected: $expected_version"
                echo "   Got: $version_output"
                ((FAILED++))
            fi
        else
            echo -e "${GREEN}✅ PASS${NC} ($version_output)"
            ((PASSED++))
        fi
    else
        echo -e "${RED}❌ FAIL${NC} - Command not found"
        ((FAILED++))
    fi
}

verify_connectivity() {
    local test_name=$1
    local command=$2
    
    echo -n "Testing $test_name... "
    
    if eval "$command" &> /dev/null; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠️  SKIP${NC} (Not available or requires cluster access)"
    fi
}

# Core Kubernetes tools
echo "📦 Core Kubernetes Tools"
echo "------------------------"
verify_tool "kubectl" "kubectl" "v1.31"
verify_tool "kubeadm" "kubeadm" "v1.31"
verify_tool "k9s" "k9s" "v0.32"

# Package managers and deployment tools
echo ""
echo "📦 Package Managers & Deployment"
echo "--------------------------------"
verify_tool "helm" "helm" "v3.16"
verify_tool "argocd" "argocd" "v2.13"

# Container runtime tools
echo ""
echo "🐳 Container Runtime Tools"
echo "-------------------------"
verify_tool "crictl" "crictl" "v1.31"

# Backup and management tools
echo ""
echo "💾 Backup & Management Tools"
echo "----------------------------"
verify_tool "etcdctl" "etcdctl" "3.5.17"

# Configuration management
echo ""
echo "⚙️  Configuration Management"
echo "---------------------------"
verify_tool "ansible" "ansible" "2.17"

# Utility tools
echo ""
echo "🔧 Utility Tools"
echo "---------------"
verify_tool "jq" "jq" ""
verify_tool "yq" "yq" "v4"
verify_tool "curl" "curl" ""
verify_tool "wget" "wget" ""
verify_tool "git" "git" ""

# Check mounted configurations
echo ""
echo "📁 Configuration Mounts"
echo "----------------------"
echo -n "Checking kubeconfig... "
if [ -f ~/.kube/config ]; then
    echo -e "${GREEN}✅ FOUND${NC}"
    ((PASSED++))
else
    echo -e "${RED}❌ MISSING${NC}"
    ((FAILED++))
fi

echo -n "Checking SSH keys... "
if [ -d ~/.ssh ] && ([ -f ~/.ssh/id_rsa ] || [ -f ~/.ssh/id_ed25519 ]); then
    echo -e "${GREEN}✅ FOUND${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️  NOT FOUND${NC} (Optional)"
fi

echo -n "Checking git config... "
if [ -f ~/.gitconfig ]; then
    echo -e "${GREEN}✅ FOUND${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️  NOT FOUND${NC}"
fi

# Test cluster connectivity (optional)
echo ""
echo "☸️  Cluster Connectivity (Optional)"
echo "-----------------------------------"
verify_connectivity "Cluster API" "kubectl cluster-info"
verify_connectivity "List nodes" "kubectl get nodes"

# Summary
echo ""
echo "==========================================="
echo "📊 Verification Summary"
echo "==========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
fi
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All critical tools verified successfully!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tools failed verification${NC}"
    exit 1
fi
