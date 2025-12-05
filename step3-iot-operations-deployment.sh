#! /bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

export SERVICE_PRINCIPAL_ID="";
export SERVICE_PRINCIPAL_CLIENT_SECRET="";
export SUBSCRIPTION_ID="";
export RESOURCE_GROUP="";
export TENANT_ID="";
export LOCATION="eastus2";
export AUTH_TYPE="principal";
export CLOUD="AzureCloud";
export DATA_CENTER="CHI"
export CITY="Chicago"
export STATE_REGION="IL"
export COUNTRY="US"

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

# Create Azure IoT Operations Namespace Device for Beckhoff OPC UA Controller
az iot ops ns device create --name opc-ua-beckhoff-controller \
    --instance ${NE_IOT_INSTANCE} \
    -g ${RESOURCE_GROUP} \
    --model "CX51x0" \
    --os-version "1.0.51" \
    --manufacturer "Beckhoff" || {
    echo -e "${RED}Failed to create IoT Ops device${RESET}"
    exit 1
  }

# Create the Endpoint that is part of the device
az iot ops ns device endpoint inbound add opcua --address "opc.tcp://192.168.30.11:4840" \
    --device opc-ua-beckhoff-controller \
    --instance ${NE_IOT_INSTANCE} \
    --name beckhoff-controller-opcua-server \
    --resource-group ${RESOURCE_GROUP} \
    --ac true \
    --ad true \
    --security-mode none \
    --security-policy none || {
        echo -e "${RED}Failed to create IoT Ops device Endpoint${RESET}"
        exit 1 
    }

az iot ops ns asset opcua create --device opc-ua-beckhoff-controller \
    --endpoint beckhoff-controller-opcua-server \
    --instance ${NE_IOT_INSTANCE} \
    --name beckhoff-controller \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset${RESET}"
        exit 1 
    }

az iot ops ns asset opcua dataset add --asset beckhoff-controller \
    --data-source "" \
    --instance ${NE_IOT_INSTANCE} \
    --name beckhoff-controller-ds \
    --resource-group ${RESOURCE_GROUP} \
    --dest topic=azure-iot-operations/data/beckhoff-controller retain=Never qos=Qos1 ttl=3600 || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Dataset${RESET}"
        exit 1
    }

az iot ops ns asset opcua datapoint add --asset beckhoff-controller \
    --data-source "ns=4;s=MAIN.nFan" \
    --dataset beckhoff-controller-ds \
    --instance ${NE_IOT_INSTANCE} \
    --name FanSpeed \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Datapoint FanSpeed${RESET}"
        exit 1
    }


az iot ops ns asset opcua datapoint add --asset beckhoff-controller \
    --data-source "ns=4;s=MAIN.nTemperature" \
    --dataset beckhoff-controller-ds \
    --instance ${NE_IOT_INSTANCE} \
    --name Temperature \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Datapoint Temperature${RESET}"
        exit 1
    }

az iot ops ns asset opcua datapoint add --asset beckhoff-controller \
    --data-source "ns=4;s=MAIN.bLamp" \
    --dataset beckhoff-controller-ds \
    --instance ${NE_IOT_INSTANCE} \
    --name IsLampOn \
    --resource-group ${RESOURCE_GROUP} || {
        echo -e "${RED}Failed to create IoT Ops OPC UA Asset Datapoint IsLampOn${RESET}"
        exit 1
    }

az iot ops dataflow endpoint create eventhub --ehns aiomfgeventhub001 \
    --name beckhoff-controller \
    --instance ${NE_IOT_INSTANCE} \
    --resource-group ${RESOURCE_GROUP} \
    --auth-type SystemAssignedManagedIdentity \
    --acks All  || {
        echo -e "${RED}Failed to create IoT Ops Dataflow Endpoint${RESET}"
        exit 1
    }

cat > ./beckhoff-controller-df.json <<EOF
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

az iot ops dataflow apply --config-file ./beckhoff-controller-df.json \
    --instance ${NE_IOT_INSTANCE} \
    --resource-group ${RESOURCE_GROUP} \
    --name beckhoff-controller-df   || {
        echo -e "${RED}Failed to create IoT Ops Dataflow${RESET}"
        exit 1
    }




