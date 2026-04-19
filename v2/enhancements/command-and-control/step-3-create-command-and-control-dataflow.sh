#!/bin/bash

set -euo pipefail

RED='\e[31m'
YELLOW='\e[33m'
GREEN='\e[32m'
RESET='\e[0m'

DATAFLOW_NAME="cloud-to-device-command-control"
PROFILE_NAME="command-and-control"
SOURCE_ENDPOINT="demo"
DESTINATION_ENDPOINT="default"
DESTINATION_TOPIC="azure-iot-operations/asset-operations/beckhoff-controller/builtin/actuator-states"
SUBSCRIPTION_ID=""
INSTANCE_NAME=""
RESOURCE_GROUP=""

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Creates the '${DATAFLOW_NAME}' dataflow under the '${PROFILE_NAME}' profile on
every IoT Operations instance in a single subscription. If the dataflow already
exists on an instance, it is skipped.

The dataflow routes messages from the '${SOURCE_ENDPOINT}' Event Grid endpoint
to the '${DESTINATION_ENDPOINT}' local MQTT broker using a passthrough
transformation. The source topic is scoped to the Arc cluster name of each
instance automatically.

  Source endpoint:    ${SOURCE_ENDPOINT}  (Azure Event Grid)
  Source topic:       /iotoperations/{cluster-name}/#
  Destination endpoint: ${DESTINATION_ENDPOINT}  (local MQTT broker)
  Destination topic:  ${DESTINATION_TOPIC}

Options:
  --subscription-id ID    Azure subscription to target. If omitted, the current
                          Azure CLI subscription is used.
  --instance-name NAME    Optional IoT Operations instance name to target.
  --resource-group NAME   Optional resource group filter. Useful with
                          --instance-name when the same name exists in more than
                          one resource group.
  -h, --help              Show this help text.

Prerequisites:
  - Azure CLI is installed and authenticated with 'az login'.
  - The '${PROFILE_NAME}' dataflow profile exists (step 1).
  - The '${SOURCE_ENDPOINT}' dataflow endpoint exists (step 2).
  - You have permission to list IoT Operations instances and manage dataflows.

Examples:
  $0 --subscription-id 00000000-0000-0000-0000-000000000000
  $0 --subscription-id 00000000-0000-0000-0000-000000000000 --instance-name my-aio-instance
  $0 --instance-name my-aio-instance --resource-group EXP-MFG-AIO-CHI-US-RG
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --instance-name)
            INSTANCE_NAME="$2"
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET}"
            usage
            exit 1
            ;;
    esac
done

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo -e "${RED}Required command not found: ${command_name}${RESET}"
        exit 1
    fi
}

require_command az

if ! az account show >/dev/null 2>&1; then
    echo -e "${RED}Azure CLI is not logged in. Run 'az login' first.${RESET}"
    exit 1
fi

if [[ -n "${SUBSCRIPTION_ID}" ]]; then
    echo -e "${GREEN}Setting Azure subscription to ${SUBSCRIPTION_ID}${RESET}"
    az account set --subscription "${SUBSCRIPTION_ID}"
fi

CURRENT_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
CURRENT_SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

echo -e "${GREEN}======================================================================================================${RESET}"
echo -e "${GREEN}Azure IoT Operations Dataflow Bootstrap${RESET}"
echo -e "${GREEN}======================================================================================================${RESET}"
echo -e "${GREEN}Subscription: ${CURRENT_SUBSCRIPTION_NAME} (${CURRENT_SUBSCRIPTION_ID})${RESET}"
echo -e "${GREEN}Dataflow Name: ${DATAFLOW_NAME}${RESET}"
echo -e "${GREEN}Profile: ${PROFILE_NAME}${RESET}"
echo -e "${GREEN}Source Endpoint: ${SOURCE_ENDPOINT}${RESET}"
echo -e "${GREEN}Destination Endpoint: ${DESTINATION_ENDPOINT}${RESET}"
echo -e "${GREEN}Destination Topic: ${DESTINATION_TOPIC}${RESET}"
if [[ -n "${INSTANCE_NAME}" ]]; then
    echo -e "${GREEN}Instance Filter: ${INSTANCE_NAME}${RESET}"
fi
if [[ -n "${RESOURCE_GROUP}" ]]; then
    echo -e "${GREEN}Resource Group Filter: ${RESOURCE_GROUP}${RESET}"
fi

echo -e "${GREEN}Ensuring Azure IoT Operations CLI extension is installed${RESET}"
az extension add --name azure-iot-ops --upgrade --allow-preview --only-show-errors >/dev/null

LIST_ARGS=(--subscription "${CURRENT_SUBSCRIPTION_ID}" --query "[].{name:name,resourceGroup:resourceGroup}" --output tsv)
if [[ -n "${RESOURCE_GROUP}" ]]; then
    LIST_ARGS=(--resource-group "${RESOURCE_GROUP}" --subscription "${CURRENT_SUBSCRIPTION_ID}" --query "[].{name:name,resourceGroup:resourceGroup}" --output tsv)
fi

INSTANCE_ROWS=$(az iot ops list "${LIST_ARGS[@]}")

if [[ -z "${INSTANCE_ROWS}" ]]; then
    echo -e "${YELLOW}No Azure IoT Operations instances found in subscription ${CURRENT_SUBSCRIPTION_ID}.${RESET}"
    exit 0
fi

CREATED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0
MATCHED_COUNT=0

while IFS=$'\t' read -r FOUND_INSTANCE_NAME FOUND_RESOURCE_GROUP; do
    [[ -z "${FOUND_INSTANCE_NAME}" ]] && continue

    if [[ -n "${INSTANCE_NAME}" && "${FOUND_INSTANCE_NAME}" != "${INSTANCE_NAME}" ]]; then
        continue
    fi

    MATCHED_COUNT=$((MATCHED_COUNT + 1))

    echo -e "${GREEN}------------------------------------------------------------------------------------------------------${RESET}"
    echo -e "${GREEN}Instance: ${FOUND_INSTANCE_NAME}${RESET}"
    echo -e "${GREEN}Resource Group: ${FOUND_RESOURCE_GROUP}${RESET}"

    # Resolve the Arc cluster name from the instance's custom location
    echo -e "${GREEN}Resolving Arc cluster name...${RESET}"
    CUSTOM_LOCATION_ID=$(az iot ops show \
        --name "${FOUND_INSTANCE_NAME}" \
        --resource-group "${FOUND_RESOURCE_GROUP}" \
        --subscription "${CURRENT_SUBSCRIPTION_ID}" \
        --query "extendedLocation.name" \
        --output tsv)

    if [[ -z "${CUSTOM_LOCATION_ID}" ]]; then
        echo -e "${RED}Could not resolve custom location for instance '${FOUND_INSTANCE_NAME}'. Skipping.${RESET}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi

    CUSTOM_LOCATION_RESOURCE_GROUP=$(echo "${CUSTOM_LOCATION_ID}" | awk -F'/' '{for (i=1; i<=NF; i++) if ($i == "resourceGroups") {print $(i+1); exit}}')
    CUSTOM_LOCATION_NAME=$(echo "${CUSTOM_LOCATION_ID}" | awk -F'/' '{print $NF}')

    if [[ -z "${CUSTOM_LOCATION_RESOURCE_GROUP}" || -z "${CUSTOM_LOCATION_NAME}" ]]; then
        echo -e "${RED}Could not parse custom location resource group/name from '${CUSTOM_LOCATION_ID}'. Skipping.${RESET}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi

    CLUSTER_NAME=$(az customlocation show \
        --name "${CUSTOM_LOCATION_NAME}" \
        --resource-group "${CUSTOM_LOCATION_RESOURCE_GROUP}" \
        --subscription "${CURRENT_SUBSCRIPTION_ID}" \
        --query "hostResourceId" \
        --output tsv | awk -F'/' '{print $NF}')

    if [[ -z "${CLUSTER_NAME}" ]]; then
        echo -e "${RED}Could not resolve Arc cluster name for instance '${FOUND_INSTANCE_NAME}'. Skipping.${RESET}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi

    SOURCE_TOPIC="/iotoperations/${CLUSTER_NAME}/#"
    echo -e "${GREEN}Arc Cluster Name: ${CLUSTER_NAME}${RESET}"
    echo -e "${GREEN}Source Topic: ${SOURCE_TOPIC}${RESET}"

    # Check if the dataflow already exists under the command-and-control profile
    if az iot ops dataflow show \
        --instance "${FOUND_INSTANCE_NAME}" \
        --name "${DATAFLOW_NAME}" \
        --profile "${PROFILE_NAME}" \
        --resource-group "${FOUND_RESOURCE_GROUP}" \
        --subscription "${CURRENT_SUBSCRIPTION_ID}" \
        --only-show-errors >/dev/null 2>&1; then
        echo -e "${YELLOW}Dataflow '${DATAFLOW_NAME}' already exists under profile '${PROFILE_NAME}'. Skipping.${RESET}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Write the dataflow config to a temp file
    CONFIG_FILE="/tmp/${DATAFLOW_NAME}-${FOUND_INSTANCE_NAME}.json"
    cat > "${CONFIG_FILE}" <<EOF
{
    "mode": "Enabled",
    "operations": [
        {
            "operationType": "Source",
            "sourceSettings": {
                "endpointRef": "${SOURCE_ENDPOINT}",
                "dataSources": [
                    "${SOURCE_TOPIC}"
                ],
                "serializationFormat": "Json"
            }
        },
        {
            "operationType": "BuiltInTransformation",
            "builtInTransformationSettings": {
                "serializationFormat": "Json",
                "datasets": [],
                "filter": [],
                "map": [
                    {
                        "type": "PassThrough",
                        "inputs": [
                            "*"
                        ],
                        "output": "*"
                    }
                ]
            }
        },
        {
            "operationType": "Destination",
            "destinationSettings": {
                "endpointRef": "${DESTINATION_ENDPOINT}",
                "dataDestination": "${DESTINATION_TOPIC}"
            }
        }
    ]
}
EOF

    if az iot ops dataflow apply \
        --instance "${FOUND_INSTANCE_NAME}" \
        --name "${DATAFLOW_NAME}" \
        --profile "${PROFILE_NAME}" \
        --resource-group "${FOUND_RESOURCE_GROUP}" \
        --subscription "${CURRENT_SUBSCRIPTION_ID}" \
        --config-file "${CONFIG_FILE}" \
        --only-show-errors >/dev/null; then
        echo -e "${GREEN}Created dataflow '${DATAFLOW_NAME}'.${RESET}"
        CREATED_COUNT=$((CREATED_COUNT + 1))
    else
        echo -e "${RED}Failed to create dataflow '${DATAFLOW_NAME}'.${RESET}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    rm -f "${CONFIG_FILE}"

done <<< "${INSTANCE_ROWS}"

if [[ ${MATCHED_COUNT} -eq 0 ]]; then
    if [[ -n "${INSTANCE_NAME}" ]]; then
        echo -e "${YELLOW}No Azure IoT Operations instance named '${INSTANCE_NAME}' matched the requested scope.${RESET}"
        exit 1
    fi

    echo -e "${YELLOW}No Azure IoT Operations instances matched the requested scope.${RESET}"
    exit 0
fi

echo -e "${GREEN}======================================================================================================${RESET}"
echo -e "${GREEN}Summary${RESET}"
echo -e "${GREEN}======================================================================================================${RESET}"
echo -e "${GREEN}Matched Instances: ${MATCHED_COUNT}${RESET}"
echo -e "${GREEN}Created: ${CREATED_COUNT}${RESET}"
echo -e "${YELLOW}Skipped: ${SKIPPED_COUNT}${RESET}"
if [[ ${FAILED_COUNT} -gt 0 ]]; then
    echo -e "${RED}Failed: ${FAILED_COUNT}${RESET}"
    exit 1
fi

echo -e "${GREEN}Completed without errors.${RESET}"
