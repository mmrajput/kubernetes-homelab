#!/bin/bash
#
# create-k8s-workers.sh - Create Kubernetes Worker Nodes
#
# This script clones the Ubuntu template and configures multiple worker
# nodes with proper networking and resources in batch.
#
# Usage:
#   ./create-k8s-workers.sh
#
#   # Override network for different subnet
#   BASE_IP=10.0.1 GATEWAY=10.0.1.1 ./create-k8s-workers.sh
#
# Prerequisites:
#   - Ubuntu template (ID 9000) must exist
#   - SSH public key must be available
#   - Run as root on Proxmox host
#
# Output:
#   - VM ID 2001: k8s-worker-01
#   - VM ID 2002: k8s-worker-02
#   - (Add more workers in WORKERS array as needed)
#
# Author: Mahmood - Kubernetes Homelab Project
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

# Template to clone from
TEMPLATE_ID="9000"

# Worker node specifications (name|IP|cores|memory_MB|disk_GB)
# Format: ["VMID"]="name|IP|cores|RAM|disk"
declare -A WORKERS=(
  ["2001"]="k8s-worker-01|192.168.178.35|3|7168|100"
  ["2002"]="k8s-worker-02|192.168.178.36|3|7168|100"
  # Add more workers as needed:
  # ["2003"]="k8s-worker-03|192.168.178.37|3|7168|100"
)

# Network configuration (can be overridden via environment variables)
GATEWAY="${GATEWAY:-192.168.178.1}"
DNS_SERVERS="${DNS_SERVERS:-192.168.178.1 1.1.1.1}"
BASE_IP="${BASE_IP:-192.168.178}"  # For subnet override
NETMASK="24"
SEARCH_DOMAIN="home.lab"

# Cloud-init configuration
CLOUD_INIT_USER="mahmood"  # Change to your username
SSH_KEY_PATH="/tmp/id_ed25519_homelab.pub"

# Deployment settings
BOOT_WAIT_SECONDS=90  # Cloud-init completion time
PARALLEL_CREATE=true  # Create all workers simultaneously

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_template_exists() {
    if ! qm status "$TEMPLATE_ID" &> /dev/null; then
        log_error "Template ID $TEMPLATE_ID does not exist!"
        log_error "Run ./create-template.sh first to create the base template."
        exit 1
    fi
}

check_ssh_key() {
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_error "SSH public key not found at: $SSH_KEY_PATH"
        log_error ""
        log_error "Generate a key first:"
        log_error "  ssh-keygen -t ed25519 -C 'homelab' -f ~/.ssh/id_ed25519_homelab"
        log_error ""
        log_error "Then copy to Proxmox:"
        log_error "  scp ~/.ssh/id_ed25519_homelab.pub root@$(hostname -I | awk '{print $1}'):/tmp/"
        exit 1
    fi
}

check_existing_vms() {
    local existing=()
    
    for vmid in "${!WORKERS[@]}"; do
        if qm status "$vmid" &> /dev/null; then
            existing+=("$vmid")
        fi
    done
    
    if [[ ${#existing[@]} -gt 0 ]]; then
        log_warn "Found existing VMs: ${existing[*]}"
        read -p "Do you want to destroy and recreate them? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            for vmid in "${existing[@]}"; do
                log_info "Destroying VM $vmid..."
                qm stop "$vmid" || true
                sleep 2
                qm destroy "$vmid" --purge
                sleep 2
            done
        else
            log_error "Existing VMs found. Please remove them manually or choose different VM IDs."
            exit 1
        fi
    fi
}

create_worker_vm() {
    local vmid=$1
    local config=$2
    
    # Parse configuration
    IFS='|' read -r name ip cores memory disk <<< "$config"
    
    log_step "Creating worker: $name (VM ID: $vmid)"
    echo "  IP Address:    ${ip}/${NETMASK}"
    echo "  vCPUs:         $cores"
    echo "  Memory:        ${memory}MB ($(( memory / 1024 ))GB)"
    echo "  Disk:          ${disk}GB"
    echo
    
    # Clone template
    log_info "  [1/6] Cloning template $TEMPLATE_ID..."
    qm clone "$TEMPLATE_ID" "$vmid" \
        --name "$name" \
        --full \
        --storage local-lvm
    
    # Configure resources
    log_info "  [2/6] Configuring CPU and memory..."
    qm set "$vmid" --memory "$memory"
    qm set "$vmid" --cores "$cores"
    
    # Resize disk
    log_info "  [3/6] Resizing disk to ${disk}GB..."
    qm resize "$vmid" scsi0 "${disk}G"
    
    # Configure networking
    log_info "  [4/6] Configuring network..."
    qm set "$vmid" --ipconfig0 "ip=${ip}/${NETMASK},gw=${GATEWAY}"
    qm set "$vmid" --nameserver "$DNS_SERVERS"
    qm set "$vmid" --searchdomain "$SEARCH_DOMAIN"
    
    # Configure cloud-init user
    log_info "  [5/6] Configuring cloud-init user and SSH..."
    qm set "$vmid" --ciuser "$CLOUD_INIT_USER"
    qm set "$vmid" --sshkeys "$SSH_KEY_PATH"
    
    # Start VM
    log_info "  [6/6] Starting VM..."
    qm start "$vmid"
    
    log_info "  ✓ Worker $name created successfully"
    echo
}

wait_for_workers() {
    log_info "Waiting ${BOOT_WAIT_SECONDS} seconds for cloud-init to complete..."
    sleep "$BOOT_WAIT_SECONDS"
    echo
}

verify_worker_ssh() {
    local vmid=$1
    local config=$2
    
    # Parse configuration
    IFS='|' read -r name ip _ _ _ <<< "$config"
    
    log_info "Verifying $name ($ip)..."
    
    # Try SSH connection using PRIVATE key
    local private_key="${SSH_KEY_PATH%.pub}"
    
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
           -i "$private_key" \
           "${CLOUD_INIT_USER}@${ip}" \
           "cloud-init status --wait" &> /dev/null; then
        log_info "  ✓ $name is ready (cloud-init completed)"
        return 0
    else
        log_warn "  ✗ $name is NOT ready (cloud-init still running or failed)"
        log_warn "    Check status: qm terminal $vmid"
        log_warn "    Or SSH manually: ssh -i $private_key ${CLOUD_INIT_USER}@${ip}"
        return 1
    fi
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

main() {
    log_info "Creating Kubernetes Worker Nodes..."
    echo
    
    # Pre-flight checks
    check_root
    check_template_exists
    check_ssh_key
    check_existing_vms
    
    # Display configuration
    echo "Configuration:"
    echo "  Template ID:    $TEMPLATE_ID"
    echo "  Worker Count:   ${#WORKERS[@]}"
    echo "  Gateway:        $GATEWAY"
    echo "  DNS Servers:    $DNS_SERVERS"
    echo "  Search Domain:  $SEARCH_DOMAIN"
    echo "  Cloud-init User: $CLOUD_INIT_USER"
    echo "  SSH Key:        $SSH_KEY_PATH"
    echo
    
    echo "Workers to create:"
    for vmid in $(echo "${!WORKERS[@]}" | tr ' ' '\n' | sort -n); do
        IFS='|' read -r name ip cores memory disk <<< "${WORKERS[$vmid]}"
        printf "  VM %-4s: %-15s | %-15s | %d vCPU | %2dGB RAM | %3dGB Disk\n" \
            "$vmid" "$name" "$ip" "$cores" "$((memory/1024))" "$disk"
    done
    echo
    
    read -p "Proceed with worker creation? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cancelled by user"
        exit 0
    fi
    echo
    
    # Create workers
    log_step "Phase 1: Creating worker VMs"
    echo
    
    for vmid in $(echo "${!WORKERS[@]}" | tr ' ' '\n' | sort -n); do
        create_worker_vm "$vmid" "${WORKERS[$vmid]}"
    done
    
    # Wait for cloud-init
    log_step "Phase 2: Waiting for cloud-init completion"
    wait_for_workers
    
    # Verify SSH connectivity
    log_step "Phase 3: Verifying SSH connectivity"
    echo
    
    local ready_count=0
    for vmid in $(echo "${!WORKERS[@]}" | tr ' ' '\n' | sort -n); do
        if verify_worker_ssh "$vmid" "${WORKERS[$vmid]}"; then
            ((ready_count++)) || true
        fi
    done
    echo
    
    # Success summary
    log_info "=========================================="
    log_info "  Worker Creation Complete!"
    log_info "=========================================="
    echo
    echo "Summary:"
    echo "  Workers Created:  ${#WORKERS[@]}"
    echo "  Workers Ready:    ${ready_count}/${#WORKERS[@]}"
    echo
    
    if [[ $ready_count -eq ${#WORKERS[@]} ]]; then
        log_info "All workers are ready!"
    else
        log_warn "Some workers may need additional time. Check manually."
    fi
    echo
    
    # Provide next steps
    echo "Worker Details:"
    for vmid in $(echo "${!WORKERS[@]}" | tr ' ' '\n' | sort -n); do
        IFS='|' read -r name ip _ _ _ <<< "${WORKERS[$vmid]}"
        echo "  $name:"
        echo "    - SSH: ssh -i ${SSH_KEY_PATH%.pub} ${CLOUD_INIT_USER}@${ip}"
        echo "    - Console: qm terminal $vmid"
        echo "    - Status: qm status $vmid"
    done
    echo
    
    echo "Verification Commands:"
    echo "  # Test SSH to all workers"
    for vmid in $(echo "${!WORKERS[@]}" | tr ' ' '\n' | sort -n); do
        IFS='|' read -r name ip _ _ _ <<< "${WORKERS[$vmid]}"
        echo "  ssh ${CLOUD_INIT_USER}@${ip} 'hostname && df -h / && cloud-init status'"
    done
    echo
    
    echo "Next Steps:"
    echo "  1. Verify all workers are accessible via SSH"
    echo "  2. Proceed to Kubernetes installation:"
    echo "     cd ../../ansible"
    echo "     ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml"
    echo
    log_info "Worker nodes are ready for Kubernetes installation!"
}

# Run main function
main "$@"
