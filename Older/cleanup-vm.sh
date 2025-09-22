#!/bin/bash

# Management VM Cleanup Script
# This script cleans up all resources created by the management-vm.bicep deployment

set -e  # Exit on any error

# Configuration
RESOURCE_GROUP="ccp4i2-django-rg"
VM_NAME="management-vm"
NSG_NAME="${VM_NAME}-nsg"
PUBLIC_IP_NAME="${VM_NAME}-pip"
NIC_NAME="${VM_NAME}-nic"
OS_DISK_NAME="${VM_NAME}-osdisk"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Confirmation function
confirm() {
    local message=$1
    read -p "$message (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    az resource show --resource-group $RESOURCE_GROUP --name $resource_name --resource-type $resource_type >/dev/null 2>&1
}

# Main cleanup function
cleanup_resources() {
    log_info "Starting cleanup of management VM resources..."

    # Check what resources exist
    log_info "Checking existing resources..."
    local vm_exists=false
    local nsg_exists=false
    local pip_exists=false
    local nic_exists=false
    local disk_exists=false

    if resource_exists "Microsoft.Compute/virtualMachines" $VM_NAME; then
        vm_exists=true
        log_info "Found VM: $VM_NAME"
    fi

    if resource_exists "Microsoft.Network/networkSecurityGroups" $NSG_NAME; then
        nsg_exists=true
        log_info "Found NSG: $NSG_NAME"
    fi

    if resource_exists "Microsoft.Network/publicIPAddresses" $PUBLIC_IP_NAME; then
        pip_exists=true
        log_info "Found Public IP: $PUBLIC_IP_NAME"
    fi

    if resource_exists "Microsoft.Network/networkInterfaces" $NIC_NAME; then
        nic_exists=true
        log_info "Found NIC: $NIC_NAME"
    fi

    if resource_exists "Microsoft.Compute/disks" $OS_DISK_NAME; then
        disk_exists=true
        log_info "Found OS Disk: $OS_DISK_NAME"
    fi

    # If no resources found, exit
    if ! $vm_exists && ! $nsg_exists && ! $pip_exists && ! $nic_exists && ! $disk_exists; then
        log_success "No management VM resources found. Nothing to clean up."
        exit 0
    fi

    # Show what will be deleted
    echo
    log_warning "The following resources will be deleted:"
    if $vm_exists; then echo "  - Virtual Machine: $VM_NAME"; fi
    if $disk_exists; then echo "  - OS Disk: $OS_DISK_NAME"; fi
    if $nic_exists; then echo "  - Network Interface: $NIC_NAME"; fi
    if $nsg_exists; then echo "  - Network Security Group: $NSG_NAME"; fi
    if $pip_exists; then echo "  - Public IP: $PUBLIC_IP_NAME"; fi
    echo

    # Confirm deletion
    if ! confirm "Do you want to proceed with deletion?"; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi

    # Delete VM first (this will also delete OS disk and NIC)
    if $vm_exists; then
        log_info "Deleting Virtual Machine: $VM_NAME..."
        az vm delete --resource-group $RESOURCE_GROUP --name $VM_NAME --yes --no-wait
        log_success "VM deletion initiated: $VM_NAME"
    fi

    # Wait a moment for VM deletion to start
    sleep 5

    # Delete remaining resources
    if $nic_exists; then
        log_info "Deleting Network Interface: $NIC_NAME..."
        if az network nic delete --resource-group $RESOURCE_GROUP --name $NIC_NAME 2>/dev/null; then
            log_success "Deleted NIC: $NIC_NAME"
        else
            log_warning "NIC deletion failed (may still be associated with VM)"
        fi
    fi

    if $nsg_exists; then
        log_info "Deleting Network Security Group: $NSG_NAME..."
        # Retry logic for NSG deletion in case it's still associated
        local retry_count=0
        local max_retries=3
        while [ $retry_count -lt $max_retries ]; do
            if az network nsg delete --resource-group $RESOURCE_GROUP --name $NSG_NAME 2>/dev/null; then
                log_success "Deleted NSG: $NSG_NAME"
                break
            else
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    log_warning "NSG deletion failed, retrying in 10 seconds... ($retry_count/$max_retries)"
                    sleep 10
                else
                    log_error "Failed to delete NSG: $NSG_NAME after $max_retries attempts"
                fi
            fi
        done
    fi

    if $pip_exists; then
        log_info "Deleting Public IP: $PUBLIC_IP_NAME..."
        az network public-ip delete --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME
        log_success "Deleted Public IP: $PUBLIC_IP_NAME"
    fi

    if $disk_exists && ! $vm_exists; then
        log_info "Deleting OS Disk: $OS_DISK_NAME..."
        az disk delete --resource-group $RESOURCE_GROUP --name $OS_DISK_NAME --yes
        log_success "Deleted OS Disk: $OS_DISK_NAME"
    fi

    # Final verification
    echo
    log_info "Verifying cleanup..."
    local remaining_resources=$(az resource list --resource-group $RESOURCE_GROUP --query "[?tags.environment=='management']" -o json | jq length)

    if [ "$remaining_resources" -eq 0 ]; then
        log_success "All management VM resources have been successfully cleaned up!"
    else
        log_warning "Some resources may still remain. Run the script again or check manually."
        az resource list --resource-group $RESOURCE_GROUP --query "[?tags.environment=='management']" -o table
    fi
}

# Help function
show_help() {
    echo "Management VM Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -y, --yes           Skip confirmation prompts"
    echo "  -g, --resource-group NAME    Specify resource group (default: ccp4i2-django-rg)"
    echo
    echo "This script will delete all resources created by the management-vm.bicep deployment:"
    echo "  - Virtual Machine"
    echo "  - OS Disk"
    echo "  - Network Interface"
    echo "  - Network Security Group"
    echo "  - Public IP Address"
    echo
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with confirmation"
    echo "  $0 -y                 # Non-interactive cleanup"
    echo "  $0 -g my-rg           # Cleanup in different resource group"
}

# Parse command line arguments
SKIP_CONFIRMATION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation if -y flag is used
if $SKIP_CONFIRMATION; then
    confirm() {
        return 0
    }
fi

# Main execution
log_info "Management VM Cleanup Script"
log_info "Resource Group: $RESOURCE_GROUP"
echo

# Check if resource group exists
if ! az group show --name $RESOURCE_GROUP >/dev/null 2>&1; then
    log_error "Resource group '$RESOURCE_GROUP' does not exist."
    exit 1
fi

cleanup_resources

log_success "Cleanup script completed!"
