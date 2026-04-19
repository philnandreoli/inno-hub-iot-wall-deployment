#!/bin/bash

set -euo pipefail

RED='\e[31m'
YELLOW='\e[33m'
GREEN='\e[32m'
RESET='\e[0m'

PROFILE_NAME="command-and-control"
PROFILE_INSTANCES=1
SUBSCRIPTION_ID=""
INSTANCE_NAME=""
RESOURCE_GROUP=""

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Creates the '${PROFILE_NAME}' Azure IoT Operations dataflow profile with
${PROFILE_INSTANCES} profile instance on Azure IoT Operations deployments in a
single subscription. If the profile already exists on an instance, it is skipped.

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
    dataflow profiles in the target subscription.

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
echo -e "${GREEN}Azure IoT Operations Dataflow Profile Bootstrap${RESET}"
echo -e "${GREEN}======================================================================================================${RESET}"
echo -e "${GREEN}Subscription: ${CURRENT_SUBSCRIPTION_NAME} (${CURRENT_SUBSCRIPTION_ID})${RESET}"
echo -e "${GREEN}Profile Name: ${PROFILE_NAME}${RESET}"
echo -e "${GREEN}Profile Instances: ${PROFILE_INSTANCES}${RESET}"
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

    if az iot ops dataflow profile show \
        --instance "${FOUND_INSTANCE_NAME}" \
        --name "${PROFILE_NAME}" \
        --resource-group "${FOUND_RESOURCE_GROUP}" \
        --subscription "${CURRENT_SUBSCRIPTION_ID}" \
        --only-show-errors >/dev/null 2>&1; then
        echo -e "${YELLOW}Profile '${PROFILE_NAME}' already exists. Skipping.${RESET}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    if az iot ops dataflow profile create \
        --instance "${FOUND_INSTANCE_NAME}" \
        --name "${PROFILE_NAME}" \
        --resource-group "${FOUND_RESOURCE_GROUP}" \
        --subscription "${CURRENT_SUBSCRIPTION_ID}" \
        --profile-instances "${PROFILE_INSTANCES}" \
        --only-show-errors >/dev/null; then
        echo -e "${GREEN}Created profile '${PROFILE_NAME}'.${RESET}"
        CREATED_COUNT=$((CREATED_COUNT + 1))
    else
        echo -e "${RED}Failed to create profile '${PROFILE_NAME}'.${RESET}"
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
echo -e "${YELLOW}Skipped: ${SKIPPED_COUNT}${RESET}"
if [[ ${FAILED_COUNT} -gt 0 ]]; then
    echo -e "${RED}Failed: ${FAILED_COUNT}${RESET}"
    exit 1
fi

echo -e "${GREEN}Completed without errors.${RESET}"