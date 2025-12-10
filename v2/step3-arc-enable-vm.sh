#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Arc Enable Virtual Machine - Step 3
# ============================================================================
# This script Arc enables the virtual machine created in step 2.
# It runs FROM THE HOST and connects to the VM via SSH to install the
# Azure Connected Machine agent.
#
# Prerequisites:
# - Host must be Arc enabled (step1 completed)
# - VM must be created and running (step2 completed)
# - SSH connectivity to VM must be working
#
# Usage:
#   ./step3-arc-enable-vm.sh \
#     --service-principal-id <sp-id> \
#     --service-principal-secret <sp-secret> \
#     --subscription-id <subscription-id> \
#     --tenant-id <tenant-id> \
#     --resource-group <resource-group> \
#     --location <location> \
#     --data-center <datacenter> \
#     --city <city> \
#     --state-region <state-region> \
#     --country <country>
#
# Example:
#   ./step3-arc-enable-vm.sh \
#     --service-principal-id "12345678-1234-1234-1234-123456789abc" \
#     --service-principal-secret "your-secret-here" \
#     --subscription-id "12345678-1234-1234-1234-123456789abc" \
#     --tenant-id "12345678-1234-1234-1234-123456789abc" \
#     --resource-group "EXP-MFG-AIO-RG" \
#     --location "eastus2" \
#     --data-center "CHI" \
#     --city "Chicago" \
#     --state-region "IL" \
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
export RESOURCE_GROUP="${ARG_RESOURCE_GROUP:-${RESOURCE_GROUP}}"
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

# Azure settings
export AUTH_TYPE="principal"
export CLOUD="AzureCloud"

echo -e "${GREEN}======================================================================================================"
echo -e " Arc Enable Virtual Machine - Configuration Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Host Name: ${HOST_NAME}${RESET}"
echo -e "${GREEN}VM Name: ${VM_NAME}${RESET}"
echo -e "${GREEN}VM IP Address: ${OT_NETWORK_VM_IP}${RESET}"
echo -e "${GREEN}Resource Group: ${RESOURCE_GROUP}${RESET}"
echo -e "${GREEN}Location: ${LOCATION}${RESET}"
echo -e "${GREEN}Data Center: ${DATA_CENTER}${RESET}"
echo -e "${GREEN}SSH Key Path: ${SSH_KEY_PATH}${RESET}"
echo ""

RESOURCE_GROUP="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"
echo -e "${GREEN}Resource Group Name: ${RESOURCE_GROUP}${RESET}"

# Validation
if [ -z "$SERVICE_PRINCIPAL_ID" ] || [ -z "$SERVICE_PRINCIPAL_CLIENT_SECRET" ] || \
   [ -z "$SUBSCRIPTION_ID" ] || [ -z "$TENANT_ID" ]  || \
   [ -z "$DATA_CENTER" ] || [ -z "$CITY" ] || [ -z "$STATE_REGION" ] || [ -z "$COUNTRY" ]; then
    echo -e "${RED}ERROR: Required parameters are missing.${RESET}"
    echo -e "${RED}Please provide all required arguments or set environment variables.${RESET}"
    echo ""
    usage
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}ERROR: SSH key not found at ${SSH_KEY_PATH}${RESET}"
    echo -e "${YELLOW}Please ensure step2 completed successfully${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 1: Verifying VM Connectivity"
echo -e "======================================================================================================${RESET}"

# Test SSH connection
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@${OT_NETWORK_VM_IP} "echo 'VM is reachable'" 2>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Cannot connect to VM at ${OT_NETWORK_VM_IP}${RESET}"
    echo -e "${YELLOW}Please verify the VM is running and network configuration is correct${RESET}"
    exit 1
fi

echo -e "${GREEN}VM connectivity verified${RESET}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 2: Creating Arc Enablement Script for VM"
echo -e "======================================================================================================${RESET}"

# Create a script that will run on the VM
cat > /tmp/arc-enable-vm.sh <<'EOFSCRIPT'
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
DATA_CENTER="__DATA_CENTER__"
CITY="__CITY__"
STATE_REGION="__STATE_REGION__"
COUNTRY="__COUNTRY__"
VM_NAME="__VM_NAME__"
AUTH_TYPE="__AUTH_TYPE__"
CLOUD="__CLOUD__"

echo -e "${GREEN}======================================================================================================"
echo -e "Installing Azure CLI on VM"
echo -e "======================================================================================================${RESET}"
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install required Azure CLI extensions
az extension add --name connectedmachine --allow-preview

echo -e "${GREEN}======================================================================================================"
echo -e "Downloading and Installing Azure Connected Machine Agent"
echo -e "======================================================================================================${RESET}"

# Download the installation package
LINUX_INSTALL_SCRIPT="/tmp/install_linux_azcmagent.sh"
if [ -f "$LINUX_INSTALL_SCRIPT" ]; then 
    rm -f "$LINUX_INSTALL_SCRIPT"
fi

output=$(wget https://gbl.his.arc.azure.com/azcmagent-linux -O "$LINUX_INSTALL_SCRIPT" 2>&1)
if [ $? != 0 ]; then 
    echo -e "${RED}Failed to download Azure Connected Machine agent${RESET}"
    exit 1
fi

# Install the hybrid agent
bash "$LINUX_INSTALL_SCRIPT"
sleep 5

echo -e "${GREEN}======================================================================================================"
echo -e "Connecting VM to Azure Arc"
echo -e "======================================================================================================${RESET}"

# Connect the VM to Azure Arc with appropriate tags
sudo azcmagent connect \
    --service-principal-id "$SERVICE_PRINCIPAL_ID" \
    --service-principal-secret "$SERVICE_PRINCIPAL_CLIENT_SECRET" \
    --resource-group "$RESOURCE_GROUP" \
    --tenant-id "$TENANT_ID" \
    --location "$LOCATION" \
    --subscription-id "$SUBSCRIPTION_ID" \
    --cloud "$CLOUD" \
    --tags "Datacenter=${DATA_CENTER},City=${CITY},StateOrDistrict=${STATE_REGION},CountryOrRegion=${COUNTRY},ServiceTag=${VM_NAME},ArcSQLServerExtensionDeployment=Disabled,Role=VM"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect VM to Azure Arc${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Installing Additional Packages"
echo -e "======================================================================================================${RESET}"
sudo apt update
sudo apt install -y net-tools aadsshlogin

echo -e "${GREEN}======================================================================================================"
echo -e "Logging into Azure with Service Principal"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription "$SUBSCRIPTION_ID"

echo -e "${GREEN}======================================================================================================"
echo -e "Creating Default Connectivity Endpoint"
echo -e "======================================================================================================${RESET}"
az rest --method put \
    --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.HybridCompute/machines/${VM_NAME}/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15" \
    --body '{"properties": {"type": "default"}}'

echo -e "${GREEN}======================================================================================================"
echo -e "Enabling SSH Functionality"
echo -e "======================================================================================================${RESET}"
az rest --method put \
    --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.HybridCompute/machines/${VM_NAME}/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15" \
    --body "{\"properties\": {\"serviceName\": \"SSH\", \"port\": 22}}"

echo -e "${GREEN}======================================================================================================"
echo -e "Installing Microsoft Entra Login Extension"
echo -e "======================================================================================================${RESET}"
az connectedmachine extension create \
    --machine-name "${VM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --publisher Microsoft.Azure.ActiveDirectory \
    --name AADSSHLogin \
    --type AADSSHLoginForLinux \
    --location "${LOCATION}"

echo -e "${GREEN}======================================================================================================"
echo -e "Configuring Security Settings (SFI Requirements)"
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
echo -e "VM Arc Enablement Complete!"
echo -e "======================================================================================================${RESET}"
EOFSCRIPT

# Replace placeholders in the script
sed -i "s|__SERVICE_PRINCIPAL_ID__|${SERVICE_PRINCIPAL_ID}|g" /tmp/arc-enable-vm.sh
sed -i "s|__SERVICE_PRINCIPAL_CLIENT_SECRET__|${SERVICE_PRINCIPAL_CLIENT_SECRET}|g" /tmp/arc-enable-vm.sh
sed -i "s|__SUBSCRIPTION_ID__|${SUBSCRIPTION_ID}|g" /tmp/arc-enable-vm.sh
sed -i "s|__TENANT_ID__|${TENANT_ID}|g" /tmp/arc-enable-vm.sh
sed -i "s|__RESOURCE_GROUP__|${RESOURCE_GROUP}|g" /tmp/arc-enable-vm.sh
sed -i "s|__LOCATION__|${LOCATION}|g" /tmp/arc-enable-vm.sh
sed -i "s|__DATA_CENTER__|${DATA_CENTER}|g" /tmp/arc-enable-vm.sh
sed -i "s|__CITY__|${CITY}|g" /tmp/arc-enable-vm.sh
sed -i "s|__STATE_REGION__|${STATE_REGION}|g" /tmp/arc-enable-vm.sh
sed -i "s|__COUNTRY__|${COUNTRY}|g" /tmp/arc-enable-vm.sh
sed -i "s|__VM_NAME__|${VM_NAME}|g" /tmp/arc-enable-vm.sh
sed -i "s|__AUTH_TYPE__|${AUTH_TYPE}|g" /tmp/arc-enable-vm.sh
sed -i "s|__CLOUD__|${CLOUD}|g" /tmp/arc-enable-vm.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Step 3: Copying Arc Enablement Script to VM"
echo -e "======================================================================================================${RESET}"
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no /tmp/arc-enable-vm.sh ubuntu@${OT_NETWORK_VM_IP}:/tmp/arc-enable-vm.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to copy script to VM${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 4: Executing Arc Enablement Script on VM"
echo -e "======================================================================================================${RESET}"
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${OT_NETWORK_VM_IP} "chmod +x /tmp/arc-enable-vm.sh && /tmp/arc-enable-vm.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to execute Arc enablement script on VM${RESET}"
    exit 1
fi

# Clean up
rm -f /tmp/arc-enable-vm.sh

echo -e "${GREEN}======================================================================================================"
echo -e "VM Arc Enablement Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}The VM '${VM_NAME}' has been successfully connected to Azure Arc.${RESET}"
echo -e "${GREEN}You can verify this in the Azure Portal under Resource Group '${RESOURCE_GROUP}'.${RESET}"
echo ""
echo -e "${GREEN}Next Step: Run step4-install-k3s-on-vm.sh to install k3s and Arc enable Kubernetes.${RESET}"
