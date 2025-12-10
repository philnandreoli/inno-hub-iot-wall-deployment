#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Deploy Azure IoT Operations - Step 5
# ============================================================================
# This script deploys Azure IoT Operations on the VM's k3s cluster.
# It creates the necessary Azure resources (Key Vault, Storage Account,
# Schema Registry) and deploys the IoT Operations instance.
# It runs FROM THE HOST and connects to the VM via SSH.
#
# Prerequisites:
# - VM must have k3s installed and Arc-enabled (step4 completed)
# - SSH connectivity to VM must be working
#
# Usage:
#   ./step5-iot-operations-deployment.sh \\
#     --service-principal-id <sp-id> \\
#     --service-principal-secret <sp-secret> \\
#     --subscription-id <subscription-id> \\
#     --tenant-id <tenant-id> \\
#     --resource-group <resource-group> \\
#     --location <location> \\
#     --data-center <datacenter> \\
#     --city <city> \\
#     --state-region <state-region> \\
#     --country <country>
#
# Example:
#   ./step5-iot-operations-deployment.sh \\
#     --service-principal-id "12345678-1234-1234-1234-123456789abc" \\
#     --service-principal-secret "your-secret-here" \\
#     --subscription-id "12345678-1234-1234-1234-123456789abc" \\
#     --tenant-id "12345678-1234-1234-1234-123456789abc" \\
#     --resource-group "EXP-MFG-AIO-RG" \\
#     --location "eastus2" \\
#     --data-center "CHI" \\
#     --city "Chicago" \\
#     --state-region "IL" \\
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
    echo "  --location LOCATION                Azure region (e.g., eastus2, northeurope)"
    echo "  --data-center CODE                 Datacenter code (e.g., CHI, STL, AMS)"
    echo "  --city NAME                        City name (e.g., Chicago, St. Louis)"
    echo "  --state-region CODE                State/Region code (e.g., IL, MO)"
    echo "  --country CODE                     2-letter country code (e.g., US, NL)"
    echo ""
    echo "Optional Options:"
    echo "  --ot-network-vm-ip IP              OT network IP for VM (default: 192.168.30.18)"
    echo "  --ssh-key-path PATH                Path to SSH private key (default: ~/.ssh/vm_id_rsa)"
    echo "  --iot-id ID                        IoT custom locations OID (default: a4e6246e-0a1b-48c6-8fd6-9b0631d78d05)"
    echo "  -h, --help                         Display this help message"
    echo ""
    echo "Note: Arguments can be provided via command-line or environment variables."
    echo "      Command-line arguments take precedence over environment variables."
    exit 1
}

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
        --location)
            ARG_LOCATION="$2"
            shift 2
            ;;
        --data-center)
            ARG_DATA_CENTER="$2"
            shift 2
            ;;
        --city)
            ARG_CITY="$2"
            shift 2
            ;;
        --state-region)
            ARG_STATE_REGION="$2"
            shift 2
            ;;
        --country)
            ARG_COUNTRY="$2"
            shift 2
            ;;
        --ot-network-vm-ip)
            ARG_OT_NETWORK_VM_IP="$2"
            shift 2
            ;;
        --ssh-key-path)
            ARG_SSH_KEY_PATH="$2"
            shift 2
            ;;
        --iot-id)
            ARG_IOT_ID="$2"
            shift 2
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
export LOCATION="${ARG_LOCATION:-${LOCATION:-eastus2}}"
export DATA_CENTER="${ARG_DATA_CENTER:-${DATA_CENTER}}"
export CITY="${ARG_CITY:-${CITY}}"
export STATE_REGION="${ARG_STATE_REGION:-${STATE_REGION}}"
export COUNTRY="${ARG_COUNTRY:-${COUNTRY}}"

# VM Configuration
export HOST_NAME=$(hostname -s)
export VM_NAME="${HOST_NAME}-vm"
export OT_NETWORK_VM_IP="${ARG_OT_NETWORK_VM_IP:-${OT_NETWORK_VM_IP:-192.168.30.18}}"
export SSH_KEY_PATH="${ARG_SSH_KEY_PATH:-${SSH_KEY_PATH:-$HOME/.ssh/vm_id_rsa}}"

# Azure IoT Operations Resource Names
export CLUSTER_NAME="${DATA_CENTER}-${VM_NAME}-k3s"
export KEYVAULT_NAME="${DATA_CENTER}-${VM_NAME}-kv"
export STORAGE_ACCOUNT_NAME="${DATA_CENTER}${VM_NAME}sa"
export IOTOPS_CLUSTER_NAME="${DATA_CENTER}-${VM_NAME}-aio-cluster"
export REGISTRY_NAME="${DATA_CENTER}${VM_NAME}registry"
export REGISTRY_NAMESPACE="${DATA_CENTER}${VM_NAME}regnamespace"
export NE_IOT_INSTANCE="${DATA_CENTER}-${VM_NAME}-aio-instance"
export NE_IOT_NAMESPACE="${DATA_CENTER}-${VM_NAME}-aio-namespace"
export USER_ASSIGNED_MANAGED_IDENTITY="${DATA_CENTER}-${VM_NAME}-uami"
export IOT_ID="${ARG_IOT_ID:-${IOT_ID:-a4e6246e-0a1b-48c6-8fd6-9b0631d78d05}}"

# Convert to lowercase and sanitize names
CLUSTER_NAME=$(echo "${CLUSTER_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
KEYVAULT_NAME=$(echo "${KEYVAULT_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
USER_ASSIGNED_MANAGED_IDENTITY=$(echo "${USER_ASSIGNED_MANAGED_IDENTITY}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
NE_IOT_INSTANCE=$(echo "${NE_IOT_INSTANCE}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
NE_IOT_NAMESPACE=$(echo "${NE_IOT_NAMESPACE}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')

# Storage and registry names must be lowercase, alphanumeric, and <= 24 chars
STORAGE_ACCOUNT_NAME=$(echo "${STORAGE_ACCOUNT_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)
REGISTRY_NAME=$(echo "${REGISTRY_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)
REGISTRY_NAMESPACE=$(echo "${REGISTRY_NAMESPACE}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)

echo -e "${GREEN}======================================================================================================"
echo -e " Deploy Azure IoT Operations - Configuration Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}VM Name: ${VM_NAME}${RESET}"
echo -e "${GREEN}VM IP Address: ${OT_NETWORK_VM_IP}${RESET}"
echo -e "${GREEN}Cluster Name: ${CLUSTER_NAME}${RESET}"
echo -e "${GREEN}Key Vault Name: ${KEYVAULT_NAME}${RESET}"
echo -e "${GREEN}Storage Account: ${STORAGE_ACCOUNT_NAME}${RESET}"
echo -e "${GREEN}Registry Name: ${REGISTRY_NAME}${RESET}"
echo -e "${GREEN}IoT Instance: ${NE_IOT_INSTANCE}${RESET}"
echo -e "${GREEN}IoT Namespace: ${NE_IOT_NAMESPACE}${RESET}"
echo -e "${GREEN}Resource Group: ${RESOURCE_GROUP}${RESET}"
echo -e "${GREEN}Location: ${LOCATION}${RESET}"
echo -e "${GREEN}SSH Key Path: ${SSH_KEY_PATH}${RESET}"
echo ""

# Validation
if [ -z "$SERVICE_PRINCIPAL_ID" ] || [ -z "$SERVICE_PRINCIPAL_CLIENT_SECRET" ] || \
   [ -z "$SUBSCRIPTION_ID" ] || [ -z "$TENANT_ID" ] || \
   [ -z "$DATA_CENTER" ] || [ -z "$CITY" ] || [ -z "$STATE_REGION" ] || [ -z "$COUNTRY" ]; then
    echo -e "${RED}ERROR: Required parameters are missing.${RESET}"
    echo -e "${RED}Please provide all required arguments or set environment variables.${RESET}"
    echo ""
    usage
fi

RESOURCE_GROUP="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"
echo -e "${GREEN}Resource Group Name: ${RESOURCE_GROUP}${RESET}"


if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}ERROR: SSH key not found at ${SSH_KEY_PATH}${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 1: Logging into Azure (on Host)"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription "$SUBSCRIPTION_ID"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 2: Creating User Assigned Managed Identity"
echo -e "======================================================================================================${RESET}"
EXISTING_UAMI=$(az identity list --resource-group "${RESOURCE_GROUP}" --query "[?name=='${USER_ASSIGNED_MANAGED_IDENTITY}'].name" -o tsv)
if [ -z "${EXISTING_UAMI}" ]; then
    az identity create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${USER_ASSIGNED_MANAGED_IDENTITY}" \
        --location "${LOCATION}" || {
        echo -e "${RED}Failed to create User Assigned Managed Identity${RESET}"
        exit 1
    }
    echo -e "${GREEN}User Assigned Managed Identity created${RESET}"
else
    echo -e "${YELLOW}User Assigned Managed Identity already exists: ${EXISTING_UAMI}${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 3: Creating Key Vault (or Restoring if Deleted)"
echo -e "======================================================================================================${RESET}"
DELETED_KEYVAULT=$(az keyvault list-deleted --query "[?name=='${KEYVAULT_NAME}'].name" -o tsv)
if [ ! -z "${DELETED_KEYVAULT}" ]; then
    echo -e "${YELLOW}Restoring deleted Key Vault: ${KEYVAULT_NAME}${RESET}"
    az keyvault recover --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}"
fi

EXISTING_KEYVAULT=$(az keyvault list --query "[?name=='${KEYVAULT_NAME}'].name" -o tsv)
if [ -z "${EXISTING_KEYVAULT}" ]; then
    az keyvault create \
        --enable-rbac-authorization true \
        --name "${KEYVAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}"
    echo -e "${GREEN}Key Vault created${RESET}"
else
    echo -e "${YELLOW}Key Vault already exists${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 4: Creating Storage Account"
echo -e "======================================================================================================${RESET}"
EXISTING_STORAGE=$(az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --query "id" --output tsv 2>/dev/null || echo "")
if [ -z "${EXISTING_STORAGE}" ]; then
    echo -e "${YELLOW}Creating storage account...${RESET}"
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --enable-hierarchical-namespace true \
        --min-tls-version TLS1_2
    echo -e "${GREEN}Storage account created${RESET}"
else
    echo -e "${YELLOW}Storage account already exists${RESET}"
fi

STORAGE_ID=$(az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --query "id" --output tsv)
echo -e "${GREEN}Storage ID: ${STORAGE_ID}${RESET}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 5: Creating IoT Ops Schema Registry"
echo -e "======================================================================================================${RESET}"
az extension add --upgrade --name azure-iot-ops --allow-preview

az iot ops schema registry create \
    -n "${REGISTRY_NAME}" \
    -g "${RESOURCE_GROUP}" \
    --registry-namespace "${REGISTRY_NAMESPACE}" \
    --sa-resource-id "${STORAGE_ID}" \
    --location "${LOCATION}" || {
    echo -e "${RED}Failed to create IoT Ops Schema Registry${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Step 6: Creating IoT Ops Namespace"
echo -e "======================================================================================================${RESET}"
az iot ops ns create \
    -n "${NE_IOT_NAMESPACE}" \
    -g "${RESOURCE_GROUP}" \
    --location "${LOCATION}" || {
    echo -e "${RED}Failed to create IoT Ops Namespace${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Step 7: Retrieving Resource IDs"
echo -e "======================================================================================================${RESET}"
SR_RESOURCE_ID=$(az iot ops schema registry show --name "${REGISTRY_NAME}" --resource-group "${RESOURCE_GROUP}" --query id --output tsv)
if [ -z "${SR_RESOURCE_ID}" ]; then
    echo -e "${RED}Failed to fetch Schema Registry ID${RESET}"
    exit 1
fi
echo -e "${GREEN}Schema Registry ID: ${SR_RESOURCE_ID}${RESET}"

NS_RESOURCE_ID=$(az iot ops ns show --name "${NE_IOT_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" --query id --output tsv)
if [ -z "${NS_RESOURCE_ID}" ]; then
    echo -e "${RED}Failed to fetch Namespace ID${RESET}"
    exit 1
fi
echo -e "${GREEN}Namespace ID: ${NS_RESOURCE_ID}${RESET}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 8: Creating IoT Operations Deployment Script for VM"
echo -e "======================================================================================================${RESET}"

# Create a script that will run on the VM
cat > /tmp/deploy-iot-ops.sh <<'EOFSCRIPT'
#!/bin/bash
set -e

export RED='\e[31m'
export GREEN='\e[32m'
export YELLOW='\e[33m'
export RESET='\e[0m'

# These variables will be replaced when the script is copied
SERVICE_PRINCIPAL_ID="__SERVICE_PRINCIPAL_ID__"
SERVICE_PRINCIPAL_CLIENT_SECRET="__SERVICE_PRINCIPAL_CLIENT_SECRET__"
SUBSCRIPTION_ID="__SUBSCRIPTION_ID__"
TENANT_ID="__TENANT_ID__"
RESOURCE_GROUP="__RESOURCE_GROUP__"
LOCATION="__LOCATION__"
CLUSTER_NAME="__CLUSTER_NAME__"
NE_IOT_INSTANCE="__NE_IOT_INSTANCE__"
NE_IOT_NAMESPACE="__NE_IOT_NAMESPACE__"
SR_RESOURCE_ID="__SR_RESOURCE_ID__"
NS_RESOURCE_ID="__NS_RESOURCE_ID__"
USER_ASSIGNED_MANAGED_IDENTITY="__USER_ASSIGNED_MANAGED_IDENTITY__"
KEYVAULT_NAME="__KEYVAULT_NAME__"

echo -e "${GREEN}======================================================================================================"
echo -e "Logging into Azure on VM"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription "$SUBSCRIPTION_ID"

# Set kubeconfig
export KUBECONFIG=~/.kube/config

echo -e "${GREEN}======================================================================================================"
echo -e "Initializing IoT Ops Cluster"
echo -e "======================================================================================================${RESET}"
az iot ops init \
    -g "${RESOURCE_GROUP}" \
    --cluster "${CLUSTER_NAME}" || {
    echo -e "${RED}Failed to initialize IoT Ops cluster${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating IoT Ops Instance"
echo -e "======================================================================================================${RESET}"
az iot ops create \
    --cluster "${CLUSTER_NAME}" \
    -g "${RESOURCE_GROUP}" \
    --name "${NE_IOT_INSTANCE}" \
    --sr-resource-id "${SR_RESOURCE_ID}" \
    --ns-resource-id "${NS_RESOURCE_ID}" || {
    echo -e "${RED}Failed to create IoT Ops instance${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Assigning User Assigned Managed Identity to IoT Ops Instance"
echo -e "======================================================================================================${RESET}"
USER_ASSIGNED_MI_RESOURCE_ID=$(az identity show \
    --name "${USER_ASSIGNED_MANAGED_IDENTITY}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query id \
    --output tsv)
echo -e "${GREEN}User Assigned MI Resource ID: ${USER_ASSIGNED_MI_RESOURCE_ID}${RESET}"

KEYVAULT_RESOURCE_ID=$(az keyvault show \
    --name "${KEYVAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query id \
    --output tsv)
echo -e "${GREEN}Key Vault Resource ID: ${KEYVAULT_RESOURCE_ID}${RESET}"

az iot ops secretsync enable \
    --instance "${NE_IOT_INSTANCE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --mi-user-assigned "${USER_ASSIGNED_MI_RESOURCE_ID}" \
    --kv-resource-id "${KEYVAULT_RESOURCE_ID}" || {
    echo -e "${RED}Failed to enable Secret Synchronization${RESET}"
    exit 1
}

az iot ops identity assign \
    --name "${NE_IOT_INSTANCE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --mi-user-assigned "${USER_ASSIGNED_MI_RESOURCE_ID}" || {
    echo -e "${RED}Failed to assign User-assigned managed identity${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Restarting Schema Registry Pods"
echo -e "======================================================================================================${RESET}"
kubectl delete pods adr-schema-registry-0 adr-schema-registry-1 -n azure-iot-operations 2>/dev/null || echo "Pods may not exist yet"

echo -e "${GREEN}======================================================================================================"
echo -e "Granting EventHub Permissions to Arc Extension"
echo -e "======================================================================================================${RESET}"
AZURE_IOT_OPS_ARC_EXTENSION_RESOURCE_ID=$(az k8s-extension list \
    --cluster-name "${CLUSTER_NAME}" \
    --cluster-type connectedClusters \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[?extensionType =='microsoft.iotoperations'].id" \
    -o tsv)

if [ ! -z "${AZURE_IOT_OPS_ARC_EXTENSION_RESOURCE_ID}" ]; then
    AZURE_IOT_OPS_ARC_EXTENSION_OID_FOR_MI=$(az resource show \
        --ids "$AZURE_IOT_OPS_ARC_EXTENSION_RESOURCE_ID" \
        --query "identity.principalId" \
        -o tsv)

    echo -e "${GREEN}Arc Extension Principal ID: ${AZURE_IOT_OPS_ARC_EXTENSION_OID_FOR_MI}${RESET}"

    az role assignment create \
        --assignee-object-id "${AZURE_IOT_OPS_ARC_EXTENSION_OID_FOR_MI}" \
        --role "Azure Event Hubs Data Receiver" \
        --scope "subscriptions/084c8f47-bb5d-447e-82cb-63241353edef/resourceGroups/EXP-MFG-AIO-ControlPlane-RG/providers/Microsoft.EventHub/namespaces/aiomfgeventhub001"

    az role assignment create \
        --assignee-object-id "${AZURE_IOT_OPS_ARC_EXTENSION_OID_FOR_MI}" \
        --role "Azure Event Hubs Data Sender" \
        --scope "subscriptions/084c8f47-bb5d-447e-82cb-63241353edef/resourceGroups/EXP-MFG-AIO-ControlPlane-RG/providers/Microsoft.EventHub/namespaces/aiomfgeventhub001"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "IoT Operations Deployment Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}IoT Ops Instance: ${NE_IOT_INSTANCE}${RESET}"
echo -e "${GREEN}You can now proceed with asset configuration${RESET}"
EOFSCRIPT

# Replace placeholders in the script
sed -i "s|__SERVICE_PRINCIPAL_ID__|${SERVICE_PRINCIPAL_ID}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__SERVICE_PRINCIPAL_CLIENT_SECRET__|${SERVICE_PRINCIPAL_CLIENT_SECRET}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__SUBSCRIPTION_ID__|${SUBSCRIPTION_ID}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__TENANT_ID__|${TENANT_ID}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__RESOURCE_GROUP__|${RESOURCE_GROUP}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__LOCATION__|${LOCATION}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__NE_IOT_INSTANCE__|${NE_IOT_INSTANCE}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__NE_IOT_NAMESPACE__|${NE_IOT_NAMESPACE}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__SR_RESOURCE_ID__|${SR_RESOURCE_ID}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__NS_RESOURCE_ID__|${NS_RESOURCE_ID}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__USER_ASSIGNED_MANAGED_IDENTITY__|${USER_ASSIGNED_MANAGED_IDENTITY}|g" /tmp/deploy-iot-ops.sh
sed -i "s|__KEYVAULT_NAME__|${KEYVAULT_NAME}|g" /tmp/deploy-iot-ops.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Step 9: Copying Deployment Script to VM"
echo -e "======================================================================================================${RESET}"
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no /tmp/deploy-iot-ops.sh ubuntu@${OT_NETWORK_VM_IP}:/tmp/deploy-iot-ops.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to copy script to VM${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 10: Executing IoT Operations Deployment on VM"
echo -e "======================================================================================================${RESET}"
echo -e "${YELLOW}This may take 10-15 minutes to complete...${RESET}"

ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${OT_NETWORK_VM_IP} "chmod +x /tmp/deploy-iot-ops.sh && /tmp/deploy-iot-ops.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to execute IoT Operations deployment on VM${RESET}"
    exit 1
fi

# Clean up
rm -f /tmp/deploy-iot-ops.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Azure IoT Operations Deployment Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}IoT Operations Instance: ${NE_IOT_INSTANCE}${RESET}"
echo -e "${GREEN}Resource Group: ${RESOURCE_GROUP}${RESET}"
echo ""
echo -e "${GREEN}Next Steps:${RESET}"
echo -e "  - Verify deployment in Azure Portal${RESET}"
echo -e "  - Run step6-beckhoff-controller-deployment.sh to configure Beckhoff PLC${RESET}"
echo -e "  - Run step7-leuze-controller-deployment.sh to configure Leuze barcode scanner${RESET}"
echo -e "  - Or use Azure CLI/Portal to configure your own assets${RESET}"
