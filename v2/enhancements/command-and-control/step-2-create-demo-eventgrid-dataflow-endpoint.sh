#!/bin/bash

set -euo pipefail

RED='\e[31m'
YELLOW='\e[33m'
GREEN='\e[32m'
RESET='\e[0m'

ENDPOINT_NAME="demo"
EVENTGRID_HOSTNAME=""
EVENTGRID_PORT=8883
SUBSCRIPTION_ID=""
INSTANCE_NAME=""
RESOURCE_GROUP=""

usage() {
    cat <<EOF
Usage: $0 --eventgrid-hostname HOSTNAME [OPTIONS]

Creates the '${ENDPOINT_NAME}' Azure IoT Operations dataflow endpoint pointing to
an Azure Event Grid namespace on every IoT Operations instance in a single
subscription. If the endpoint already exists on an instance, it is updated.

Required:
  --eventgrid-hostname HOSTNAME   The HTTP hostname of the Azure Event Grid namespace.
                                  Found under 'Http hostname' in the namespace overview.
                                  Format: NAMESPACE.REGION-1.ts.eventgrid.azure.net
  --port PORT                     Port number for the Event Grid namespace. Default: 8883.

Options:
  --subscription-id ID    Azure subscription to target. If omitted, the current
                          Azure CLI subscription is used.
  --instance-name NAME    Optional IoT Operations instance name to target.
  --resource-group NAME   Optional resource group filter. Useful with
                          --instance-name when the same name exists in more than
                          one resource group.
  -h, --help              Show this help text.

Prerequisites:
  - Azure CLI is installed.
  - You are already authenticated with 'az login'.
  - You have permission to list Azure IoT Operations instances and manage
    dataflow endpoints in the target subscription.

Examples:
  $0 --eventgrid-hostname "mynamespace.eastus2-1.ts.eventgrid.azure.net"
  $0 --eventgrid-hostname "mynamespace.eastus2-1.ts.eventgrid.azure.net" \\
     --subscription-id 00000000-0000-0000-0000-000000000000
  $0 --eventgrid-hostname "mynamespace.eastus2-1.ts.eventgrid.azure.net" \\
     --subscription-id 00000000-0000-0000-0000-000000000000 \\
     --instance-name my-aio-instance \\
     --resource-group EXP-MFG-AIO-CHI-US-RG
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --eventgrid-hostname)
            EVENTGRID_HOSTNAME="$2"
            shift 2
            ;;
        --port)
            EVENTGRID_PORT="$2"
            shift 2
            ;;
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

if [[ -z "${EVENTGRID_HOSTNAME}" ]]; then
    echo -e "${RED}--eventgrid-hostname is required.${RESET}"
    echo ""
    usage
    exit 1
fi

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
echo -e "${GREEN}Azure IoT Operations Dataflow Endpoint Bootstrap${RESET}"
echo -e "${GREEN}======================================================================================================${RESET}"
echo -e "${GREEN}Subscription: ${CURRENT_SUBSCRIPTION_NAME} (${CURRENT_SUBSCRIPTION_ID})${RESET}"
echo -e "${GREEN}Endpoint Name: ${ENDPOINT_NAME}${RESET}"
echo -e "${GREEN}Event Grid Hostname: ${EVENTGRID_HOSTNAME}${RESET}"
echo -e "${GREEN}Event Grid Port: ${EVENTGRID_PORT}${RESET}"
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
UPDATED_COUNT=0
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

    if az iot ops dataflow endpoint show \
        --instance "${FOUND_INSTANCE_NAME}" \
        --name "${ENDPOINT_NAME}" \
        --resource-group "${FOUND_RESOURCE_GROUP}" \
        --subscription "${CURRENT_SUBSCRIPTION_ID}" \
        --only-show-errors >/dev/null 2>&1; then
        if az iot ops dataflow endpoint update eventgrid \
            --instance "${FOUND_INSTANCE_NAME}" \
            --name "${ENDPOINT_NAME}" \
            --resource-group "${FOUND_RESOURCE_GROUP}" \
            --subscription "${CURRENT_SUBSCRIPTION_ID}" \
            --client-id-prefix "${FOUND_INSTANCE_NAME}" \
            --hostname "${EVENTGRID_HOSTNAME}" \
            --port "${EVENTGRID_PORT}" \
            --auth-type SystemAssignedManagedIdentity \
            --only-show-errors >/dev/null; then
            echo -e "${GREEN}Updated endpoint '${ENDPOINT_NAME}'.${RESET}"
            UPDATED_COUNT=$((UPDATED_COUNT + 1))
        else
            echo -e "${RED}Failed to update endpoint '${ENDPOINT_NAME}'.${RESET}"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
        continue
    fi

    if az iot ops dataflow endpoint create eventgrid \
        --instance "${FOUND_INSTANCE_NAME}" \
        --name "${ENDPOINT_NAME}" \
        --resource-group "${FOUND_RESOURCE_GROUP}" \
        --subscription "${CURRENT_SUBSCRIPTION_ID}" \
        --client-id-prefix "${FOUND_INSTANCE_NAME}" \
        --hostname "${EVENTGRID_HOSTNAME}" \
        --port "${EVENTGRID_PORT}" \
        --auth-type SystemAssignedManagedIdentity \
        --only-show-errors >/dev/null; then
        echo -e "${GREEN}Created endpoint '${ENDPOINT_NAME}'.${RESET}"
        CREATED_COUNT=$((CREATED_COUNT + 1))
    else
        echo -e "${RED}Failed to create endpoint '${ENDPOINT_NAME}'.${RESET}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
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
echo -e "${GREEN}Updated: ${UPDATED_COUNT}${RESET}"
if [[ ${FAILED_COUNT} -gt 0 ]]; then
    echo -e "${RED}Failed: ${FAILED_COUNT}${RESET}"
    exit 1
fi

echo -e "${GREEN}Completed without errors.${RESET}"
