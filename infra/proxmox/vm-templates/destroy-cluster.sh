#!/bin/bash
#
# destroy-cluster.sh - Safely Destroy Kubernetes Cluster VMs
#
# This script provides controlled destruction of Kubernetes cluster VMs
# with safety confirmations and options for selective or complete teardown.
#
# Usage:
#   ./destroy-cluster.sh                    # Interactive mode
#   ./destroy-cluster.sh --all              # Destroy all cluster VMs
#   ./destroy-cluster.sh --workers-only     # Destroy only worker nodes
#   ./destroy-cluster.sh --control-plane    # Destroy only control plane
#   ./destroy-cluster.sh --force            # Skip confirmations (DANGEROUS)
#
# Safety Features:
#   - Multiple confirmation prompts
#   - Shows what will be destroyed before proceeding
#   - Graceful shutdown before destruction
#   - Preserves template by default
#   - Option to backup VM configs before deletion
#
# Author: Mahmood - Kubernetes Homelab Project
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

# VM ID ranges
TEMPLATE_ID="9000"
CONTROL_PLANE_IDS=(1001)  # Add 1002, 1003 for HA setup
WORKER_IDS=(2001 2002)    # Add more worker IDs as needed

# Destruction behavior
FORCE_MODE=false
BACKUP_CONFIGS=true
SHUTDOWN_TIMEOUT=30  # Seconds to wait for graceful shutdown

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
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

log_danger() {
    echo -e "${MAGENTA}[DANGER]${NC} $1"
}

show_banner() {
    echo -e "${RED}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║                                                        ║"
    echo "║        ⚠️  KUBERNETES CLUSTER DESTRUCTION ⚠️           ║"
    echo "║                                                        ║"
    echo "║  This will PERMANENTLY DELETE virtual machines        ║"
    echo "║  and all data stored within them.                     ║"
    echo "║                                                        ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

get_vm_info() {
    local vmid=$1
    
    if ! qm status "$vmid" &> /dev/null; then
        echo "NOT_EXISTS"
        return
    fi
    
    local name=$(qm config "$vmid" | grep "^name:" | awk '{print $2}')
    local status=$(qm status "$vmid" | awk '{print $2}')
    local memory=$(qm config "$vmid" | grep "^memory:" | awk '{print $2}')
    local cores=$(qm config "$vmid" | grep "^cores:" | awk '{print $2}')
    
    echo "$name|$status|${memory}MB|${cores}vCPU"
}

backup_vm_config() {
    local vmid=$1
    local backup_dir="/root/vm-backups"
    
    mkdir -p "$backup_dir"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local config_file="${backup_dir}/vm-${vmid}-config-${timestamp}.conf"
    
    qm config "$vmid" > "$config_file" 2>/dev/null || true
    
    if [[ -f "$config_file" ]]; then
        log_info "  Config backed up: $config_file"
    fi
}

graceful_shutdown() {
    local vmid=$1
    local name=$2
    
    local status=$(qm status "$vmid" | awk '{print $2}')
    
    if [[ "$status" == "running" ]]; then
        log_info "  Shutting down $name (VM $vmid)..."
        qm shutdown "$vmid" || true
        
        # Wait for graceful shutdown
        local waited=0
        while [[ $waited -lt $SHUTDOWN_TIMEOUT ]]; do
            status=$(qm status "$vmid" | awk '{print $2}')
            if [[ "$status" == "stopped" ]]; then
                log_info "  ✓ $name stopped gracefully"
                return 0
            fi
            sleep 2
            waited=$((waited + 2))
        done
        
        # Force stop if timeout
        log_warn "  Graceful shutdown timeout, forcing stop..."
        qm stop "$vmid" || true
        sleep 2
    else
        log_info "  $name already stopped"
    fi
}

destroy_vm() {
    local vmid=$1
    local name=$2
    
    log_info "Destroying $name (VM $vmid)..."
    
    # Backup configuration if enabled
    if [[ "$BACKUP_CONFIGS" == true ]]; then
        backup_vm_config "$vmid"
    fi
    
    # Graceful shutdown
    graceful_shutdown "$vmid" "$name"
    
    # Destroy VM and purge all disks
    log_info "  Removing VM and all associated storage..."
    qm destroy "$vmid" --purge
    
    log_info "  ✓ $name destroyed"
}

confirm_destruction() {
    local message=$1
    
    if [[ "$FORCE_MODE" == true ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}"
    read -p "$message (yes/no): " -r
    echo -e "${NC}"
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        return 1
    fi
    return 0
}

show_vm_list() {
    local title=$1
    shift
    local vm_ids=("$@")
    
    echo -e "${BLUE}$title${NC}"
    echo "┌──────┬─────────────────┬──────────┬──────────┬────────┐"
    echo "│ VMID │ Name            │ Status   │ Memory   │ vCPUs  │"
    echo "├──────┼─────────────────┼──────────┼──────────┼────────┤"
    
    for vmid in "${vm_ids[@]}"; do
        local info=$(get_vm_info "$vmid")
        
        if [[ "$info" == "NOT_EXISTS" ]]; then
            printf "│ %-4s │ %-15s │ %-8s │ %-8s │ %-6s │\n" \
                "$vmid" "N/A" "not found" "-" "-"
        else
            IFS='|' read -r name status memory cores <<< "$info"
            printf "│ %-4s │ %-15s │ %-8s │ %-8s │ %-6s │\n" \
                "$vmid" "$name" "$status" "$memory" "$cores"
        fi
    done
    
    echo "└──────┴─────────────────┴──────────┴──────────┴────────┘"
    echo
}

destroy_control_plane() {
    log_danger "Destroying Control Plane Nodes..."
    echo
    
    show_vm_list "Control Plane VMs:" "${CONTROL_PLANE_IDS[@]}"
    
    if ! confirm_destruction "Destroy control plane? This will make the cluster non-functional"; then
        log_info "Control plane destruction cancelled"
        return 1
    fi
    
    echo
    for vmid in "${CONTROL_PLANE_IDS[@]}"; do
        local info=$(get_vm_info "$vmid")
        if [[ "$info" != "NOT_EXISTS" ]]; then
            IFS='|' read -r name _ _ _ <<< "$info"
            destroy_vm "$vmid" "$name"
            echo
        else
            log_warn "VM $vmid does not exist, skipping"
        fi
    done
    
    log_info "Control plane destroyed"
    return 0
}

destroy_workers() {
    log_warn "Destroying Worker Nodes..."
    echo
    
    show_vm_list "Worker VMs:" "${WORKER_IDS[@]}"
    
    if ! confirm_destruction "Destroy worker nodes?"; then
        log_info "Worker destruction cancelled"
        return 1
    fi
    
    echo
    for vmid in "${WORKER_IDS[@]}"; do
        local info=$(get_vm_info "$vmid")
        if [[ "$info" != "NOT_EXISTS" ]]; then
            IFS='|' read -r name _ _ _ <<< "$info"
            destroy_vm "$vmid" "$name"
            echo
        else
            log_warn "VM $vmid does not exist, skipping"
        fi
    done
    
    log_info "Workers destroyed"
    return 0
}

destroy_all() {
    log_danger "Destroying ENTIRE Kubernetes Cluster..."
    echo
    
    # Show all VMs
    local all_ids=("${CONTROL_PLANE_IDS[@]}" "${WORKER_IDS[@]}")
    show_vm_list "All Cluster VMs:" "${all_ids[@]}"
    
    # First confirmation
    echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  WARNING: This will destroy ALL cluster VMs           ║${NC}"
    echo -e "${RED}║  This action CANNOT be undone!                        ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
    echo
    
    if ! confirm_destruction "Are you absolutely sure you want to destroy the entire cluster?"; then
        log_info "Cluster destruction cancelled"
        return 1
    fi
    
    # Second confirmation (extra safety)
    if [[ "$FORCE_MODE" != true ]]; then
        echo
        echo -e "${RED}Final confirmation required.${NC}"
        read -p "Type 'destroy-cluster' to confirm: " -r
        if [[ "$REPLY" != "destroy-cluster" ]]; then
            log_info "Cluster destruction cancelled (incorrect confirmation)"
            return 1
        fi
    fi
    
    echo
    log_info "Starting cluster destruction..."
    echo
    
    # Destroy workers first (safer, can rebuild without control plane)
    if destroy_workers; then
        echo
    fi
    
    # Then destroy control plane
    if destroy_control_plane; then
        echo
    fi
    
    log_info "Complete cluster destroyed"
}

destroy_template() {
    log_danger "Destroying Template..."
    echo
    
    local info=$(get_vm_info "$TEMPLATE_ID")
    
    if [[ "$info" == "NOT_EXISTS" ]]; then
        log_warn "Template $TEMPLATE_ID does not exist"
        return 1
    fi
    
    IFS='|' read -r name _ _ _ <<< "$info"
    
    echo "Template Details:"
    echo "  VMID: $TEMPLATE_ID"
    echo "  Name: $name"
    echo
    
    echo -e "${RED}WARNING: Destroying the template will require re-downloading${NC}"
    echo -e "${RED}the Ubuntu cloud image and recreating it.${NC}"
    echo
    
    if ! confirm_destruction "Destroy template $TEMPLATE_ID?"; then
        log_info "Template destruction cancelled"
        return 1
    fi
    
    destroy_vm "$TEMPLATE_ID" "$name"
    log_info "Template destroyed"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Kubernetes cluster VMs with confirmation prompts.

OPTIONS:
    --all               Destroy all cluster VMs (control plane + workers)
    --workers-only      Destroy only worker nodes
    --control-plane     Destroy only control plane node(s)
    --template          Destroy Ubuntu template (requires recreation)
    --force             Skip confirmation prompts (DANGEROUS!)
    --no-backup         Skip VM configuration backup
    -h, --help          Show this help message

EXAMPLES:
    # Interactive mode (recommended)
    $0

    # Destroy all cluster VMs
    $0 --all

    # Destroy only workers (preserves control plane)
    $0 --workers-only

    # Complete teardown including template
    $0 --all --template

    # Quick destroy without confirmations (use with caution!)
    $0 --all --force

SAFETY FEATURES:
    - Multiple confirmation prompts (unless --force)
    - VM configs backed up before deletion (unless --no-backup)
    - Graceful shutdown before destruction
    - Template preserved by default
    - Shows what will be destroyed before proceeding

BACKUP LOCATION:
    VM configurations: /root/vm-backups/

EOF
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

main() {
    local mode="interactive"
    local destroy_template_flag=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                mode="all"
                shift
                ;;
            --workers-only)
                mode="workers"
                shift
                ;;
            --control-plane)
                mode="control-plane"
                shift
                ;;
            --template)
                destroy_template_flag=true
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --no-backup)
                BACKUP_CONFIGS=false
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Pre-flight check
    check_root
    
    # Show banner
    show_banner
    
    # Interactive mode
    if [[ "$mode" == "interactive" ]]; then
        echo "What would you like to destroy?"
        echo "  1) All cluster VMs (control plane + workers)"
        echo "  2) Worker nodes only"
        echo "  3) Control plane only"
        echo "  4) Template (requires recreation)"
        echo "  5) Cancel"
        echo
        read -p "Choose option [1-5]: " -r choice
        echo
        
        case $choice in
            1) mode="all" ;;
            2) mode="workers" ;;
            3) mode="control-plane" ;;
            4) destroy_template_flag=true ;;
            5) 
                log_info "Cancelled by user"
                exit 0
                ;;
            *)
                log_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    # Execute destruction based on mode
    case $mode in
        all)
            destroy_all
            ;;
        workers)
            destroy_workers
            ;;
        control-plane)
            destroy_control_plane
            ;;
    esac
    
    # Destroy template if requested
    if [[ "$destroy_template_flag" == true ]]; then
        echo
        destroy_template
    fi
    
    # Final summary
    echo
    log_info "=========================================="
    log_info "  Destruction Complete"
    log_info "=========================================="
    echo
    
    if [[ "$BACKUP_CONFIGS" == true ]]; then
        echo "VM configurations backed up to: /root/vm-backups/"
    fi
    
    echo
    echo "To rebuild cluster:"
    echo "  1. Create template:       ./create-template.sh"
    echo "  2. Create control plane:  ./create-k8s-controlplane.sh"
    echo "  3. Create workers:        ./create-k8s-workers.sh"
    echo "  4. Install Kubernetes:    cd ../../ansible && ansible-playbook ..."
    echo
}

# Run main function
main "$@"
