#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Install k3s and Arc Enable Kubernetes - Step 4
# ============================================================================
# This script installs k3s on the VM, configures kubectl, sets system limits,
# and Arc enables the Kubernetes cluster.
# It runs FROM THE HOST and connects to the VM via SSH.
#
# Prerequisites:
# - VM must be Arc enabled (step3 completed)
# - SSH connectivity to VM must be working
#
# Usage:
#   ./step4-install-k3s-on-vm.sh \
#     --service-principal-id <sp-id> \
#     --service-principal-secret <sp-secret> \
#     --subscription-id <subscription-id> \
#     --tenant-id <tenant-id> \
#     --resource-group <resource-group> \
#     --location <location> \
#     --data-center <datacenter>
#
# Example:
#   ./step4-install-k3s-on-vm.sh \
#     --service-principal-id "12345678-1234-1234-1234-123456789abc" \
#     --service-principal-secret "your-secret-here" \
#     --subscription-id "12345678-1234-1234-1234-123456789abc" \
#     --tenant-id "12345678-1234-1234-1234-123456789abc" \
#     --resource-group "EXP-MFG-AIO-RG" \
#     --location "eastus2" \
#     --data-center "CHI"
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
    echo "  --country CODE                     Country code (e.g., US, DE)"
    echo ""
    echo "Optional Options:"
    echo "  --ot-network-vm-ip IP              OT network IP for VM (default: 192.168.30.18)"
    echo "  --ssh-key-path PATH                Path to SSH private key (default: ~/.ssh/vm_id_rsa)"
    echo "  --k3s-version VERSION              k3s version to install (default: v1.34.1+k3s1)"
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
        --country)
            ARG_COUNTRY="$2"
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
        --ot-network-vm-ip)
            ARG_OT_NETWORK_VM_IP="$2"
            shift 2
            ;;
        --ssh-key-path)
            ARG_SSH_KEY_PATH="$2"
            shift 2
            ;;
        --k3s-version)
            ARG_K3S_VERSION="$2"
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
export COUNTRY="${ARG_COUNTRY:-${COUNTRY}}"
export LOCATION="${ARG_LOCATION:-${LOCATION:-eastus2}}"
export DATA_CENTER="${ARG_DATA_CENTER:-${DATA_CENTER}}"

# VM Configuration
export HOST_NAME=$(hostname -s)
export VM_NAME="${HOST_NAME}-vm"
export OT_NETWORK_VM_IP="${ARG_OT_NETWORK_VM_IP:-${OT_NETWORK_VM_IP:-192.168.30.18}}"
export SSH_KEY_PATH="${ARG_SSH_KEY_PATH:-${SSH_KEY_PATH:-$HOME/.ssh/vm_id_rsa}}"

# k3s and IoT Operations settings
export INSTALL_K3S_VERSION="${ARG_K3S_VERSION:-${INSTALL_K3S_VERSION:-v1.34.1+k3s1}}"
export CLUSTER_NAME="${DATA_CENTER}-${VM_NAME}-k3s"
export IOT_ID="${ARG_IOT_ID:-${IOT_ID:-a4e6246e-0a1b-48c6-8fd6-9b0631d78d05}}"

# Convert cluster name to lowercase and replace underscores with hyphens
CLUSTER_NAME=$(echo "${CLUSTER_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')

echo -e "${GREEN}======================================================================================================"
echo -e " Install k3s and Arc Enable Kubernetes - Configuration Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Host Name: ${HOST_NAME}${RESET}"
echo -e "${GREEN}VM Name: ${VM_NAME}${RESET}"
echo -e "${GREEN}VM IP Address: ${OT_NETWORK_VM_IP}${RESET}"
echo -e "${GREEN}Cluster Name: ${CLUSTER_NAME}${RESET}"
echo -e "${GREEN}k3s Version: ${INSTALL_K3S_VERSION}${RESET}"
echo -e "${GREEN}Resource Group: ${RESOURCE_GROUP}${RESET}"
echo -e "${GREEN}Location: ${LOCATION}${RESET}"
echo -e "${GREEN}SSH Key Path: ${SSH_KEY_PATH}${RESET}"
echo -e "${GREEN}IoT Custom Locations OID: ${IOT_ID}${RESET}"
echo ""

# Validation
if [ -z "$SERVICE_PRINCIPAL_ID" ] || [ -z "$SERVICE_PRINCIPAL_CLIENT_SECRET" ] || \
   [ -z "$SUBSCRIPTION_ID" ] || [ -z "$TENANT_ID" ] || [ -z "$COUNTRY" ] || \
   [ -z "$DATA_CENTER" ]; then
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
echo -e "Step 1: Verifying VM Connectivity"
echo -e "======================================================================================================${RESET}"

ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@${OT_NETWORK_VM_IP} "echo 'VM is reachable'" 2>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Cannot connect to VM at ${OT_NETWORK_VM_IP}${RESET}"
    exit 1
fi

echo -e "${GREEN}VM connectivity verified${RESET}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 2: Creating k3s Installation and Arc Enablement Script"
echo -e "======================================================================================================${RESET}"

# Create a script that will run on the VM
cat > /tmp/install-k3s-arc.sh <<'EOFSCRIPT'
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
INSTALL_K3S_VERSION="__INSTALL_K3S_VERSION__"
IOT_ID="__IOT_ID__"

echo -e "${GREEN}======================================================================================================"
echo -e "Installing k3s"
echo -e "======================================================================================================${RESET}"
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION}" sh -

# Wait for k3s to be ready
echo -e "${YELLOW}Waiting for k3s to be ready...${RESET}"
sleep 10

echo -e "${GREEN}======================================================================================================"
echo -e "Configuring kubectl for k3s"
echo -e "======================================================================================================${RESET}"
mkdir -p ~/.kube
sudo KUBECONFIG=~/.kube/config:/etc/rancher/k3s/k3s.yaml kubectl config view --flatten > ~/.kube/merged
mv ~/.kube/merged ~/.kube/config
chmod 0600 ~/.kube/config
export KUBECONFIG=~/.kube/config

# Switch to k3s context
kubectl config use-context default
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Verify k3s is running
echo -e "${YELLOW}Verifying k3s installation...${RESET}"
kubectl get nodes

echo -e "${GREEN}======================================================================================================"
echo -e "Configuring System Limits for k3s"
echo -e "======================================================================================================${RESET}"
echo fs.inotify.max_user_instances=8192 | sudo tee -a /etc/sysctl.conf
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
echo fs.file-max = 100000 | sudo tee -a /etc/sysctl.conf

sudo sysctl -p

echo -e "${GREEN}======================================================================================================"
echo -e "Installing Azure CLI Extensions for Kubernetes"
echo -e "======================================================================================================${RESET}"
az extension add --name connectedk8s
az extension add --name k8s-extension

echo -e "${GREEN}======================================================================================================"
echo -e "Logging into Azure"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription "$SUBSCRIPTION_ID"

echo -e "${GREEN}======================================================================================================"
echo -e "Connecting k3s to Azure Arc"
echo -e "======================================================================================================${RESET}"
az connectedk8s connect \
    --name "$CLUSTER_NAME" \
    --location "$LOCATION" \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --disable-auto-upgrade

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect k3s to Azure Arc${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Enabling IoT Features on Arc-Enabled Kubernetes Cluster"
echo -e "======================================================================================================${RESET}"
az connectedk8s enable-features \
    -n "${CLUSTER_NAME}" \
    -g "${RESOURCE_GROUP}" \
    --custom-locations-oid "${IOT_ID}" \
    --features cluster-connect custom-locations

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to enable IoT features${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Updating k3s config.yaml with OIDC Issuer"
echo -e "======================================================================================================${RESET}"
SERVICE_ACCOUNT_ISSUER=$(az connectedk8s show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --query oidcIssuerProfile.issuerUrl \
    --output tsv)

echo -e "${YELLOW}OIDC Issuer URL: ${SERVICE_ACCOUNT_ISSUER}${RESET}"

CONFIG_SNIPPET="kube-apiserver-arg:\n - service-account-issuer=${SERVICE_ACCOUNT_ISSUER}\n - service-account-max-token-expiration=24h"
echo -e "${CONFIG_SNIPPET}" | sudo tee -a /etc/rancher/k3s/config.yaml

echo -e "${GREEN}======================================================================================================"
echo -e "Restarting k3s to Apply New Configuration"
echo -e "======================================================================================================${RESET}"
sudo systemctl restart k3s

# Wait for k3s to come back up
echo -e "${YELLOW}Waiting for k3s to restart...${RESET}"
sleep 15

# Verify k3s is running
kubectl get nodes

echo -e "${GREEN}======================================================================================================"
echo -e "k3s Installation and Arc Enablement Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Cluster Name: ${CLUSTER_NAME}${RESET}"
echo -e "${GREEN}Cluster is now Arc-enabled and ready for Azure IoT Operations deployment${RESET}"
EOFSCRIPT

# Replace placeholders in the script
sed -i "s|__SERVICE_PRINCIPAL_ID__|${SERVICE_PRINCIPAL_ID}|g" /tmp/install-k3s-arc.sh
sed -i "s|__SERVICE_PRINCIPAL_CLIENT_SECRET__|${SERVICE_PRINCIPAL_CLIENT_SECRET}|g" /tmp/install-k3s-arc.sh
sed -i "s|__SUBSCRIPTION_ID__|${SUBSCRIPTION_ID}|g" /tmp/install-k3s-arc.sh
sed -i "s|__TENANT_ID__|${TENANT_ID}|g" /tmp/install-k3s-arc.sh
sed -i "s|__RESOURCE_GROUP__|${RESOURCE_GROUP}|g" /tmp/install-k3s-arc.sh
sed -i "s|__LOCATION__|${LOCATION}|g" /tmp/install-k3s-arc.sh
sed -i "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" /tmp/install-k3s-arc.sh
sed -i "s|__INSTALL_K3S_VERSION__|${INSTALL_K3S_VERSION}|g" /tmp/install-k3s-arc.sh
sed -i "s|__IOT_ID__|${IOT_ID}|g" /tmp/install-k3s-arc.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Step 3: Copying Installation Script to VM"
echo -e "======================================================================================================${RESET}"
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no /tmp/install-k3s-arc.sh ubuntu@${OT_NETWORK_VM_IP}:/tmp/install-k3s-arc.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to copy script to VM${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 4: Executing k3s Installation and Arc Enablement on VM"
echo -e "======================================================================================================${RESET}"
echo -e "${YELLOW}This may take several minutes...${RESET}"

ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${OT_NETWORK_VM_IP} "chmod +x /tmp/install-k3s-arc.sh && /tmp/install-k3s-arc.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to execute k3s installation script on VM${RESET}"
    exit 1
fi

# Clean up
rm -f /tmp/install-k3s-arc.sh

echo -e "${GREEN}======================================================================================================"
echo -e "k3s Installation and Arc Enablement Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}The k3s cluster on VM '${VM_NAME}' has been successfully installed and Arc-enabled.${RESET}"
echo -e "${GREEN}Cluster Name: ${CLUSTER_NAME}${RESET}"
echo ""
echo -e "${GREEN}You can verify the cluster in Azure Portal:${RESET}"
echo -e "  - Resource Group: ${RESOURCE_GROUP}${RESET}"
echo -e "  - Look for Azure Arc-enabled Kubernetes cluster: ${CLUSTER_NAME}${RESET}"
echo ""
echo -e "${GREEN}To access the cluster from the VM:${RESET}"
echo -e "  ssh -i ${SSH_KEY_PATH} ubuntu@${OT_NETWORK_VM_IP}${RESET}"
echo -e "  kubectl get nodes${RESET}"
echo ""
echo -e "${GREEN}Next Step: Run step5-iot-operations-deployment.sh to deploy Azure IoT Operations.${RESET}"
