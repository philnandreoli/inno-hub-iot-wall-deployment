#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Uninstall Script - Version 2
# ============================================================================
# This script removes all resources created by the v2 deployment:
# 1. Disconnects and removes Arc-enabled k3s cluster
# 2. Disconnects and removes VM from Azure Arc
# 3. Deletes Key Vault (soft delete)
# 4. Deletes Storage Account
# 5. Stops and deletes the VM on the host
# 6. Removes VM disk
# 7. Optionally removes network bridges
#
# Note: This script does NOT remove:
# - The Azure Resource Group
# - The Arc-enabled Host
#
# Prerequisites:
# - Run this script on the physical host
# - Azure CLI installed and logged in
# - Service Principal credentials
#
# Usage:
#   ./uninstall.sh \
#     --service-principal-id <sp-id> \
#     --service-principal-secret <sp-secret> \
#     --subscription-id <subscription-id> \
#     --tenant-id <tenant-id> \
#     --data-center <datacenter> \
#     --country <country>
#
# Example:
#   ./uninstall.sh \
#     --service-principal-id "12345678-1234-1234-1234-123456789abc" \
#     --service-principal-secret "your-secret-here" \
#     --subscription-id "12345678-1234-1234-1234-123456789abc" \
#     --tenant-id "12345678-1234-1234-1234-123456789abc" \
#     --data-center "CHI" \
#     --country "US"
# ============================================================================

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required Options:"
    echo "  --service-principal-id ID          Azure Service Principal Application ID"
    echo "  --service-principal-secret SECRET  Azure Service Principal Secret"
    echo "  --subscription-id ID               Azure Subscription ID"
    echo "  --tenant-id ID                     Azure Tenant ID"
    echo "  --data-center CODE                 Datacenter code (e.g., CHI, STL, AMS)"
    echo "  --country CODE                     2-letter country code (e.g., US, NL)"
    echo ""
    echo "Optional Options:"
    echo "  --delete-network-bridges           Delete network bridges br-it and br-ot"
    echo "  --skip-azure-cleanup               Skip Azure resource cleanup (only delete local VM)"
    echo "  -h, --help                         Display this help message"
    echo ""
    echo "Note: Resource group name will be derived as EXP-MFG-AIO-\${DATA_CENTER}-\${COUNTRY}-RG"
    echo "Note: This script will NOT delete the resource group or remove the host from Arc"
    exit 1
}

# Default values
DELETE_NETWORK_BRIDGES=false
SKIP_AZURE_CLEANUP=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service-principal-id)
            ARG_SERVICE_PRINCIPAL_ID="$2"
            shift 2
            ;;
        --service-principal-secret)
            ARG_SERVICE_PRINCIPAL_SECRET="$2"
            shift 2
            ;;
        --subscription-id)
            ARG_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --tenant-id)
            ARG_TENANT_ID="$2"
            shift 2
            ;;
        --data-center)
            ARG_DATA_CENTER="$2"
            shift 2
            ;;
        --country)
            ARG_COUNTRY="$2"
            shift 2
            ;;
        --delete-network-bridges)
            DELETE_NETWORK_BRIDGES=true
            shift
            ;;
        --skip-azure-cleanup)
            SKIP_AZURE_CLEANUP=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET}"
            usage
            ;;
    esac
done

# Use command-line arguments if provided, otherwise fall back to environment variables
export SERVICE_PRINCIPAL_ID="${ARG_SERVICE_PRINCIPAL_ID:-${SERVICE_PRINCIPAL_ID}}"
export SERVICE_PRINCIPAL_CLIENT_SECRET="${ARG_SERVICE_PRINCIPAL_SECRET:-${SERVICE_PRINCIPAL_CLIENT_SECRET}}"
export SUBSCRIPTION_ID="${ARG_SUBSCRIPTION_ID:-${SUBSCRIPTION_ID}}"
export TENANT_ID="${ARG_TENANT_ID:-${TENANT_ID}}"
export DATA_CENTER="${ARG_DATA_CENTER:-${DATA_CENTER}}"
export COUNTRY="${ARG_COUNTRY:-${COUNTRY}}"

# Derive resource group name
export RESOURCE_GROUP="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"

# Get host and VM names
export HOST_NAME=$(hostname -s)
export VM_NAME="${HOST_NAME}-vm"
export VM_DISK_PATH="/data/${VM_NAME}.qcow2"

# Derive Azure resource names (matching step5 naming convention)
export CLUSTER_NAME=$(echo "${DATA_CENTER}-${VM_NAME}-k3s" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
export KEYVAULT_NAME=$(echo "${DATA_CENTER}-${VM_NAME}-kv" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
export STORAGE_ACCOUNT_NAME=$(echo "${DATA_CENTER}${VM_NAME}sa" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)

echo -e "${GREEN}======================================================================================================"
echo -e " Uninstall Script - Configuration Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Resource Group: ${RESOURCE_GROUP}${RESET}"
echo -e "${GREEN}Host Name: ${HOST_NAME}${RESET}"
echo -e "${GREEN}VM Name: ${VM_NAME}${RESET}"
echo -e "${GREEN}VM Disk Path: ${VM_DISK_PATH}${RESET}"
echo -e "${GREEN}Cluster Name: ${CLUSTER_NAME}${RESET}"
echo -e "${GREEN}Key Vault Name: ${KEYVAULT_NAME}${RESET}"
echo -e "${GREEN}Storage Account: ${STORAGE_ACCOUNT_NAME}${RESET}"
echo -e "${GREEN}Delete Network Bridges: ${DELETE_NETWORK_BRIDGES}${RESET}"
echo -e "${GREEN}Skip Azure Cleanup: ${SKIP_AZURE_CLEANUP}${RESET}"
echo ""

# Validation for Azure cleanup
if [ "$SKIP_AZURE_CLEANUP" = false ]; then
    if [ -z "$SERVICE_PRINCIPAL_ID" ] || [ -z "$SERVICE_PRINCIPAL_CLIENT_SECRET" ] || \
       [ -z "$SUBSCRIPTION_ID" ] || [ -z "$TENANT_ID" ] || \
       [ -z "$DATA_CENTER" ] || [ -z "$COUNTRY" ]; then
        echo -e "${RED}ERROR: Required Azure parameters are missing.${RESET}"
        echo -e "${RED}Please provide all required arguments or use --skip-azure-cleanup flag.${RESET}"
        echo ""
        usage
    fi
fi

# Confirmation prompt
echo -e "${YELLOW}======================================================================================================"
echo -e " WARNING: This will permanently delete resources!"
echo -e "======================================================================================================${RESET}"
echo -e "${YELLOW}This script will:"
echo -e "  - Stop and delete the VM: ${VM_NAME}"
echo -e "  - Delete the VM disk: ${VM_DISK_PATH}"
if [ "$SKIP_AZURE_CLEANUP" = false ]; then
    echo -e "  - Disconnect k3s cluster from Azure Arc: ${CLUSTER_NAME}"
    echo -e "  - Disconnect VM from Azure Arc"
    echo -e "  - Delete Key Vault: ${KEYVAULT_NAME} (soft delete)"
    echo -e "  - Delete Storage Account: ${STORAGE_ACCOUNT_NAME}"
fi
if [ "$DELETE_NETWORK_BRIDGES" = true ]; then
    echo -e "  - Delete network bridges: br-it, br-ot"
fi
echo -e ""
echo -e "${YELLOW}This script will NOT:"
echo -e "  - Delete the resource group: ${RESOURCE_GROUP}"
echo -e "  - Remove the host from Azure Arc"
echo -e "  - Delete Azure IoT Operations instance (must be deleted manually)"
echo -e "${RESET}"

read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo -e "${RED}Uninstall cancelled.${RESET}"
    exit 0
fi

# ============================================================================
# Azure Resource Cleanup
# ============================================================================

if [ "$SKIP_AZURE_CLEANUP" = false ]; then
    echo -e "${GREEN}======================================================================================================"
    echo -e "Step 1: Logging into Azure"
    echo -e "======================================================================================================${RESET}"
    
    az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
    az account set --subscription "$SUBSCRIPTION_ID"

    echo -e "${GREEN}======================================================================================================"
    echo -e "Step 2: Removing Arc-enabled k3s Cluster"
    echo -e "======================================================================================================${RESET}"
    
    # Check if k3s cluster exists in Azure Arc
    CLUSTER_EXISTS=$(az connectedk8s show --name "${CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}" --query "id" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$CLUSTER_EXISTS" ]; then
        echo -e "${YELLOW}Disconnecting and deleting k3s cluster ${CLUSTER_NAME} from Azure Arc...${RESET}"
        az connectedk8s delete --name "${CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}" --yes
        echo -e "${GREEN}k3s cluster removed from Azure Arc${RESET}"
    else
        echo -e "${YELLOW}k3s cluster ${CLUSTER_NAME} not found in Azure Arc, skipping...${RESET}"
    fi

    echo -e "${GREEN}======================================================================================================"
    echo -e "Step 3: Removing VM from Azure Arc"
    echo -e "======================================================================================================${RESET}"
    
    # Check if VM exists in Azure Arc
    VM_EXISTS=$(az connectedmachine show --name "${VM_NAME}" --resource-group "${RESOURCE_GROUP}" --query "id" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$VM_EXISTS" ]; then
        echo -e "${YELLOW}Disconnecting and deleting VM ${VM_NAME} from Azure Arc...${RESET}"
        az connectedmachine delete --name "${VM_NAME}" --resource-group "${RESOURCE_GROUP}" --yes
        echo -e "${GREEN}VM removed from Azure Arc${RESET}"
    else
        echo -e "${YELLOW}VM ${VM_NAME} not found in Azure Arc, skipping...${RESET}"
    fi

    echo -e "${GREEN}======================================================================================================"
    echo -e "Step 4: Deleting Key Vault"
    echo -e "======================================================================================================${RESET}"
    
    # Check if Key Vault exists
    KV_EXISTS=$(az keyvault show --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}" --query "id" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$KV_EXISTS" ]; then
        echo -e "${YELLOW}Deleting Key Vault ${KEYVAULT_NAME}...${RESET}"
        az keyvault delete --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}"
        echo -e "${GREEN}Key Vault deleted (soft delete enabled, can be recovered for 90 days)${RESET}"
        echo -e "${YELLOW}To permanently delete: az keyvault purge --name ${KEYVAULT_NAME}${RESET}"
    else
        echo -e "${YELLOW}Key Vault ${KEYVAULT_NAME} not found, skipping...${RESET}"
    fi

    echo -e "${GREEN}======================================================================================================"
    echo -e "Step 5: Deleting Storage Account"
    echo -e "======================================================================================================${RESET}"
    
    # Check if Storage Account exists
    SA_EXISTS=$(az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --query "id" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$SA_EXISTS" ]; then
        echo -e "${YELLOW}Deleting Storage Account ${STORAGE_ACCOUNT_NAME}...${RESET}"
        az storage account delete --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --yes
        echo -e "${GREEN}Storage Account deleted${RESET}"
    else
        echo -e "${YELLOW}Storage Account ${STORAGE_ACCOUNT_NAME} not found, skipping...${RESET}"
    fi
fi

# ============================================================================
# Local VM Cleanup
# ============================================================================

echo -e "${GREEN}======================================================================================================"
echo -e "Step 6: Stopping and Deleting Virtual Machine"
echo -e "======================================================================================================${RESET}"

# Check if VM exists
if sudo virsh list --all | grep -q "${VM_NAME}"; then
    echo -e "${YELLOW}Stopping VM ${VM_NAME}...${RESET}"
    sudo virsh shutdown "${VM_NAME}" 2>/dev/null || true
    sleep 5
    
    # Force destroy if still running
    if sudo virsh list --state-running | grep -q "${VM_NAME}"; then
        echo -e "${YELLOW}Force destroying VM ${VM_NAME}...${RESET}"
        sudo virsh destroy "${VM_NAME}" 2>/dev/null || true
    fi
    
    echo -e "${YELLOW}Undefining VM ${VM_NAME}...${RESET}"
    sudo virsh undefine "${VM_NAME}" 2>/dev/null || true
    echo -e "${GREEN}VM ${VM_NAME} deleted${RESET}"
else
    echo -e "${YELLOW}VM ${VM_NAME} not found, skipping...${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 7: Deleting VM Disk"
echo -e "======================================================================================================${RESET}"

if [ -f "$VM_DISK_PATH" ]; then
    echo -e "${YELLOW}Deleting VM disk at ${VM_DISK_PATH}...${RESET}"
    sudo rm -f "$VM_DISK_PATH"
    echo -e "${GREEN}VM disk deleted${RESET}"
else
    echo -e "${YELLOW}VM disk not found at ${VM_DISK_PATH}, skipping...${RESET}"
fi

# ============================================================================
# Network Cleanup (Optional)
# ============================================================================

if [ "$DELETE_NETWORK_BRIDGES" = true ]; then
    echo -e "${GREEN}======================================================================================================"
    echo -e "Step 8: Removing Network Bridges"
    echo -e "======================================================================================================${RESET}"
    
    for BRIDGE in br-it br-ot; do
        if ip link show "$BRIDGE" &> /dev/null; then
            echo -e "${YELLOW}Removing bridge ${BRIDGE}...${RESET}"
            sudo ip link set "$BRIDGE" down 2>/dev/null || true
            sudo brctl delbr "$BRIDGE" 2>/dev/null || true
            echo -e "${GREEN}Bridge ${BRIDGE} removed${RESET}"
        else
            echo -e "${YELLOW}Bridge ${BRIDGE} not found, skipping...${RESET}"
        fi
    done
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 9: Cleaning Up Cloud-Init and Temporary Files"
echo -e "======================================================================================================${RESET}"

# Remove cloud-init files
if [ -d "/var/lib/cloud/instances" ]; then
    echo -e "${YELLOW}Removing cloud-init instance data...${RESET}"
    sudo rm -rf /var/lib/cloud/instances/* 2>/dev/null || true
fi

# Remove SSH keys if they were created
if [ -f ~/.ssh/vm-key ]; then
    echo -e "${YELLOW}Removing VM SSH keys...${RESET}"
    rm -f ~/.ssh/vm-key ~/.ssh/vm-key.pub 2>/dev/null || true
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Uninstall Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Summary:${RESET}"
echo -e "${GREEN}  ✓ VM ${VM_NAME} stopped and deleted${RESET}"
echo -e "${GREEN}  ✓ VM disk removed${RESET}"

if [ "$SKIP_AZURE_CLEANUP" = false ]; then
    echo -e "${GREEN}  ✓ k3s cluster removed from Azure Arc${RESET}"
    echo -e "${GREEN}  ✓ VM removed from Azure Arc${RESET}"
    echo -e "${GREEN}  ✓ Key Vault deleted (soft delete enabled)${RESET}"
    echo -e "${GREEN}  ✓ Storage Account deleted${RESET}"
fi

if [ "$DELETE_NETWORK_BRIDGES" = true ]; then
    echo -e "${GREEN}  ✓ Network bridges removed${RESET}"
fi

echo ""
echo -e "${YELLOW}Note: You may need to manually clean up:${RESET}"
echo -e "${YELLOW}  - Azure IoT Operations instance (if deployed)${RESET}"
echo -e "${YELLOW}  - Schema Registry (if created)${RESET}"
echo -e "${YELLOW}  - User Assigned Managed Identity${RESET}"
echo -e "${YELLOW}  - Resource group ${RESOURCE_GROUP} (if you want to delete everything)${RESET}"
if [ "$SKIP_AZURE_CLEANUP" = false ]; then
    echo -e "${YELLOW}  - Key Vault (purge permanently): az keyvault purge --name ${KEYVAULT_NAME}${RESET}"
fi
echo -e "${YELLOW}  - Service Principal (if no longer needed)${RESET}"
echo ""
