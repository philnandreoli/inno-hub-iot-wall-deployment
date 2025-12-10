#! /bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# Usage function
usage() {
    cat <<EOF
${YELLOW}Usage: $0 --sp-id <ID> --sp-secret <SECRET> --subscription-id <ID> --tenant-id <ID> --location <LOC> --data-center <DC> --country <COUNTRY>${RESET}

${GREEN}Required Arguments:${RESET}
  --sp-id             : The Service Principal ID from the IoT-Wall-V2 secret in the MTC SHARED Vault
  --sp-secret         : The Service Principal Client Secret from the vault
  --subscription-id   : The Azure Subscription ID
  --tenant-id         : The Azure Tenant ID
  --location          : Azure Location (e.g., eastus2 for AMERICAS)
  --data-center       : Data Center Code (e.g., CHI for Chicago, STL for St. Louis)
  --country           : Two-letter country code (e.g., US, NL)

${YELLOW}Note: Resource group will be auto-created with naming convention: EXP-MFG-AIO-\${DATA_CENTER}-\${COUNTRY}-RG${RESET}

${GREEN}Example:${RESET}
  $0 --sp-id "sp-id-here" --sp-secret "sp-secret-here" --subscription-id "sub-id-here" --tenant-id "tenant-id-here" \\
     --location "eastus2" --data-center "CHI" --country "US"
EOF
    exit 1
}

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --sp-id)
            SERVICE_PRINCIPAL_ID="$2"
            shift 2
            ;;
        --sp-secret)
            SERVICE_PRINCIPAL_CLIENT_SECRET="$2"
            shift 2
            ;;
        --subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --data-center)
            DATA_CENTER="$2"
            shift 2
            ;;
        --country)
            COUNTRY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown argument: $1${RESET}"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "${SERVICE_PRINCIPAL_ID}" ] || [ -z "${SERVICE_PRINCIPAL_CLIENT_SECRET}" ] || [ -z "${SUBSCRIPTION_ID}" ] || \
   [ -z "${TENANT_ID}" ] || [ -z "${LOCATION}" ] || [ -z "${DATA_CENTER}" ] || [ -z "${COUNTRY}" ]; then
    echo -e "${RED}Error: Missing required arguments${RESET}"
    usage
fi

export SERVICE_PRINCIPAL_ID
export SERVICE_PRINCIPAL_CLIENT_SECRET
export SUBSCRIPTION_ID
export TENANT_ID
export LOCATION
export DATA_CENTER
export COUNTRY

# Dynamically create resource group name based on data center and country
export RESOURCE_GROUP="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"
export LOCATION
export DATA_CENTER

# Set constant values
export AUTH_TYPE="principal"
export CLOUD="AzureCloud"

export SERVICE_TAG=$(hostname -s)

export CLUSTER_NAME="${DATA_CENTER}-${SERVICE_TAG}-k3s"
export IOTOPS_CLUSTER_NAME="${DATA_CENTER}-${SERVICE_TAG}-aio-cluster"
export NE_IOT_INSTANCE="${DATA_CENTER}-${SERVICE_TAG}-aio-instance"
export NE_IOT_NAMESPACE="${DATA_CENTER}-${SERVICE_TAG}-aio-namespace"

NE_IOT_INSTANCE=$(echo "${NE_IOT_INSTANCE}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g'  )
NE_IOT_NAMESPACE=$(echo "${NE_IOT_NAMESPACE}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g'  )
CLUSTER_NAME=$(echo "${CLUSTER_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g'  )

echo -e "${GREEN}======================================================================================================"
echo -e " Step 1.... Logging into Azure using Service Principal"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription $SUBSCRIPTION_ID

az config set extension.dynamic_install_allow_preview=true
az extension add --name azure-iot-ops

# Create Azure IoT Operations Namespace Device for Leuze OPC UA Controller
az iot ops ns device create --name opc-ua-leuze-controller \
    --instance ${NE_IOT_INSTANCE} \
    -g ${RESOURCE_GROUP} \
    --model "BCL300i" \
    --os-version "2.1.0" \
    --manufacturer "Leuze Electronic" || {
    echo -e "${RED}Failed to create IoT Ops device${RESET}"
    exit 1
  }

# Create the Endpoint that is part of the device
az iot ops ns device endpoint inbound add opcua --address "opc.tcp://192.168.30.21:4840" \
    --device opc-ua-leuze-controller \
    --instance ${NE_IOT_INSTANCE} \
    --name leuze-controller-opcua-server \
    --resource-group ${RESOURCE_GROUP} \
    --ac true \
    --ad true \
    --security-mode none \
    --security-policy none || {
        echo -e "${RED}Failed to create IoT Ops device Endpoint${RESET}"
        exit 1 
    }

az iot ops ns asset opcua create --device opc-ua-leuze-controller \
    --endpoint leuze-controller-opcua-server \
    --instance ${NE_IOT_INSTANCE} \
    --name leuze-controller \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset${RESET}"
        exit 1 
    }

az iot ops ns asset opcua dataset add --asset leuze-controller \
    --data-source "" \
    --instance ${NE_IOT_INSTANCE} \
    --name leuze-controller-ds \
    --resource-group ${RESOURCE_GROUP} \
    --dest topic=azure-iot-operations/data/leuze-controller retain=Never qos=Qos1 ttl=3600 || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Dataset${RESET}"
        exit 1
    }

az iot ops ns asset opcua datapoint add --asset leuze-controller \
    --data-source "ns=3;i=40901" \
    --dataset leuze-controller-ds \
    --instance ${NE_IOT_INSTANCE} \
    --name LastReadBarcode \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Datapoint LastReadBarcode${RESET}"
        exit 1
    }


az iot ops ns asset opcua datapoint add --asset leuze-controller \
    --data-source "ns=3;i=40903" \
    --dataset leuze-controller-ds \
    --instance ${NE_IOT_INSTANCE} \
    --name LastReadBarcodeAngle \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Datapoint LastReadBarcodeAngle${RESET}"
        exit 1
    }

az iot ops ns asset opcua datapoint add --asset leuze-controller \
    --data-source "ns=3;i=40902" \
    --dataset leuze-controller-ds \
    --instance ${NE_IOT_INSTANCE} \
    --name LastReadBarcodeQuality \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Datapoint LastReadBarcodeQuality${RESET}"
        exit 1
    }

az iot ops ns asset opcua datapoint add --asset leuze-controller \
    --data-source "ns=3;i=40905" \
    --dataset leuze-controller-ds \
    --instance ${NE_IOT_INSTANCE} \
    --name ReadingGatesCounter \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Datapoint ReadingGatesCounter${RESET}"
        exit 1
    }

az iot ops ns asset opcua datapoint add --asset leuze-controller \
    --data-source "ns=3;i=40904" \
    --dataset leuze-controller-ds \
    --instance ${NE_IOT_INSTANCE} \
    --name ReadingGatesPerMinute \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Datapoint ReadingGatesPerMinute${RESET}"
        exit 1
    }

az iot ops ns asset opcua datapoint add --asset leuze-controller \
    --data-source "ns=3;i=70001" \
    --dataset leuze-controller-ds \
    --instance ${NE_IOT_INSTANCE} \
    --name Temperature \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Datapoint Temperature${RESET}"
        exit 1
    }

az iot ops dataflow endpoint create eventhub --ehns aiomfgeventhub001 \
    --name leuze-controller \
    --instance ${NE_IOT_INSTANCE} \
    --resource-group ${RESOURCE_GROUP} \
    --auth-type SystemAssignedManagedIdentity \
    --acks All  || {
        echo -e "${RED}Failed to create IoT Ops Dataflow Endpoint${RESET}"
        exit 1
    }

cat > ./leuze-controller-df.json <<EOF
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

az iot ops dataflow apply --config-file ./leuze-controller-df.json \
    --instance ${NE_IOT_INSTANCE} \
    --resource-group ${RESOURCE_GROUP} \
    --name leuze-controller-df   || {
        echo -e "${RED}Failed to create IoT Ops Dataflow${RESET}"
        exit 1
    }




