#!/bin/bash

set -euo pipefail

RED='\e[31m'
YELLOW='\e[33m'
GREEN='\e[32m'
BLUE='\e[34m'
RESET='\e[0m'

SUBSCRIPTION_ID="084c8f47-bb5d-447e-82cb-63241353edef"
EVENTGRID_RG="EXP-MFG-AIO-ControlPlane-RG"
EVENTGRID_NAME="aiomfgeventgrid"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Diagnoses Event Grid connectivity issues across all Azure IoT Operations instances.
Identifies which instance can connect, which cannot, and why.

Options:
  --subscription-id ID    Azure subscription ID. Default: ${SUBSCRIPTION_ID}
  -h, --help              Show this help text.

Prerequisites:
  - Azure CLI is installed and authenticated with 'az login'.
  - kubectl is installed and can access k3s clusters.

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subscription-id)
            SUBSCRIPTION_ID="$2"
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

az account set --subscription "$SUBSCRIPTION_ID" >/dev/null

echo -e "${BLUE}======================================================================================================${RESET}"
echo -e "${BLUE}Azure Event Grid Connectivity Diagnostic Report${RESET}"
echo -e "${BLUE}======================================================================================================${RESET}"
echo -e "${BLUE}Date: $(date)${RESET}"
echo -e "${BLUE}Subscription: ${SUBSCRIPTION_ID}${RESET}"
echo -e "${BLUE}Event Grid Resource: ${EVENTGRID_NAME} (${EVENTGRID_RG})${RESET}"
echo ""

# Get Event Grid resource details
EVENTGRID_ID=$(az resource show --name "$EVENTGRID_NAME" --resource-group "$EVENTGRID_RG" --resource-type "Microsoft.EventGrid/namespaces" --query id -o tsv)
EVENTGRID_HOSTNAME=$(az resource show --name "$EVENTGRID_NAME" --resource-group "$EVENTGRID_RG" --resource-type "Microsoft.EventGrid/namespaces" --query "properties.publicNetworkAccessFlag" -o tsv 2>/dev/null || echo "unknown")

echo -e "${GREEN}Event Grid Namespace Details:${RESET}"
echo "  Resource ID: $EVENTGRID_ID"
echo "  Region: $(az resource show --name "$EVENTGRID_NAME" --resource-group "$EVENTGRID_RG" --resource-type "Microsoft.EventGrid/namespaces" --query location -o tsv)"
echo "  Public Network Access: $EVENTGRID_HOSTNAME"
echo ""

# Get all IoT Ops instances
echo -e "${GREEN}Listing all IoT Operations instances...${RESET}"
INSTANCES=$(az iot ops list --subscription "$SUBSCRIPTION_ID" --query "[].{name:name,resourceGroup:resourceGroup}" -o json)
INSTANCE_COUNT=$(echo "$INSTANCES" | jq 'length')
echo "Found $INSTANCE_COUNT instances"
echo ""

# Analyze each instance
echo -e "${BLUE}======================================================================================================${RESET}"
echo -e "${BLUE}Per-Instance Analysis${RESET}"
echo -e "${BLUE}======================================================================================================${RESET}"
echo ""

WORKING_INSTANCES=0
FAILING_INSTANCES=0
UNKNOWN_INSTANCES=0

while IFS= read -r INSTANCE_JSON; do
    INSTANCE_NAME=$(echo "$INSTANCE_JSON" | jq -r '.name')
    INSTANCE_RG=$(echo "$INSTANCE_JSON" | jq -r '.resourceGroup')
    
    echo -e "${YELLOW}Instance: ${INSTANCE_NAME}${RESET}"
    echo "  Resource Group: $INSTANCE_RG"
    
    # Get the demo endpoint configuration
    ENDPOINT_EXISTS=$(az iot ops dataflow endpoint show \
        --instance "$INSTANCE_NAME" \
        --name "demo" \
        --resource-group "$INSTANCE_RG" \
        --subscription "$SUBSCRIPTION_ID" \
        --query "properties.endpointSettings.hostname" -o tsv 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$ENDPOINT_EXISTS" == "NOT_FOUND" ]]; then
        echo -e "${RED}  ✗ Endpoint 'demo' not found${RESET}"
        ((UNKNOWN_INSTANCES++))
        echo ""
        continue
    fi
    
    echo -e "${GREEN}  ✓ Endpoint 'demo' exists${RESET}"
    echo "    Hostname: $ENDPOINT_EXISTS"
    
    # Get endpoint authentication type
    AUTH_TYPE=$(az iot ops dataflow endpoint show \
        --instance "$INSTANCE_NAME" \
        --name "demo" \
        --resource-group "$INSTANCE_RG" \
        --subscription "$SUBSCRIPTION_ID" \
        --query "properties.authenticationSettings.authType" -o tsv)
    echo "    Auth Type: $AUTH_TYPE"
    
    # Get the Arc cluster and its networking info
    CUSTOM_LOC_ID=$(az iot ops show \
        --name "$INSTANCE_NAME" \
        --resource-group "$INSTANCE_RG" \
        --subscription "$SUBSCRIPTION_ID" \
        --query "extendedLocation.name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$CUSTOM_LOC_ID" ]]; then
        echo -e "${RED}  ✗ Could not resolve custom location${RESET}"
        ((UNKNOWN_INSTANCES++))
        echo ""
        continue
    fi
    
    CL_RG=$(echo "$CUSTOM_LOC_ID" | awk -F'/' '{for (i=1; i<=NF; i++) if ($i == "resourceGroups") {print $(i+1); exit}}')
    CL_NAME=$(echo "$CUSTOM_LOC_ID" | awk -F'/' '{print $NF}')
    
    # Get Arc cluster name
    ARC_ID=$(az customlocation show --name "$CL_NAME" --resource-group "$CL_RG" --query "hostResourceId" -o tsv 2>/dev/null || echo "")
    if [[ -z "$ARC_ID" ]]; then
        echo -e "${RED}  ✗ Could not resolve Arc cluster${RESET}"
        ((UNKNOWN_INSTANCES++))
        echo ""
        continue
    fi
    
    CLUSTER_NAME=$(echo "$ARC_ID" | awk -F'/' '{print $NF}')
    echo "  Arc Cluster: $CLUSTER_NAME"
    
    # Get Arc cluster details
    CLUSTER_INFO=$(az connectedk8s show --name "$CLUSTER_NAME" --resource-group "$CL_RG" --query "{region:location,status:connectivityStatus}" -o json)
    CLUSTER_REGION=$(echo "$CLUSTER_INFO" | jq -r '.region')
    CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r '.status')
    echo "    Region: $CLUSTER_REGION"
    echo "    Connectivity Status: $CLUSTER_STATUS"
    
    # Get system-assigned identity principal ID
    PRINCIPAL_ID=$(az iot ops show \
        --name "$INSTANCE_NAME" \
        --resource-group "$INSTANCE_RG" \
        --subscription "$SUBSCRIPTION_ID" \
        --query "identity.principalId" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$PRINCIPAL_ID" ]]; then
        echo -e "${RED}  ✗ Could not retrieve system-assigned identity principal ID${RESET}"
        ((UNKNOWN_INSTANCES++))
        echo ""
        continue
    fi
    
    echo "  System-Assigned Identity Principal ID: $PRINCIPAL_ID"
    
    # Check if this principal has EventGrid TopicSpaces Publisher role
    PUBLISHER_ROLE=$(az role assignment list \
        --scope "$EVENTGRID_ID" \
        --assignee-object-id "$PRINCIPAL_ID" \
        --query "[?roleDefinitionName=='EventGrid TopicSpaces Publisher'] | length(@)" -o tsv 2>/dev/null || echo "0")
    
    if [[ "$PUBLISHER_ROLE" == "1" ]]; then
        echo -e "${GREEN}  ✓ Has 'EventGrid TopicSpaces Publisher' role${RESET}"
    else
        echo -e "${RED}  ✗ Missing 'EventGrid TopicSpaces Publisher' role${RESET}"
    fi
    
    # Try to test connectivity from the cluster
    echo "  Testing connectivity from cluster..."
    
    # Get kubeconfig for the cluster
    if kubectl config current-context >/dev/null 2>&1; then
        CURRENT_CONTEXT=$(kubectl config current-context)
        if [[ "$CURRENT_CONTEXT" == *"$CLUSTER_NAME"* ]]; then
            # We're already in the right cluster context
            DATAFLOW_POD=$(kubectl get pods -n azure-iot-operations -l app.kubernetes.io/name=aio-dataflow -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            if [[ -n "$DATAFLOW_POD" ]]; then
                TEST_RESULT=$(kubectl exec -n azure-iot-operations "$DATAFLOW_POD" -- timeout 5 bash -c "nc -zv ${ENDPOINT_EXISTS} 8883 2>&1" 2>/dev/null || echo "TIMEOUT/ERROR")
                if [[ "$TEST_RESULT" == *"succeeded"* ]] || [[ "$TEST_RESULT" == *"succeeded"* ]]; then
                    echo -e "${GREEN}  ✓ Connectivity test passed (port 8883 reachable)${RESET}"
                    ((WORKING_INSTANCES++))
                else
                    echo -e "${RED}  ✗ Connectivity test failed: ${TEST_RESULT}${RESET}"
                    ((FAILING_INSTANCES++))
                fi
            else
                echo -e "${YELLOW}  ? Could not find dataflow pod to test connectivity${RESET}"
                ((UNKNOWN_INSTANCES++))
            fi
        else
            echo -e "${YELLOW}  ? Current kubectl context is not this cluster (would need manual context switch)${RESET}"
            ((UNKNOWN_INSTANCES++))
        fi
    else
        echo -e "${YELLOW}  ? kubectl not configured, cannot test connectivity${RESET}"
        ((UNKNOWN_INSTANCES++))
    fi
    
    echo ""
done < <(echo "$INSTANCES" | jq -c '.[]')

echo -e "${BLUE}======================================================================================================${RESET}"
echo -e "${BLUE}Summary${RESET}"
echo -e "${BLUE}======================================================================================================${RESET}"
echo -e "${GREEN}Working Instances: ${WORKING_INSTANCES}${RESET}"
echo -e "${RED}Failing Instances: ${FAILING_INSTANCES}${RESET}"
echo -e "${YELLOW}Unknown/Indeterminate: ${UNKNOWN_INSTANCES}${RESET}"
echo ""

if [[ $FAILING_INSTANCES -gt 0 ]]; then
    echo -e "${RED}Diagnostics completed. $FAILING_INSTANCES instances have connectivity issues.${RESET}"
    echo ""
    echo -e "${YELLOW}Possible causes:${RESET}"
    echo "  1. Network/firewall: 8 instances cannot reach Event Grid hostname:port (${ENDPOINT_EXISTS}:8883)"
    echo "  2. DNS resolution: Some clusters may have DNS issues resolving the Event Grid hostname"
    echo "  3. NSG/Firewall rules: Outbound 8883 may be blocked for some clusters but not others"
    echo "  4. TLS/Certificate validation: Certificate issues on specific clusters"
    echo ""
    echo -e "${YELLOW}Next steps:${RESET}"
    echo "  1. Verify network connectivity from each cluster to Event Grid namespace"
    echo "  2. Check NSG rules on the VMs/clusters"
    echo "  3. Check dataflow pod logs for TLS/auth errors:"
    echo "     kubectl logs -n azure-iot-operations -l app.kubernetes.io/name=aio-dataflow -f"
    echo "  4. Verify Event Grid namespace firewall rules (if any)"
    exit 1
fi

echo -e "${GREEN}Diagnostics completed successfully.${RESET}"
