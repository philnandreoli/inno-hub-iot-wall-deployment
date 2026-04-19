#!/bin/bash

set -euo pipefail

RED='\e[31m'
YELLOW='\e[33m'
GREEN='\e[32m'
BLUE='\e[34m'
RESET='\e[0m'

SUBSCRIPTION_ID="084c8f47-bb5d-447e-82cb-63241353edef"
WORKING_INSTANCE="chi-hjw4894-vm-aio-instance"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Compares the working instance '${WORKING_INSTANCE}' with all other instances
to identify configuration differences that explain the connectivity issue.

Options:
  --subscription-id ID    Azure subscription ID. Default: ${SUBSCRIPTION_ID}
  --working-instance NAME  The working instance name. Default: ${WORKING_INSTANCE}
  -h, --help              Show this help text.

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --working-instance)
            WORKING_INSTANCE="$2"
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
echo -e "${BLUE}Event Grid Connectivity Root Cause Analysis${RESET}"
echo -e "${BLUE}Comparing: ${GREEN}${WORKING_INSTANCE} (WORKING)${BLUE} vs. Other Instances (FAILING)${RESET}"
echo -e "${BLUE}======================================================================================================${RESET}"
echo ""

# Get working instance details
echo -e "${GREEN}Retrieving working instance details...${RESET}"
WORKING_INST_JSON=$(az iot ops list --subscription "$SUBSCRIPTION_ID" --query "[?name=='${WORKING_INSTANCE}']" -o json)
if [[ $(echo "$WORKING_INST_JSON" | jq 'length') -eq 0 ]]; then
    echo -e "${RED}ERROR: Working instance '${WORKING_INSTANCE}' not found${RESET}"
    exit 1
fi

WORKING_RG=$(echo "$WORKING_INST_JSON" | jq -r '.[0].resourceGroup')
echo "  Name: $WORKING_INSTANCE"
echo "  Resource Group: $WORKING_RG"
echo ""

# Get working instance's Arc cluster details
WORKING_CUSTOM_LOC=$(az iot ops show --name "$WORKING_INSTANCE" --resource-group "$WORKING_RG" --subscription "$SUBSCRIPTION_ID" --query "extendedLocation.name" -o tsv)
WORKING_CL_RG=$(echo "$WORKING_CUSTOM_LOC" | awk -F'/' '{for (i=1; i<=NF; i++) if ($i == "resourceGroups") {print $(i+1); exit}}')
WORKING_CL_NAME=$(echo "$WORKING_CUSTOM_LOC" | awk -F'/' '{print $NF}')
WORKING_ARC_ID=$(az customlocation show --name "$WORKING_CL_NAME" --resource-group "$WORKING_CL_RG" --query "hostResourceId" -o tsv)
WORKING_CLUSTER=$(echo "$WORKING_ARC_ID" | awk -F'/' '{print $NF}')
WORKING_CLUSTER_RG=$(echo "$WORKING_ARC_ID" | awk -F'/' '{for (i=1; i<=NF; i++) if ($i == "resourceGroups") {print $(i+1); exit}}')

echo -e "${GREEN}Working Instance Arc Cluster:${RESET}"
echo "  Cluster Name: $WORKING_CLUSTER"
echo "  Resource Group: $WORKING_CLUSTER_RG"

WORKING_CLUSTER_INFO=$(az connectedk8s show --name "$WORKING_CLUSTER" --resource-group "$WORKING_CLUSTER_RG" --query "{location:location,tags:tags,agentVersion:agentVersion,distribution:distribution,infrastructure:infrastructure,privateLinkScopeResourceId:privateLinkScopeResourceId}" -o json)
WORKING_LOCATION=$(echo "$WORKING_CLUSTER_INFO" | jq -r '.location')
WORKING_TAGS=$(echo "$WORKING_CLUSTER_INFO" | jq -r '.tags | to_entries | map("\(.key)=\(.value)") | join(", ")')
WORKING_AGENT_VERSION=$(echo "$WORKING_CLUSTER_INFO" | jq -r '.agentVersion // "unknown"')
WORKING_DISTRO=$(echo "$WORKING_CLUSTER_INFO" | jq -r '.distribution // "unknown"')
WORKING_INFRA=$(echo "$WORKING_CLUSTER_INFO" | jq -r '.infrastructure // "unknown"')
WORKING_PLS=$(echo "$WORKING_CLUSTER_INFO" | jq -r '.privateLinkScopeResourceId // "none"')

echo "  Location: $WORKING_LOCATION"
echo "  Agent Version: $WORKING_AGENT_VERSION"
echo "  Distribution: $WORKING_DISTRO"
echo "  Infrastructure: $WORKING_INFRA"
echo "  Private Link Scope: $WORKING_PLS"
echo "  Tags: $WORKING_TAGS"

# Get VM details for working instance
WORKING_VM_NAME="$(echo $WORKING_INSTANCE | sed 's/-aio-instance//')"
WORKING_VM=$(az vm list --subscription "$SUBSCRIPTION_ID" --query "[?name=='${WORKING_VM_NAME}']" -o json)
if [[ $(echo "$WORKING_VM" | jq 'length') -gt 0 ]]; then
    WORKING_VM_RG=$(echo "$WORKING_VM" | jq -r '.[0].resourceGroup')
    WORKING_VM_INFO=$(az vm show --name "$WORKING_VM_NAME" --resource-group "$WORKING_VM_RG" --query "{vmSize:hardwareProfile.vmSize,zones:zones,networkProfile:networkProfile.networkInterfaces[0].id}" -o json)
    WORKING_VM_SIZE=$(echo "$WORKING_VM_INFO" | jq -r '.vmSize')
    WORKING_VM_ZONES=$(echo "$WORKING_VM_INFO" | jq -r '.zones | join(",") // "no-zones"')
    WORKING_NIC_ID=$(echo "$WORKING_VM_INFO" | jq -r '.networkProfile')
    echo "  VM Size: $WORKING_VM_SIZE"
    echo "  Availability Zones: $WORKING_VM_ZONES"
    
    # Get networking details
    NIC_NAME=$(echo "$WORKING_NIC_ID" | awk -F'/' '{print $NF}')
    NIC_RG=$(echo "$WORKING_NIC_ID" | awk -F'/' '{for (i=1; i<=NF; i++) if ($i == "resourceGroups") {print $(i+1); exit}}')
    WORKING_NIC_INFO=$(az network nic show --name "$NIC_NAME" --resource-group "$NIC_RG" --query "{vnet:ipConfigurations[0].subnet.id,nsgId:networkSecurityGroup.id}" -o json)
    WORKING_VNET=$(echo "$WORKING_NIC_INFO" | jq -r '.vnet')
    WORKING_NSG=$(echo "$WORKING_NIC_INFO" | jq -r '.nsgId')
    echo "  VNET: $(echo $WORKING_VNET | awk -F'/' '{print $(NF-2)"/"$NF}')"
    if [[ "$WORKING_NSG" != "null" ]]; then
        NSG_NAME=$(echo "$WORKING_NSG" | awk -F'/' '{print $NF}')
        echo "  NSG: $NSG_NAME"
    fi
fi
echo ""

# Now compare with all other instances
echo -e "${BLUE}======================================================================================================${RESET}"
echo -e "${BLUE}Comparison with Other Instances${RESET}"
echo -e "${BLUE}======================================================================================================${RESET}"
echo ""

DIFF_COUNT=0
INSTANCES=$(az iot ops list --subscription "$SUBSCRIPTION_ID" --query "[].{name:name,resourceGroup:resourceGroup}" -o json)

while IFS= read -r INSTANCE_JSON; do
    INSTANCE_NAME=$(echo "$INSTANCE_JSON" | jq -r '.name')
    INSTANCE_RG=$(echo "$INSTANCE_JSON" | jq -r '.resourceGroup')
    
    # Skip the working instance
    if [[ "$INSTANCE_NAME" == "$WORKING_INSTANCE" ]]; then
        continue
    fi
    
    echo -e "${YELLOW}Instance: ${INSTANCE_NAME}${RESET}"
    
    # Get Arc cluster details
    CUSTOM_LOC=$(az iot ops show --name "$INSTANCE_NAME" --resource-group "$INSTANCE_RG" --subscription "$SUBSCRIPTION_ID" --query "extendedLocation.name" -o tsv 2>/dev/null || echo "")
    if [[ -z "$CUSTOM_LOC" ]]; then
        echo "  ✗ Could not retrieve custom location"
        echo ""
        continue
    fi
    
    CL_RG=$(echo "$CUSTOM_LOC" | awk -F'/' '{for (i=1; i<=NF; i++) if ($i == "resourceGroups") {print $(i+1); exit}}')
    CL_NAME=$(echo "$CUSTOM_LOC" | awk -F'/' '{print $NF}')
    ARC_ID=$(az customlocation show --name "$CL_NAME" --resource-group "$CL_RG" --query "hostResourceId" -o tsv 2>/dev/null || echo "")
    if [[ -z "$ARC_ID" ]]; then
        echo "  ✗ Could not retrieve Arc cluster"
        echo ""
        continue
    fi
    
    CLUSTER=$(echo "$ARC_ID" | awk -F'/' '{print $NF}')
    CLUSTER_RG=$(echo "$ARC_ID" | awk -F'/' '{for (i=1; i<=NF; i++) if ($i == "resourceGroups") {print $(i+1); exit}}')
    
    CLUSTER_INFO=$(az connectedk8s show --name "$CLUSTER" --resource-group "$CLUSTER_RG" --query "{location:location,tags:tags,agentVersion:agentVersion,distribution:distribution,infrastructure:infrastructure,privateLinkScopeResourceId:privateLinkScopeResourceId}" -o json)
    LOCATION=$(echo "$CLUSTER_INFO" | jq -r '.location')
    TAGS=$(echo "$CLUSTER_INFO" | jq -r '.tags | to_entries | map("\(.key)=\(.value)") | join(", ")')
    AGENT_VERSION=$(echo "$CLUSTER_INFO" | jq -r '.agentVersion // "unknown"')
    DISTRO=$(echo "$CLUSTER_INFO" | jq -r '.distribution // "unknown"')
    INFRA=$(echo "$CLUSTER_INFO" | jq -r '.infrastructure // "unknown"')
    PLS=$(echo "$CLUSTER_INFO" | jq -r '.privateLinkScopeResourceId // "none"')
    
    echo "  Cluster: $CLUSTER"
    
    # Compare each field
    if [[ "$LOCATION" != "$WORKING_LOCATION" ]]; then
        echo -e "    ${RED}✗ Location: $LOCATION (working: $WORKING_LOCATION)${RESET}"
        ((DIFF_COUNT++))
    else
        echo -e "    ${GREEN}✓ Location: $LOCATION${RESET}"
    fi
    
    if [[ "$AGENT_VERSION" != "$WORKING_AGENT_VERSION" ]]; then
        echo -e "    ${RED}✗ Agent Version: $AGENT_VERSION (working: $WORKING_AGENT_VERSION)${RESET}"
        ((DIFF_COUNT++))
    else
        echo -e "    ${GREEN}✓ Agent Version: $AGENT_VERSION${RESET}"
    fi
    
    if [[ "$DISTRO" != "$WORKING_DISTRO" ]]; then
        echo -e "    ${RED}✗ Distribution: $DISTRO (working: $WORKING_DISTRO)${RESET}"
        ((DIFF_COUNT++))
    else
        echo -e "    ${GREEN}✓ Distribution: $DISTRO${RESET}"
    fi
    
    if [[ "$INFRA" != "$WORKING_INFRA" ]]; then
        echo -e "    ${RED}✗ Infrastructure: $INFRA (working: $WORKING_INFRA)${RESET}"
        ((DIFF_COUNT++))
    else
        echo -e "    ${GREEN}✓ Infrastructure: $INFRA${RESET}"
    fi
    
    # Check Private Link configuration difference
    if [[ "$PLS" != "$WORKING_PLS" ]]; then
        echo -e "    ${RED}✗ Private Link Scope: $PLS (working: $WORKING_PLS)${RESET}"
        ((DIFF_COUNT++))
    else
        echo -e "    ${GREEN}✓ Private Link Scope: $PLS${RESET}"
    fi
    
    # Check VM networking if we can
    VM_NAME="$(echo $INSTANCE_NAME | sed 's/-aio-instance//')"
    VM=$(az vm list --subscription "$SUBSCRIPTION_ID" --query "[?name=='${VM_NAME}']" -o json 2>/dev/null || echo "[]")
    if [[ $(echo "$VM" | jq 'length') -gt 0 ]]; then
        VM_RG=$(echo "$VM" | jq -r '.[0].resourceGroup')
        VM_INFO=$(az vm show --name "$VM_NAME" --resource-group "$VM_RG" --query "{vmSize:hardwareProfile.vmSize,zones:zones}" -o json)
        VM_SIZE=$(echo "$VM_INFO" | jq -r '.vmSize')
        VM_ZONES=$(echo "$VM_INFO" | jq -r '.zones | join(",") // "no-zones"')
        
        if [[ "$VM_SIZE" != "$WORKING_VM_SIZE" ]]; then
            echo -e "    ${RED}✗ VM Size: $VM_SIZE (working: $WORKING_VM_SIZE)${RESET}"
        else
            echo -e "    ${GREEN}✓ VM Size: $VM_SIZE${RESET}"
        fi
        
        if [[ "$VM_ZONES" != "$WORKING_VM_ZONES" ]]; then
            echo -e "    ${YELLOW}⚠ Availability Zones: $VM_ZONES (working: $WORKING_VM_ZONES)${RESET}"
        else
            echo -e "    ${GREEN}✓ Availability Zones: $VM_ZONES${RESET}"
        fi
    fi
    
    echo ""
done < <(echo "$INSTANCES" | jq -c '.[]')

echo -e "${BLUE}======================================================================================================${RESET}"
echo -e "${BLUE}Analysis Summary${RESET}"
echo -e "${BLUE}======================================================================================================${RESET}"
echo ""

if [[ $DIFF_COUNT -eq 0 ]]; then
    echo -e "${YELLOW}No major configuration differences found in Arc cluster setup.${RESET}"
    echo ""
    echo -e "${YELLOW}Root cause is likely:${RESET}"
    echo "  1. NETWORK FIREWALL/NSG: Check if 8 VMs have outbound rules blocking port 8883"
    echo "  2. AZURE FIREWALL: If behind Azure Firewall, may be blocking Event Grid hostname"
    echo "  3. ROUTE TABLES: Asymmetric routing or UDR issues"
    echo "  4. DNS: 8 instances may not be able to resolve Event Grid hostname"
    echo "  5. PRIVATE ENDPOINTS: Event Grid may be using private endpoint in some regions"
    echo ""
    echo -e "${GREEN}Recommended immediate checks:${RESET}"
    echo "  1. ssh to each VM and run: nslookup aiomfgeventgrid.eastus2-1.ts.eventgrid.azure.net"
    echo "  2. Run: telnet aiomfgeventgrid.eastus2-1.ts.eventgrid.azure.net 8883"
    echo "  3. Check NSG outbound rules for each VM's NIC"
    echo "  4. Check Azure Firewall rules if one is in use"
    echo "  5. Run from failing instance pod: curl -v telemetry.eventgrid.azure.com"
    echo ""
    echo -e "${GREEN}Check dataflow pod logs on a failing instance:${RESET}"
    echo "  kubectl logs -n azure-iot-operations -l app.kubernetes.io/name=aio-dataflow --tail=100"
else
    echo -e "${GREEN}Found $DIFF_COUNT configuration differences${RESET}"
fi
