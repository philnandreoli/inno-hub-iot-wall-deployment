#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Azure Arc Enable Host - Step 1
# ============================================================================
# This script Arc enables the Ubuntu 24.04.3 LTS host machine.
# It must be run on the physical host before creating the VM.
#
# Prerequisites:
# - Ubuntu Server 24.04.3 LTS
# - Internet connectivity
# - Service Principal with appropriate permissions
#
# Usage:
#   ./step1-arc-enable-host.sh \
#     --service-principal-id <sp-id> \
#     --service-principal-secret <sp-secret> \
#     --subscription-id <subscription-id> \
#     --tenant-id <tenant-id> \
#     --location <location> \
#     --data-center <datacenter> \
#     --city <city> \
#     --state-region <state-region> \
#     --country <country>
#
# Example:
#   ./step1-arc-enable-host.sh \
#     --service-principal-id "12345678-1234-1234-1234-123456789abc" \
#     --service-principal-secret "your-secret-here" \
#     --subscription-id "12345678-1234-1234-1234-123456789abc" \
#     --tenant-id "12345678-1234-1234-1234-123456789abc" \
#     --location "eastus2" \
#     --data-center "CHI" \
#     --city "Chicago" \
#     --state-region "IL" \
#     --country "US"
#
# Note: Resource group will be auto-created as EXP-MFG-AIO-CHI-US-RG
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
    echo "Options:"
    echo "  -h, --help                         Display this help message"
    echo ""
    echo "Note: Resource group will be auto-created with naming convention:"
    echo "      EXP-MFG-AIO-\${DATA_CENTER}-\${COUNTRY}-RG"
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

# Azure settings
export AUTH_TYPE="principal"
export CLOUD="AzureCloud"

# Resource group will be auto-created with naming convention
export RESOURCE_GROUP="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"




# Service tag is the hostname of this machine
export SERVICE_TAG=$(hostname -s)

echo -e "${GREEN}======================================================================================================"
echo -e " Azure Arc Enable Host - Configuration Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}SERVICE_PRINCIPAL_ID: ${SERVICE_PRINCIPAL_ID}${RESET}"
echo -e "${GREEN}SUBSCRIPTION_ID: ${SUBSCRIPTION_ID}${RESET}"
echo -e "${GREEN}RESOURCE_GROUP: ${RESOURCE_GROUP}${RESET}"
echo -e "${GREEN}TENANT_ID: ${TENANT_ID}${RESET}"
echo -e "${GREEN}LOCATION: ${LOCATION}${RESET}"
echo -e "${GREEN}DATA_CENTER: ${DATA_CENTER}${RESET}"
echo -e "${GREEN}CITY: ${CITY}${RESET}"
echo -e "${GREEN}STATE_REGION: ${STATE_REGION}${RESET}"
echo -e "${GREEN}COUNTRY: ${COUNTRY}${RESET}"
echo -e "${GREEN}SERVICE_TAG (Host): ${SERVICE_TAG}${RESET}"
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

echo -e "${GREEN}======================================================================================================"
echo -e "Step 1: Installing Azure CLI"
echo -e "======================================================================================================${RESET}"
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install required Azure CLI extensions
az extension add --name connectedmachine --allow-preview

echo -e "${GREEN}======================================================================================================"
echo -e "Step 2: Logging into Azure and Creating Resource Group"
echo -e "======================================================================================================${RESET}"

# Login to Azure with Service Principal
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription "$SUBSCRIPTION_ID"

# Create resource group with naming convention: EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG
RESOURCE_GROUP_NAME="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"

echo -e "${GREEN}Resource Group Name: ${RESOURCE_GROUP_NAME}${RESET}"

# Check if resource group exists
EXISTING_RG=$(az group show --name "${RESOURCE_GROUP_NAME}" --query "id" -o tsv 2>/dev/null || echo "")

if [ -z "${EXISTING_RG}" ]; then
    echo -e "${YELLOW}Creating resource group: ${RESOURCE_GROUP_NAME}${RESET}"
    az group create \
        --name "${RESOURCE_GROUP_NAME}" \
        --location "${LOCATION}" \
        --tags Environment=MTCDemo CreatedBy=NativeEdge Industry=MFG Partner=NA RGMonthlyCost=1000 Owner=philand@onemtcnet CreatedDate=$(date +%Y-%m-%d) LifeCycleCheck=$(date +%Y-%m-%d)
    

    az role assignment create --assignee "e47cc756-add5-4ae8-b684-10f6c82ee08e" --role "Contributor" --scope "/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${RESOURCE_GROUP_NAME}"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create resource group${RESET}"
        exit 1
    fi
    echo -e "${GREEN}Resource group created successfully${RESET}"
else
    echo -e "${YELLOW}Resource group already exists: ${RESOURCE_GROUP_NAME}${RESET}"
fi

# Update RESOURCE_GROUP variable to use the created/verified resource group
export RESOURCE_GROUP="${RESOURCE_GROUP_NAME}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 3: Downloading and Installing Azure Connected Machine Agent"
echo -e "======================================================================================================${RESET}"

# Download the installation package
LINUX_INSTALL_SCRIPT="/tmp/install_linux_azcmagent.sh"
if [ -f "$LINUX_INSTALL_SCRIPT" ]; then 
    rm -f "$LINUX_INSTALL_SCRIPT"
fi

output=$(wget https://gbl.his.arc.azure.com/azcmagent-linux -O "$LINUX_INSTALL_SCRIPT" 2>&1)
if [ $? != 0 ]; then 
    wget -qO- --method=PUT --body-data="{\"subscriptionId\":\"$SUBSCRIPTION_ID\",\"resourceGroup\":\"$RESOURCE_GROUP\",\"tenantId\":\"$TENANT_ID\",\"location\":\"$LOCATION\",\"correlationId\":\"$correlationId\",\"authType\":\"$AUTH_TYPE\",\"operation\":\"onboarding\",\"messageType\":\"DownloadScriptFailed\",\"message\":\"$output\"}" "https://gbl.his.arc.azure.com/log" &> /dev/null || true
    echo -e "${RED}Failed to download Azure Connected Machine agent${RESET}"
    exit 1
fi
echo "$output"

# Install the hybrid agent
bash "$LINUX_INSTALL_SCRIPT"
sleep 5

echo -e "${GREEN}======================================================================================================"
echo -e "Step 4: Connecting Host to Azure Arc"
echo -e "======================================================================================================${RESET}"

# Connect the host to Azure Arc
sudo azcmagent connect \
    --service-principal-id "$SERVICE_PRINCIPAL_ID" \
    --service-principal-secret "$SERVICE_PRINCIPAL_CLIENT_SECRET" \
    --resource-group "$RESOURCE_GROUP" \
    --tenant-id "$TENANT_ID" \
    --location "$LOCATION" \
    --subscription-id "$SUBSCRIPTION_ID" \
    --cloud "$CLOUD" \
    --tags "Datacenter=${DATA_CENTER},City=${CITY},StateOrDistrict=${STATE_REGION},CountryOrRegion=${COUNTRY},ServiceTag=${SERVICE_TAG},ArcSQLServerExtensionDeployment=Disabled,Role=Host"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect host to Azure Arc${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 5: Installing Additional Packages"
echo -e "======================================================================================================${RESET}"
sudo apt update
sudo apt install -y net-tools aadsshlogin

echo -e "${GREEN}======================================================================================================"
echo -e "Step 6: Creating Default Connectivity Endpoint"
echo -e "======================================================================================================${RESET}"
az rest --method put \
    --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.HybridCompute/machines/${SERVICE_TAG}/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15" \
    --body '{"properties": {"type": "default"}}'

echo -e "${GREEN}======================================================================================================"
echo -e "Step 7: Verifying Connectivity Endpoint Status"
echo -e "======================================================================================================${RESET}"
az rest --method get \
    --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.HybridCompute/machines/${SERVICE_TAG}/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 8: Enabling SSH Functionality"
echo -e "======================================================================================================${RESET}"
az rest --method put \
    --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.HybridCompute/machines/${SERVICE_TAG}/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15" \
    --body "{\"properties\": {\"serviceName\": \"SSH\", \"port\": 22}}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 9: Installing Microsoft Entra Login Extension"
echo -e "======================================================================================================${RESET}"
az connectedmachine extension create \
    --machine-name "${SERVICE_TAG}" \
    --resource-group "${RESOURCE_GROUP}" \
    --publisher Microsoft.Azure.ActiveDirectory \
    --name AADSSHLogin \
    --type AADSSHLoginForLinux \
    --location "${LOCATION}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 10: Configuring Security Settings (SFI Requirements)"
echo -e "======================================================================================================${RESET}"

# Set the owner and group of /etc/cron.weekly to root and permissions to 0700
sudo chown root:root /etc/cron.weekly
sudo chmod 0700 /etc/cron.weekly

# Set the owner and group of /etc/ssh/sshd_config to root and permissions to 0600
sudo chown root:root /etc/ssh/sshd_config
sudo chmod 600 /etc/ssh/sshd_config

# Set the owner and group of /etc/cron.monthly to root and permissions to 0700
sudo chown root:root /etc/cron.monthly
sudo chmod 700 /etc/cron.monthly

# Configure sysctl parameters
sudo sed -i 's/^net\.ipv4\.conf\.all\.send_redirects.*/net.ipv4.conf.all.send_redirects = 0/' /etc/sysctl.conf
sudo sed -i 's/^net\.ipv4\.conf\.default\.send_redirects.*/net.ipv4.conf.default.send_redirects = 0/' /etc/sysctl.conf

# Append if not already present
grep -q "^net.ipv4.conf.all.send_redirects" /etc/sysctl.conf || echo "net.ipv4.conf.all.send_redirects = 0" | sudo tee -a /etc/sysctl.conf
grep -q "^net.ipv4.conf.default.send_redirects" /etc/sysctl.conf || echo "net.ipv4.conf.default.send_redirects = 0" | sudo tee -a /etc/sysctl.conf

sudo sysctl -w net.ipv4.conf.all.send_redirects=0
sudo sysctl -w net.ipv4.conf.default.send_redirects=0

echo -e "${GREEN}======================================================================================================"
echo -e "Host Arc Enablement Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}The host '${SERVICE_TAG}' has been successfully connected to Azure Arc.${RESET}"
echo -e "${GREEN}Next Step: Run step2-create-vm.sh to create and configure the virtual machine.${RESET}"
