#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Deploy Leuze Controller Configuration - Step 6
# ============================================================================
# This script configures the Leuze OPC UA controller as an asset in
# Azure IoT Operations, including device, endpoint, asset, dataset,
# datapoints, and dataflow configuration.
# It runs FROM THE HOST and connects to the VM via SSH.
#
# Prerequisites:
# - IoT Operations must be deployed (step5 completed)
# - SSH connectivity to VM must be working
# ============================================================================

# Required Environment Variables
export SERVICE_PRINCIPAL_ID=""
export SERVICE_PRINCIPAL_CLIENT_SECRET=""
export SUBSCRIPTION_ID=""
export TENANT_ID=""
export RESOURCE_GROUP=""
export LOCATION="eastus2"
export DATA_CENTER=""
export CITY=""
export STATE_REGION=""
export COUNTRY=""

# VM Configuration
export HOST_NAME=$(hostname -s)
export VM_NAME="${HOST_NAME}-vm"
export OT_NETWORK_VM_IP="192.168.30.18"
export SSH_KEY_PATH="$HOME/.ssh/vm_id_rsa"

# Azure IoT Operations Resource Names
export CLUSTER_NAME="${DATA_CENTER}-${VM_NAME}-k3s"
export NE_IOT_INSTANCE="${DATA_CENTER}-${VM_NAME}-aio-instance"

# Convert to lowercase
CLUSTER_NAME=$(echo "${CLUSTER_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
NE_IOT_INSTANCE=$(echo "${NE_IOT_INSTANCE}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')

echo -e "${GREEN}======================================================================================================"
echo -e " Deploy Leuze Controller Configuration - Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}VM Name: ${VM_NAME}${RESET}"
echo -e "${GREEN}IoT Instance: ${NE_IOT_INSTANCE}${RESET}"
echo -e "${GREEN}Resource Group: ${RESOURCE_GROUP}${RESET}"
echo ""

# Validation
if [ -z "$SERVICE_PRINCIPAL_ID" ] || [ -z "$SERVICE_PRINCIPAL_CLIENT_SECRET" ] || \
   [ -z "$SUBSCRIPTION_ID" ] || [ -z "$TENANT_ID" ] || [ -z "$RESOURCE_GROUP" ] || \
   [ -z "$DATA_CENTER" ] || [ -z "$CITY" ] || [ -z "$STATE_REGION" ] || [ -z "$COUNTRY" ]; then
    echo -e "${RED}ERROR: Required environment variables are not set. Please configure all required variables.${RESET}"
    exit 1
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}ERROR: SSH key not found at ${SSH_KEY_PATH}${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 1: Creating Leuze Controller Configuration Script"
echo -e "======================================================================================================${RESET}"

# Create a script that will run on the VM
cat > /tmp/configure-leuze.sh <<'EOFSCRIPT'
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
echo -e "Creating IoT Ops Device for Leuze OPC UA Controller"
echo -e "======================================================================================================${RESET}"
az iot ops ns device create \
    --name opc-ua-leuze-controller \
    --instance "${NE_IOT_INSTANCE}" \
    -g "${RESOURCE_GROUP}" \
    --model "BCL300i" \
    --os-version "2.1.0" \
    --manufacturer "Leuze Electronic" || {
    echo -e "${RED}Failed to create IoT Ops device${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating Device Endpoint for Leuze Controller"
echo -e "======================================================================================================${RESET}"
az iot ops ns device endpoint inbound add opcua \
    --address "opc.tcp://192.168.30.21:4840" \
    --device opc-ua-leuze-controller \
    --instance "${NE_IOT_INSTANCE}" \
    --name leuze-controller-opcua-server \
    --resource-group "${RESOURCE_GROUP}" \
    --ac true \
    --ad true \
    --security-mode none \
    --security-policy none || {
    echo -e "${RED}Failed to create IoT Ops device Endpoint${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating OPC UA Asset for Leuze Controller"
echo -e "======================================================================================================${RESET}"
az iot ops ns asset opcua create \
    --device opc-ua-leuze-controller \
    --endpoint leuze-controller-opcua-server \
    --instance "${NE_IOT_INSTANCE}" \
    --name leuze-controller \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create IoT Ops OPC UA Asset${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating Asset Dataset for Leuze Controller"
echo -e "======================================================================================================${RESET}"
az iot ops ns asset opcua dataset add \
    --asset leuze-controller \
    --data-source "" \
    --instance "${NE_IOT_INSTANCE}" \
    --name leuze-controller-ds \
    --resource-group "${RESOURCE_GROUP}" \
    --dest topic=azure-iot-operations/data/leuze-controller retain=Never qos=Qos1 ttl=3600 || {
    echo -e "${RED}Failed to create IoT Ops OPC UA Asset Dataset${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Adding Datapoints to Leuze Controller Asset"
echo -e "======================================================================================================${RESET}"

# LastReadBarcode
az iot ops ns asset opcua datapoint add \
    --asset leuze-controller \
    --data-source "ns=3;i=40901" \
    --dataset leuze-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name LastReadBarcode \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: LastReadBarcode${RESET}"
    exit 1
}

# LastReadBarcodeAngle
az iot ops ns asset opcua datapoint add \
    --asset leuze-controller \
    --data-source "ns=3;i=40903" \
    --dataset leuze-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name LastReadBarcodeAngle \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: LastReadBarcodeAngle${RESET}"
    exit 1
}

# LastReadBarcodeQuality
az iot ops ns asset opcua datapoint add \
    --asset leuze-controller \
    --data-source "ns=3;i=40902" \
    --dataset leuze-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name LastReadBarcodeQuality \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: LastReadBarcodeQuality${RESET}"
    exit 1
}

# ReadingGatesCounter
az iot ops ns asset opcua datapoint add \
    --asset leuze-controller \
    --data-source "ns=3;i=40905" \
    --dataset leuze-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name ReadingGatesCounter \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: ReadingGatesCounter${RESET}"
    exit 1
}

# ReadingGatesPerMinute
az iot ops ns asset opcua datapoint add \
    --asset leuze-controller \
    --data-source "ns=3;i=40904" \
    --dataset leuze-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name ReadingGatesPerMinute \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: ReadingGatesPerMinute${RESET}"
    exit 1
}

# Temperature
az iot ops ns asset opcua datapoint add \
    --asset leuze-controller \
    --data-source "ns=3;i=70001" \
    --dataset leuze-controller-ds \
    --instance "${NE_IOT_INSTANCE}" \
    --name Temperature \
    --resource-group "${RESOURCE_GROUP}" || {
    echo -e "${RED}Failed to create datapoint: Temperature${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating Dataflow Endpoint for Leuze Controller"
echo -e "======================================================================================================${RESET}"
az iot ops dataflow endpoint create eventhub \
    --ehns aiomfgeventhub001 \
    --name leuze-controller \
    --instance "${NE_IOT_INSTANCE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --auth-type SystemAssignedManagedIdentity \
    --acks All || {
    echo -e "${RED}Failed to create IoT Ops Dataflow Endpoint${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Creating Dataflow Configuration for Leuze Controller"
echo -e "======================================================================================================${RESET}"

cat > /tmp/leuze-controller-df.json <<EOF
{
    "mode": "Enabled",
    "operations": [
        {
            "operationType": "Source",
            "sourceSettings": {
                "dataSources": [
                    "azure-iot-operations/data/leuze-controller"
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
                        "expression": "\"leuze-controller\"",
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
                "dataDestination": "leuze-controller",
                "endpointRef": "leuze-controller",
                "headers": []
            },
            "operationType": "Destination"
        }
    ]
}
EOF

az iot ops dataflow apply \
    --config-file /tmp/leuze-controller-df.json \
    --instance "${NE_IOT_INSTANCE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name leuze-controller-df || {
    echo -e "${RED}Failed to create IoT Ops Dataflow${RESET}"
    exit 1
}

# Clean up
rm -f /tmp/leuze-controller-df.json

echo -e "${GREEN}======================================================================================================"
echo -e "Leuze Controller Configuration Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Device: opc-ua-leuze-controller${RESET}"
echo -e "${GREEN}Asset: leuze-controller${RESET}"
echo -e "${GREEN}Datapoints: 6 configured${RESET}"
echo -e "${GREEN}Dataflow: leuze-controller-df${RESET}"
EOFSCRIPT

# Replace placeholders in the script
sed -i "s|__SERVICE_PRINCIPAL_ID__|${SERVICE_PRINCIPAL_ID}|g" /tmp/configure-leuze.sh
sed -i "s|__SERVICE_PRINCIPAL_CLIENT_SECRET__|${SERVICE_PRINCIPAL_CLIENT_SECRET}|g" /tmp/configure-leuze.sh
sed -i "s|__SUBSCRIPTION_ID__|${SUBSCRIPTION_ID}|g" /tmp/configure-leuze.sh
sed -i "s|__TENANT_ID__|${TENANT_ID}|g" /tmp/configure-leuze.sh
sed -i "s|__RESOURCE_GROUP__|${RESOURCE_GROUP}|g" /tmp/configure-leuze.sh
sed -i "s|__NE_IOT_INSTANCE__|${NE_IOT_INSTANCE}|g" /tmp/configure-leuze.sh
sed -i "s|__DATA_CENTER__|${DATA_CENTER}|g" /tmp/configure-leuze.sh
sed -i "s|__COUNTRY__|${COUNTRY}|g" /tmp/configure-leuze.sh
sed -i "s|__STATE_REGION__|${STATE_REGION}|g" /tmp/configure-leuze.sh
sed -i "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" /tmp/configure-leuze.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Step 2: Copying Configuration Script to VM"
echo -e "======================================================================================================${RESET}"
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no /tmp/configure-leuze.sh ubuntu@${OT_NETWORK_VM_IP}:/tmp/configure-leuze.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to copy script to VM${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 3: Executing Leuze Controller Configuration on VM"
echo -e "======================================================================================================${RESET}"
echo -e "${YELLOW}This may take a few minutes...${RESET}"

ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${OT_NETWORK_VM_IP} "chmod +x /tmp/configure-leuze.sh && /tmp/configure-leuze.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to execute Leuze controller configuration on VM${RESET}"
    exit 1
fi

# Clean up
rm -f /tmp/configure-leuze.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Leuze Controller Configuration Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}The Leuze BCL300i controller has been configured as an asset in Azure IoT Operations.${RESET}"
echo ""
echo -e "${GREEN}Configuration Summary:${RESET}"
echo -e "  Device: opc-ua-leuze-controller${RESET}"
echo -e "  Endpoint: opc.tcp://192.168.30.21:4840${RESET}"
echo -e "  Asset: leuze-controller${RESET}"
echo -e "  Datapoints:${RESET}"
echo -e "    - LastReadBarcode${RESET}"
echo -e "    - LastReadBarcodeAngle${RESET}"
echo -e "    - LastReadBarcodeQuality${RESET}"
echo -e "    - ReadingGatesCounter${RESET}"
echo -e "    - ReadingGatesPerMinute${RESET}"
echo -e "    - Temperature${RESET}"
echo -e "  Dataflow: leuze-controller-df -> Event Hub${RESET}"
echo ""
echo -e "${GREEN}You can verify the configuration in the Azure Portal:${RESET}"
echo -e "  Resource Group: ${RESOURCE_GROUP}${RESET}"
echo -e "  IoT Operations Instance: ${NE_IOT_INSTANCE}${RESET}"
