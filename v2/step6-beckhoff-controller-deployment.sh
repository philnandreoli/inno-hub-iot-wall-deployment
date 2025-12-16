#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Deploy Beckhoff Controller Configuration - Step 6
# ============================================================================
# This script configures the Beckhoff OPC UA controller as an asset in
# Azure IoT Operations, including device, endpoint, asset, dataset,
# datapoints, and dataflow configuration.
# It runs FROM THE HOST and connects to the VM via SSH.
#
# Prerequisites:
# - IoT Operations must be deployed (step5 completed)
# - SSH connectivity to VM must be working
#
# Usage:
#   ./step6-beckhoff-controller-deployment.sh \\
#     --service-principal-id <sp-id> \\
#     --service-principal-secret <sp-secret> \\
#     --subscription-id <subscription-id> \\
#     --tenant-id <tenant-id> \\
#     --location <location> \\
#     --data-center <datacenter> \\
#     --city <city> \\
#     --state-region <state-region> \\
#     --country <country>
#
# Example:
#   ./step6-beckhoff-controller-deployment.sh \\
#     --service-principal-id "12345678-1234-1234-1234-123456789abc" \\
#     --service-principal-secret "your-secret-here" \\
#     --subscription-id "12345678-1234-1234-1234-123456789abc" \\
#     --tenant-id "12345678-1234-1234-1234-123456789abc" \\
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

# Resource group with naming convention
export RESOURCE_GROUP="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"

# Azure IoT Operations Resource Names
export CLUSTER_NAME="${DATA_CENTER}-${VM_NAME}-k3s"
export NE_IOT_INSTANCE="${DATA_CENTER}-${VM_NAME}-aio-instance"

# Convert to lowercase
CLUSTER_NAME=$(echo "${CLUSTER_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
NE_IOT_INSTANCE=$(echo "${NE_IOT_INSTANCE}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')

echo -e "${GREEN}======================================================================================================"
echo -e " Deploy Beckhoff Controller Configuration - Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}VM Name: ${VM_NAME}${RESET}"
echo -e "${GREEN}VM IP Address: ${OT_NETWORK_VM_IP}${RESET}"
echo -e "${GREEN}IoT Instance: ${NE_IOT_INSTANCE}${RESET}"
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

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}ERROR: SSH key not found at ${SSH_KEY_PATH}${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 1: Creating Beckhoff Controller Configuration Script"
echo -e "======================================================================================================${RESET}"

# Create a script that will run on the VM
cat > /tmp/configure-beckhoff.sh <<'EOFSCRIPT'
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
NE_IOT_INSTANCE="__NE_IOT_INSTANCE__"
DATA_CENTER="__DATA_CENTER__"
COUNTRY="__COUNTRY__"
STATE_REGION="__STATE_REGION__"
CLUSTER_NAME="__CLUSTER_NAME__"

echo -e "${GREEN}======================================================================================================"
echo -e "Logging into Azure"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription "$SUBSCRIPTION_ID"

az config set extension.dynamic_install_allow_preview=true
az extension add --name azure-iot-ops --allow-preview

echo -e "${GREEN}======================================================================================================"
echo -e "Creating IoT Ops Device for Beckhoff OPC UA Controller"
echo -e "======================================================================================================${RESET}"
az iot ops ns device create \
    --name opc-ua-beckhoff-controller \
    --instance "${NE_IOT_INSTANCE}" \
    -g "${RESOURCE_GROUP}" \
    --model "CX51x0" \
    --os-version "1.0.51" \
    --manufacturer "Beckhoff" || {
    echo -e "${RED}Failed to create IoT Ops device${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating Device Endpoint for Beckhoff Controller"
echo -e "======================================================================================================${RESET}"
az iot ops ns device endpoint inbound add opcua \
    --address "opc.tcp://192.168.30.11:4840" \
    --device opc-ua-beckhoff-controller \
    --instance "${NE_IOT_INSTANCE}" \
    --name beckhoff-controller-opcua-server \
    --resource-group "${RESOURCE_GROUP}" \
    --ac true \
    --ad true \
    --security-mode none \
    --security-policy none || {
    echo -e "${RED}Failed to create IoT Ops device Endpoint${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating OPC UA Asset for Beckhoff Controller"
echo -e "======================================================================================================${RESET}"
az iot ops ns asset opcua create \
    --device opc-ua-beckhoff-controller \
    --endpoint beckhoff-controller-opcua-server \
    --instance "${NE_IOT_INSTANCE}" \
    --name beckhoff-controller \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create IoT Ops OPC UA Asset${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating Asset Dataset for Beckhoff Controller"
echo -e "======================================================================================================${RESET}"
az iot ops ns asset opcua dataset add \
    --asset beckhoff-controller \
    --data-source "" \
    --instance "${NE_IOT_INSTANCE}" \
    --name beckhoff-controller-ds \
    --resource-group "${RESOURCE_GROUP}" \
    --dest topic=azure-iot-operations/data/beckhoff-controller retain=Never qos=Qos1 ttl=3600 || {
    echo -e "${RED}Failed to create IoT Ops OPC UA Asset Dataset${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Adding Datapoints to Beckhoff Controller Asset"
echo -e "======================================================================================================${RESET}"

# FanSpeed
az iot ops ns asset opcua datapoint add \
    --asset beckhoff-controller \
    --data-source "ns=4;s=MAIN.nFan" \
    --dataset beckhoff-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name FanSpeed \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: FanSpeed${RESET}"
    exit 1
}

# Temperature
az iot ops ns asset opcua datapoint add \
    --asset beckhoff-controller \
    --data-source "ns=4;s=MAIN.nTemperature" \
    --dataset beckhoff-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name Temperature \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: Temperature${RESET}"
    exit 1
}

# IsLampOn
az iot ops ns asset opcua datapoint add \
    --asset beckhoff-controller \
    --data-source "ns=4;s=MAIN.bLamp" \
    --dataset beckhoff-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name IsLampOn \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: IsLampOn${RESET}"
    exit 1
}

# BlinkPattern
az iot ops ns asset opcua datapoint add \
    --asset beckhoff-controller \
    --data-source "ns=4;s=MAIN.nBlinkPattern" \
    --dataset beckhoff-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name BlinkPattern \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: BlinkPattern${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating Dataflow Endpoint for Beckhoff Controller"
echo -e "======================================================================================================${RESET}"
az iot ops dataflow endpoint create eventhub \
    --ehns aiomfgeventhub001 \
    --name beckhoff-controller \
    --instance "${NE_IOT_INSTANCE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --auth-type SystemAssignedManagedIdentity \
    --acks All || {
    echo -e "${RED}Failed to create IoT Ops Dataflow Endpoint${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating Dataflow Configuration for Beckhoff Controller"
echo -e "======================================================================================================${RESET}"

cat > /tmp/beckhoff-controller-df.json <<EOF
{
    "mode": "Enabled",
    "operations": [
        {
            "operationType": "Source",
            "sourceSettings": {
                "dataSources": [
                    "azure-iot-operations/data/beckhoff-controller"
                ],
                "endpointRef": "default",
                "serializationFormat": "Json"
            }
        },
        {
            "builtInTransformationSettings": {
                "datasets": [],
                "filter": [],
                "map": [
                    {
                        "inputs": [
                            "*"
                        ],
                        "output": "*",
                        "type": "PassThrough"
                    },
                    {
                        "expression": "\"${DATA_CENTER}\"",
                        "inputs": [],
                        "output": "\"hub\"",
                        "type": "NewProperties"
                    },
                    {
                        "expression": "\"${COUNTRY}\"",
                        "inputs": [],
                        "output": "\"country\"",
                        "type": "NewProperties"
                    },
                    {
                        "expression": "\"${STATE_REGION}\"",
                        "inputs": [],
                        "output": "\"stateProvince\"",
                        "type": "NewProperties"
                    },
                    {
                        "expression": "\"beckhoff-controller\"",
                        "inputs": [],
                        "output": "\"assetName\"",
                        "type": "NewProperties"
                    },
                    {
                        "expression": "\"${CLUSTER_NAME}\"",
                        "inputs": [],
                        "output": "\"iotInstanceName\"",
                        "type": "NewProperties"
                    }
                ],
                "serializationFormat": "Json"
            },
            "operationType": "BuiltInTransformation"
        },
        {
            "destinationSettings": {
                "dataDestination": "beckhoff-controller",
                "endpointRef": "beckhoff-controller",
                "headers": []
            },
            "operationType": "Destination"
        }
    ]
}
EOF

az iot ops dataflow apply \
    --config-file /tmp/beckhoff-controller-df.json \
    --instance "${NE_IOT_INSTANCE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name beckhoff-controller-df || {
    echo -e "${RED}Failed to create IoT Ops Dataflow${RESET}"
    exit 1
}

# Clean up
rm -f /tmp/beckhoff-controller-df.json

echo -e "${GREEN}======================================================================================================"
echo -e "Beckhoff Controller Configuration Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Device: opc-ua-beckhoff-controller${RESET}"
echo -e "${GREEN}Asset: beckhoff-controller${RESET}"
echo -e "${GREEN}Datapoints: 3 configured${RESET}"
echo -e "${GREEN}Dataflow: beckhoff-controller-df${RESET}"
EOFSCRIPT

# Replace placeholders in the script
sed -i "s|__SERVICE_PRINCIPAL_ID__|${SERVICE_PRINCIPAL_ID}|g" /tmp/configure-beckhoff.sh
sed -i "s|__SERVICE_PRINCIPAL_CLIENT_SECRET__|${SERVICE_PRINCIPAL_CLIENT_SECRET}|g" /tmp/configure-beckhoff.sh
sed -i "s|__SUBSCRIPTION_ID__|${SUBSCRIPTION_ID}|g" /tmp/configure-beckhoff.sh
sed -i "s|__TENANT_ID__|${TENANT_ID}|g" /tmp/configure-beckhoff.sh
sed -i "s|__RESOURCE_GROUP__|${RESOURCE_GROUP}|g" /tmp/configure-beckhoff.sh
sed -i "s|__NE_IOT_INSTANCE__|${NE_IOT_INSTANCE}|g" /tmp/configure-beckhoff.sh
sed -i "s|__DATA_CENTER__|${DATA_CENTER}|g" /tmp/configure-beckhoff.sh
sed -i "s|__COUNTRY__|${COUNTRY}|g" /tmp/configure-beckhoff.sh
sed -i "s|__STATE_REGION__|${STATE_REGION}|g" /tmp/configure-beckhoff.sh
sed -i "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" /tmp/configure-beckhoff.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Step 2: Copying Configuration Script to VM"
echo -e "======================================================================================================${RESET}"
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no /tmp/configure-beckhoff.sh ubuntu@${OT_NETWORK_VM_IP}:/tmp/configure-beckhoff.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to copy script to VM${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 3: Executing Beckhoff Controller Configuration on VM"
echo -e "======================================================================================================${RESET}"
echo -e "${YELLOW}This may take a few minutes...${RESET}"

ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${OT_NETWORK_VM_IP} "chmod +x /tmp/configure-beckhoff.sh && /tmp/configure-beckhoff.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to execute Beckhoff controller configuration on VM${RESET}"
    exit 1
fi

# Clean up
rm -f /tmp/configure-beckhoff.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Beckhoff Controller Configuration Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}The Beckhoff CX51x0 controller has been configured as an asset in Azure IoT Operations.${RESET}"
echo ""
echo -e "${GREEN}Configuration Summary:${RESET}"
echo -e "  Device: opc-ua-beckhoff-controller${RESET}"
echo -e "  Endpoint: opc.tcp://192.168.30.11:4840${RESET}"
echo -e "  Asset: beckhoff-controller${RESET}"
echo -e "  Datapoints:${RESET}"
echo -e "    - FanSpeed (ns=4;s=MAIN.nFan)${RESET}"
echo -e "    - Temperature (ns=4;s=MAIN.nTemperature)${RESET}"
echo -e "    - IsLampOn (ns=4;s=MAIN.bLamp)${RESET}"
echo -e "  Dataflow: beckhoff-controller-df -> Event Hub${RESET}"
echo ""
echo -e "${GREEN}You can verify the configuration in the Azure Portal:${RESET}"
echo -e "  Resource Group: ${RESOURCE_GROUP}${RESET}"
echo -e "  IoT Operations Instance: ${NE_IOT_INSTANCE}${RESET}"
echo ""
echo -e "${GREEN}Next Step: Run step7-leuze-controller-deployment.sh to configure the Leuze controller.${RESET}"
