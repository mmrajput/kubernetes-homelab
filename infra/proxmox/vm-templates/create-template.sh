#!/bin/bash
#
# create-template.sh - Create Ubuntu 24.04 Cloud-Init Template
#
# This script downloads the Ubuntu cloud image and creates a reusable
# Proxmox VM template that serves as the base for all Kubernetes nodes.
#
# Usage:
#   ./create-template.sh
#
# Prerequisites:
#   - Run as root on Proxmox host
#   - Internet connectivity
#   - At least 10GB free in local-lvm storage
#
# Output:
#   - VM Template ID 9000: ubuntu-2404-template
#
# Author: Mahmood - Kubernetes Homelab Project
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

# Template specifications
TEMPLATE_ID="9000"
TEMPLATE_NAME="ubuntu-2404-template"

# Ubuntu cloud image
UBUNTU_VERSION="24.04"
IMAGE_URL="https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
CHECKSUM_URL="https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/SHA256SUMS"

# Storage locations
ISO_STORAGE="/var/lib/vz/template/iso"
IMAGE_FILE="${ISO_STORAGE}/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"

# Template hardware specs (minimal - will be increased during cloning)
TEMPLATE_MEMORY=2048      # 2GB RAM
TEMPLATE_CORES=2          # 2 vCPUs
TEMPLATE_DISK_SIZE="10G"  # Will be resized during clone

# Network configuration
NETWORK_BRIDGE="vmbr0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_proxmox() {
    if ! command -v qm &> /dev/null; then
        log_error "Proxmox 'qm' command not found. Are you running this on a Proxmox host?"
        exit 1
    fi
}

check_template_exists() {
    if qm status "$TEMPLATE_ID" &> /dev/null; then
        log_warn "Template ID $TEMPLATE_ID already exists!"
        read -p "Do you want to destroy it and recreate? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Destroying existing template $TEMPLATE_ID..."
            qm destroy "$TEMPLATE_ID" --purge
        else
            log_error "Template already exists. Exiting."
            exit 1
        fi
    fi
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

main() {
    log_info "Starting Ubuntu 24.04 Cloud-Init template creation..."
    echo

    # Pre-flight checks
    check_root
    check_proxmox
    check_template_exists

    # Step 1: Download Ubuntu cloud image
    log_info "Step 1/6: Downloading Ubuntu ${UBUNTU_VERSION} cloud image..."
    cd "$ISO_STORAGE"

    if [[ -f "$IMAGE_FILE" ]]; then
        log_warn "Image already exists at $IMAGE_FILE"
        read -p "Re-download? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            rm -f "$IMAGE_FILE"
        else
            log_info "Using existing image"
        fi
    fi

    if [[ ! -f "$IMAGE_FILE" ]]; then
        wget --progress=bar:force "$IMAGE_URL" -O "$IMAGE_FILE"
    fi

    # Step 2: Verify checksum (security best practice)
    log_info "Step 2/6: Verifying image checksum..."
    wget -q "$CHECKSUM_URL" -O SHA256SUMS
    
    if sha256sum --ignore-missing -c SHA256SUMS 2>&1 | grep -q "OK"; then
        log_info "✓ Checksum verification passed"
    else
        log_error "Checksum verification failed! Image may be corrupted."
        exit 1
    fi

    # Step 3: Create VM
    log_info "Step 3/6: Creating VM $TEMPLATE_ID ($TEMPLATE_NAME)..."
    qm create "$TEMPLATE_ID" \
        --name "$TEMPLATE_NAME" \
        --memory "$TEMPLATE_MEMORY" \
        --cores "$TEMPLATE_CORES" \
        --cpu cputype=host \
        --net0 virtio,bridge="$NETWORK_BRIDGE" \
        --scsihw virtio-scsi-pci \
        --ostype l26

    # Step 4: Import cloud image as disk
    log_info "Step 4/6: Importing cloud image as VM disk..."
    qm importdisk "$TEMPLATE_ID" "$IMAGE_FILE" local-lvm

    # Step 5: Configure template
    log_info "Step 5/6: Configuring template..."
    
    # Attach imported disk
    qm set "$TEMPLATE_ID" --scsi0 local-lvm:vm-${TEMPLATE_ID}-disk-0
    
    # Resize disk to base size
    qm resize "$TEMPLATE_ID" scsi0 "$TEMPLATE_DISK_SIZE"
    
    # Add cloud-init drive
    qm set "$TEMPLATE_ID" --ide2 local-lvm:cloudinit
    
    # Set boot order (skip PXE boot for faster startup)
    qm set "$TEMPLATE_ID" --boot order=scsi0
    
    # Enable QEMU guest agent (better VM management)
    qm set "$TEMPLATE_ID" --agent enabled=1
    
    # Add serial console for qm terminal access
    qm set "$TEMPLATE_ID" --serial0 socket --vga serial0

    # Set cloud-init defaults (will be overridden during clone)
    # These ensure cloud-init is properly initialized in the template
    qm set "$TEMPLATE_ID" --ciuser ubuntu
    qm set "$TEMPLATE_ID" --ipconfig0 ip=dhcp
    qm set "$TEMPLATE_ID" --nameserver "8.8.8.8 1.1.1.1"
    qm set "$TEMPLATE_ID" --searchdomain home.lab

    # Step 6: Convert to template
    log_info "Step 6/6: Converting VM to template..."
    qm template "$TEMPLATE_ID"

    # Success summary
    echo
    log_info "=========================================="
    log_info "  Template Creation Complete!"
    log_info "=========================================="
    echo
    echo "Template Details:"
    echo "  - Template ID:    $TEMPLATE_ID"
    echo "  - Template Name:  $TEMPLATE_NAME"
    echo "  - Base Image:     Ubuntu ${UBUNTU_VERSION} LTS"
    echo "  - Memory:         ${TEMPLATE_MEMORY}MB"
    echo "  - vCPUs:          $TEMPLATE_CORES"
    echo "  - Disk Size:      $TEMPLATE_DISK_SIZE"
    echo "  - Cloud-Init:     ✓ Enabled"
    echo "  - QEMU Agent:     ✓ Enabled"
    echo
    echo "Next Steps:"
    echo "  1. Create control plane:  ./create-k8s-controlplane.sh"
    echo "  2. Create worker nodes:   ./create-k8s-workers.sh"
    echo
    log_info "Template is ready for cloning!"
}

# Run main function
main "$@"
