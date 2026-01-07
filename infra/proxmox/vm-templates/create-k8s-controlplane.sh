#!/bin/bash
#
# create-k8s-controlplane.sh - Create Kubernetes Control Plane Node
#
# This script clones the Ubuntu template and configures it as the
# Kubernetes control plane node with proper networking and resources.
#
# Usage:
#   ./create-k8s-controlplane.sh
#
# Prerequisites:
#   - Ubuntu template (ID 9000) must exist
#   - SSH public key must be available
#   - Run as root on Proxmox host
#
# Output:
#   - VM ID 1001: k8s-cp-01 (Control Plane)
#
# Author: Mahmood - Kubernetes Homelab Project
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

# Template to clone from
TEMPLATE_ID="9000"

# Control plane VM specifications
VM_ID="1001"
VM_NAME="k8s-cp-01"
VM_MEMORY=6144        # 6GB RAM for control plane
VM_CORES=3            # 3 vCPUs
VM_DISK_SIZE="50G"    # 50GB storage

# Network configuration
VM_IP="192.168.178.34"
VM_GATEWAY="192.168.178.1"
VM_NETMASK="24"       # /24 = 255.255.255.0
VM_DNS="192.168.178.1 1.1.1.1"
VM_SEARCH_DOMAIN="home.lab"

# Cloud-init configuration
CLOUD_INIT_USER="mahmood"        # Change to your username
SSH_KEY_PATH="/tmp/id_ed25519_homelab.pub"  # Update with your key path

# Deployment wait time
BOOT_WAIT_SECONDS=90  # Cloud-init takes 60-90s to complete

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

check_vm_exists() {
    if qm status "$VM_ID" &> /dev/null; then
        log_warn "VM ID $VM_ID already exists!"
        read -p "Do you want to destroy it and recreate? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Destroying existing VM $VM_ID..."
            qm stop "$VM_ID" || true  # Don't fail if already stopped
            sleep 2
            qm destroy "$VM_ID" --purge
            sleep 2
        else
            log_error "VM already exists. Exiting."
            exit 1
        fi
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

wait_for_cloud_init() {
    local vm_ip=$1
    local max_attempts=30
    local attempt=0

    log_info "Waiting for cloud-init to complete (this takes ~90 seconds)..."
    
    # Initial wait for VM to boot
    sleep "$BOOT_WAIT_SECONDS"

    # Try to SSH and check cloud-init status
    while [[ $attempt -lt $max_attempts ]]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
               -i "${SSH_KEY_PATH%.pub}" \
               "${CLOUD_INIT_USER}@${vm_ip}" \
               "cloud-init status --wait" &> /dev/null; then
            log_info "✓ Cloud-init completed successfully"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done

    log_warn "Could not verify cloud-init completion via SSH"
    log_warn "VM may still be initializing. Check manually with:"
    log_warn "  ssh ${CLOUD_INIT_USER}@${vm_ip} 'cloud-init status --wait'"
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

main() {
    log_info "Creating Kubernetes Control Plane Node..."
    echo

    # Pre-flight checks
    check_root
    check_template_exists
    check_vm_exists
    check_ssh_key

    # Display configuration
    echo "Configuration:"
    echo "  Template ID:    $TEMPLATE_ID"
    echo "  VM ID:          $VM_ID"
    echo "  VM Name:        $VM_NAME"
    echo "  IP Address:     ${VM_IP}/${VM_NETMASK}"
    echo "  Gateway:        $VM_GATEWAY"
    echo "  Memory:         ${VM_MEMORY}MB (8GB)"
    echo "  vCPUs:          $VM_CORES"
    echo "  Disk Size:      $VM_DISK_SIZE"
    echo "  User:           $CLOUD_INIT_USER"
    echo "  SSH Key:        $SSH_KEY_PATH"
    echo

    read -p "Proceed with VM creation? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cancelled by user"
        exit 0
    fi
    echo

    # Step 1: Clone template
    log_step "1/7: Cloning template $TEMPLATE_ID to VM $VM_ID..."
    qm clone "$TEMPLATE_ID" "$VM_ID" \
        --name "$VM_NAME" \
        --full \
        --storage local-lvm

    # Step 2: Configure resources
    log_step "2/7: Configuring CPU and memory..."
    qm set "$VM_ID" --memory "$VM_MEMORY"
    qm set "$VM_ID" --cores "$VM_CORES"

    # Step 3: Resize disk
    log_step "3/7: Resizing disk to $VM_DISK_SIZE..."
    qm resize "$VM_ID" scsi0 "$VM_DISK_SIZE"

    # Step 4: Configure networking
    log_step "4/7: Configuring static IP network..."
    qm set "$VM_ID" --ipconfig0 "ip=${VM_IP}/${VM_NETMASK},gw=${VM_GATEWAY}"
    qm set "$VM_ID" --nameserver "$VM_DNS"
    qm set "$VM_ID" --searchdomain "$VM_SEARCH_DOMAIN"

    # Step 5: Configure cloud-init user
    log_step "5/7: Configuring cloud-init user and SSH key..."
    qm set "$VM_ID" --ciuser "$CLOUD_INIT_USER"
    qm set "$VM_ID" --sshkeys "$SSH_KEY_PATH"

    # Step 6: Start VM
    log_step "6/7: Starting VM..."
    qm start "$VM_ID"

    # Step 7: Wait for cloud-init
    log_step "7/7: Waiting for cloud-init to complete..."
    wait_for_cloud_init "$VM_IP"

    # Success summary
    echo
    log_info "=========================================="
    log_info "  Control Plane Created Successfully!"
    log_info "=========================================="
    echo
    echo "VM Details:"
    echo "  - VM ID:         $VM_ID"
    echo "  - VM Name:       $VM_NAME"
    echo "  - IP Address:    ${VM_IP}"
    echo "  - SSH Access:    ssh ${CLOUD_INIT_USER}@${VM_IP}"
    echo "  - Status:        $(qm status "$VM_ID" | awk '{print $2}')"
    echo
    echo "Verification Commands:"
    echo "  # SSH into control plane"
    echo "  ssh -i ${SSH_KEY_PATH%.pub} ${CLOUD_INIT_USER}@${VM_IP}"
    echo
    echo "  # Check cloud-init status"
    echo "  ssh ${CLOUD_INIT_USER}@${VM_IP} 'cloud-init status --wait'"
    echo
    echo "  # Verify disk size"
    echo "  ssh ${CLOUD_INIT_USER}@${VM_IP} 'df -h /'"
    echo
    echo "  # Test internet connectivity"
    echo "  ssh ${CLOUD_INIT_USER}@${VM_IP} 'ping -c 3 google.com'"
    echo
    echo "Next Steps:"
    echo "  1. Verify VM is accessible via SSH"
    echo "  2. Create worker nodes: ./create-k8s-workers.sh"
    echo "  3. Install Kubernetes: ansible-playbook -i ../../ansible/inventory.ini ..."
    echo
    log_info "Control plane is ready for Kubernetes installation!"
}

# Run main function
main "$@"
