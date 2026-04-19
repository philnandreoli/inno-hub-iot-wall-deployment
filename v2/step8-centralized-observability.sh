#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Configure Centralized Observability - Step 8
# ============================================================================
# This script configures observability for Azure IoT Operations using
# pre-created centralized monitoring resources in Azure.
# It runs FROM THE HOST and connects to the VM via SSH.
#
# Prerequisites:
# - Step5 completed (IoT Operations deployed)
# - Central monitoring resources already exist:
#   - Azure Monitor Workspace
#   - Azure Managed Grafana
#   - Log Analytics Workspace
# - SSH connectivity to VM must be working
#
# Usage:
#   ./step8-centralized-observability.sh \
#     --service-principal-id <sp-id> \
#     --service-principal-secret <sp-secret> \
#     --subscription-id <subscription-id> \
#     --tenant-id <tenant-id> \
#     --location <location> \
#     --data-center <datacenter> \
#     --country <country> \
#     --monitor-workspace-id <azure-monitor-workspace-resource-id> \
#     --grafana-id <grafana-resource-id> \
#     --log-analytics-id <log-analytics-workspace-resource-id>
#
# Note:
# - Grafana dashboard import is handled centrally and is not part of this step.
# ============================================================================

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
    echo "  --country CODE                     2-letter country code (e.g., US, NL)"
    echo "  --monitor-workspace-id ID          Azure Monitor Workspace resource ID"
    echo "  --grafana-id ID                    Azure Managed Grafana resource ID"
    echo "  --log-analytics-id ID              Log Analytics Workspace resource ID"
    echo ""
    echo "Optional Options:"
    echo "  --ot-network-vm-ip IP              OT network IP for VM (default: 192.168.30.18)"
    echo "  --ssh-key-path PATH                Path to SSH private key (default: ~/.ssh/vm_id_rsa)"
    echo "  --instance-name NAME               IoT Operations instance (default: <dc>-<host>-vm-aio-instance)"
    echo "  --otel-collector-name NAME         OTel collector service name (default: aio-otel-collector)"
    echo "  --otel-grpc-port PORT              OTel gRPC port (default: 4317)"
    echo "  --otel-export-seconds SECONDS      Metrics export interval in seconds (default: 60)"
    echo "  -h, --help                         Display this help message"
    echo ""
    echo "Note: Arguments can be provided via command-line or environment variables."
    echo "      Command-line arguments take precedence over environment variables."
    exit 1
}

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
        --country)
            ARG_COUNTRY="$2"
            shift 2
            ;;
        --monitor-workspace-id)
            ARG_MONITOR_WORKSPACE_ID="$2"
            shift 2
            ;;
        --grafana-id)
            ARG_GRAFANA_ID="$2"
            shift 2
            ;;
        --log-analytics-id)
            ARG_LOG_ANALYTICS_ID="$2"
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
        --instance-name)
            ARG_INSTANCE_NAME="$2"
            shift 2
            ;;
        --otel-collector-name)
            ARG_OTEL_COLLECTOR_NAME="$2"
            shift 2
            ;;
        --otel-grpc-port)
            ARG_OTEL_GRPC_PORT="$2"
            shift 2
            ;;
        --otel-export-seconds)
            ARG_OTEL_EXPORT_SECONDS="$2"
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

export SERVICE_PRINCIPAL_ID="${ARG_SERVICE_PRINCIPAL_ID:-${SERVICE_PRINCIPAL_ID}}"
export SERVICE_PRINCIPAL_CLIENT_SECRET="${ARG_SERVICE_PRINCIPAL_SECRET:-${SERVICE_PRINCIPAL_CLIENT_SECRET}}"
export SUBSCRIPTION_ID="${ARG_SUBSCRIPTION_ID:-${SUBSCRIPTION_ID}}"
export TENANT_ID="${ARG_TENANT_ID:-${TENANT_ID}}"
export LOCATION="${ARG_LOCATION:-${LOCATION:-eastus2}}"
export DATA_CENTER="${ARG_DATA_CENTER:-${DATA_CENTER}}"
export COUNTRY="${ARG_COUNTRY:-${COUNTRY}}"

export CENTRAL_MONITOR_WORKSPACE_ID="${ARG_MONITOR_WORKSPACE_ID:-${CENTRAL_MONITOR_WORKSPACE_ID}}"
export CENTRAL_GRAFANA_ID="${ARG_GRAFANA_ID:-${CENTRAL_GRAFANA_ID}}"
export CENTRAL_LOG_ANALYTICS_ID="${ARG_LOG_ANALYTICS_ID:-${CENTRAL_LOG_ANALYTICS_ID}}"

export HOST_NAME=$(hostname -s)
export VM_NAME="${HOST_NAME}-vm"
export OT_NETWORK_VM_IP="${ARG_OT_NETWORK_VM_IP:-${OT_NETWORK_VM_IP:-192.168.30.18}}"
export SSH_KEY_PATH="${ARG_SSH_KEY_PATH:-${SSH_KEY_PATH:-$HOME/.ssh/vm_id_rsa}}"

export CLUSTER_NAME="${DATA_CENTER}-${VM_NAME}-k3s"
export NE_IOT_INSTANCE="${ARG_INSTANCE_NAME:-${NE_IOT_INSTANCE:-${DATA_CENTER}-${VM_NAME}-aio-instance}}"
export RESOURCE_GROUP="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"

export OTEL_COLLECTOR_NAME="${ARG_OTEL_COLLECTOR_NAME:-${OTEL_COLLECTOR_NAME:-aio-otel-collector}}"
export OTEL_GRPC_PORT="${ARG_OTEL_GRPC_PORT:-${OTEL_GRPC_PORT:-4317}}"
export OTEL_EXPORT_SECONDS="${ARG_OTEL_EXPORT_SECONDS:-${OTEL_EXPORT_SECONDS:-60}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OTEL_VALUES_FILE="${SCRIPT_DIR}/observability/otel-collector-values.yaml"
PROM_CONFIG_FILE="${SCRIPT_DIR}/observability/ama-metrics-prometheus-config.yaml"

CLUSTER_NAME=$(echo "${CLUSTER_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
NE_IOT_INSTANCE=$(echo "${NE_IOT_INSTANCE}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')

echo -e "${GREEN}======================================================================================================"
echo -e " Configure Centralized Observability - Configuration Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Host Name: ${HOST_NAME}${RESET}"
echo -e "${GREEN}VM Name: ${VM_NAME}${RESET}"
echo -e "${GREEN}VM IP Address: ${OT_NETWORK_VM_IP}${RESET}"
echo -e "${GREEN}Resource Group: ${RESOURCE_GROUP}${RESET}"
echo -e "${GREEN}Cluster Name: ${CLUSTER_NAME}${RESET}"
echo -e "${GREEN}IoT Instance: ${NE_IOT_INSTANCE}${RESET}"
echo -e "${GREEN}Azure Monitor Workspace ID: ${CENTRAL_MONITOR_WORKSPACE_ID}${RESET}"
echo -e "${GREEN}Grafana Resource ID: ${CENTRAL_GRAFANA_ID}${RESET}"
echo -e "${GREEN}Log Analytics Workspace ID: ${CENTRAL_LOG_ANALYTICS_ID}${RESET}"

if [ -z "$SERVICE_PRINCIPAL_ID" ] || [ -z "$SERVICE_PRINCIPAL_CLIENT_SECRET" ] || \
   [ -z "$SUBSCRIPTION_ID" ] || [ -z "$TENANT_ID" ] || \
   [ -z "$DATA_CENTER" ] || [ -z "$COUNTRY" ] || \
   [ -z "$CENTRAL_MONITOR_WORKSPACE_ID" ] || [ -z "$CENTRAL_GRAFANA_ID" ] || [ -z "$CENTRAL_LOG_ANALYTICS_ID" ]; then
    echo -e "${RED}ERROR: Required parameters are missing.${RESET}"
    echo -e "${RED}Please provide all required arguments or set environment variables.${RESET}"
    echo ""
    usage
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}ERROR: SSH key not found at ${SSH_KEY_PATH}${RESET}"
    exit 1
fi

if [ ! -f "$OTEL_VALUES_FILE" ]; then
    echo -e "${RED}ERROR: OTel values file not found at ${OTEL_VALUES_FILE}${RESET}"
    exit 1
fi

if [ ! -f "$PROM_CONFIG_FILE" ]; then
    echo -e "${RED}ERROR: Prometheus config file not found at ${PROM_CONFIG_FILE}${RESET}"
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

echo -e "${GREEN}======================================================================================================"
echo -e "Step 2: Logging into Azure on Host"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription "$SUBSCRIPTION_ID"
# Verify subscription is set correctly
echo "Verifying subscription context..."
SUBSCRIPTION_CHECK=$(az account show --query id -o tsv)
if [ -z "${SUBSCRIPTION_CHECK}" ]; then
    echo -e "${RED}ERROR: Failed to set subscription context${RESET}"
    exit 1
fi
echo -e "${GREEN}Active subscription: ${SUBSCRIPTION_CHECK}${RESET}"
# Use the verified subscription for all subsequent commands
export AZURE_SUBSCRIPTION_ID="${SUBSCRIPTION_CHECK}"

echo -e "${GREEN}====================================================================================================="
echo -e "Step 3: Enabling Azure Monitor Extensions on Arc Cluster"
echo -e "======================================================================================================${RESET}"
az extension add --upgrade --name k8s-extension
az extension add --upgrade --name connectedk8s

echo "=== DEBUG: Variable values ==="
echo "  CLUSTER_NAME:                ${CLUSTER_NAME}"
echo "  RESOURCE_GROUP:              ${RESOURCE_GROUP}"
echo "  AZURE_SUBSCRIPTION_ID:       ${AZURE_SUBSCRIPTION_ID}"
echo "  CENTRAL_MONITOR_WORKSPACE_ID:${CENTRAL_MONITOR_WORKSPACE_ID}"
echo "  CENTRAL_GRAFANA_ID:          ${CENTRAL_GRAFANA_ID}"
echo "  CENTRAL_LOG_ANALYTICS_ID:    ${CENTRAL_LOG_ANALYTICS_ID}"
echo ""

echo "Verifying Arc-enabled cluster exists..."
az connectedk8s show \
    --name "${CLUSTER_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --subscription "${AZURE_SUBSCRIPTION_ID}" \
    --query "{name:name, state:connectivityStatus}" -o table || {
    echo -e "${RED}ERROR: Arc cluster '${CLUSTER_NAME}' not found in resource group '${RESOURCE_GROUP}'${RESET}"
    exit 1
}

echo "Listing k8s-extension resources in resource group ${RESOURCE_GROUP}..."

EXISTING_METRICS_EXTENSION=$(az k8s-extension list \
    --cluster-name "${CLUSTER_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-type connectedClusters \
    --subscription "${AZURE_SUBSCRIPTION_ID}" \
    --query "[?name=='azuremonitor-metrics'].name" -o tsv 2>&1 || echo "")

if [ -z "${EXISTING_METRICS_EXTENSION}" ]; then
    echo "Creating azuremonitor-metrics extension..."
    az k8s-extension create \
        --name azuremonitor-metrics \
        --cluster-name "${CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --cluster-type connectedClusters \
        --subscription "${AZURE_SUBSCRIPTION_ID}" \
        --extension-type Microsoft.AzureMonitor.Containers.Metrics \
        --configuration-settings azure-monitor-workspace-resource-id="${CENTRAL_MONITOR_WORKSPACE_ID}" grafana-resource-id="${CENTRAL_GRAFANA_ID}" || {
        echo -e "${RED}Failed to create azuremonitor-metrics extension${RESET}"
        exit 1
    }
else
    echo -e "${YELLOW}azuremonitor-metrics extension already exists${RESET}"
fi

EXISTING_CONTAINERS_EXTENSION=$(az k8s-extension list \
    --cluster-name "${CLUSTER_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-type connectedClusters \
    --subscription "${AZURE_SUBSCRIPTION_ID}" \
    --query "[?name=='azuremonitor-containers'].name" -o tsv 2>&1 || echo "")

if [ -z "${EXISTING_CONTAINERS_EXTENSION}" ]; then
    echo "Creating azuremonitor-containers extension..."
    az k8s-extension create \
        --name azuremonitor-containers \
        --cluster-name "${CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --cluster-type connectedClusters \
        --subscription "${AZURE_SUBSCRIPTION_ID}" \
        --extension-type Microsoft.AzureMonitor.Containers \
        --configuration-settings logAnalyticsWorkspaceResourceID="${CENTRAL_LOG_ANALYTICS_ID}" || {
        echo -e "${RED}Failed to create azuremonitor-containers extension${RESET}"
        exit 1
    }
else
    echo -e "${YELLOW}azuremonitor-containers extension already exists${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 4: Creating VM Observability Script"
echo -e "======================================================================================================${RESET}"

cat > /tmp/configure-observability-vm.sh <<'EOFSCRIPT'
#!/bin/bash
set -e

export RED='\e[31m'
export GREEN='\e[32m'
export YELLOW='\e[33m'
export RESET='\e[0m'

SERVICE_PRINCIPAL_ID="__SERVICE_PRINCIPAL_ID__"
SERVICE_PRINCIPAL_CLIENT_SECRET="__SERVICE_PRINCIPAL_CLIENT_SECRET__"
SUBSCRIPTION_ID="__SUBSCRIPTION_ID__"
TENANT_ID="__TENANT_ID__"
RESOURCE_GROUP="__RESOURCE_GROUP__"
CLUSTER_NAME="__CLUSTER_NAME__"
NE_IOT_INSTANCE="__NE_IOT_INSTANCE__"
OTEL_COLLECTOR_NAME="__OTEL_COLLECTOR_NAME__"
OTEL_GRPC_PORT="__OTEL_GRPC_PORT__"
OTEL_EXPORT_SECONDS="__OTEL_EXPORT_SECONDS__"

echo -e "${GREEN}======================================================================================================"
echo -e "Logging into Azure on VM"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription "$SUBSCRIPTION_ID"
az extension add --upgrade --name azure-iot-ops --allow-preview

export KUBECONFIG=~/.kube/config

echo -e "${GREEN}======================================================================================================"
echo -e "Deploying OpenTelemetry Collector"
echo -e "======================================================================================================${RESET}"
kubectl get namespace azure-iot-operations >/dev/null 2>&1 || kubectl create namespace azure-iot-operations

if ! command -v helm >/dev/null 2>&1; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update

helm upgrade --install aio-observability open-telemetry/opentelemetry-collector \
    -f /tmp/otel-collector-values.yaml \
    --namespace azure-iot-operations

echo -e "${GREEN}======================================================================================================"
echo -e "Applying Prometheus Scrape Configuration"
echo -e "======================================================================================================${RESET}"
kubectl apply -f /tmp/ama-metrics-prometheus-config.yaml

echo -e "${GREEN}======================================================================================================"
echo -e "Updating IoT Operations Observability Settings"
echo -e "======================================================================================================${RESET}"
az iot ops upgrade \
    --resource-group "${RESOURCE_GROUP}" \
    -n "${NE_IOT_INSTANCE}" \
    --ops-config observability.metrics.openTelemetryCollectorAddress=${OTEL_COLLECTOR_NAME}.azure-iot-operations.svc.cluster.local:${OTEL_GRPC_PORT} \
    --ops-config observability.metrics.exportInternalSeconds=${OTEL_EXPORT_SECONDS} \
    --yes || {
    echo -e "${RED}Failed to update IoT Operations observability settings${RESET}"
    exit 1
}

echo -e "${GREEN}======================================================================================================"
echo -e "Verifying Observability Components"
echo -e "======================================================================================================${RESET}"
kubectl get pods -n azure-iot-operations | grep -i otel || {
    echo -e "${RED}OTel collector pod not found${RESET}"
    exit 1
}

kubectl get configmap ama-metrics-prometheus-config -n kube-system >/dev/null 2>&1 || {
    echo -e "${RED}Prometheus ConfigMap not found${RESET}"
    exit 1
}

echo -e "${GREEN}VM observability configuration complete${RESET}"
EOFSCRIPT

sed -i "s|__SERVICE_PRINCIPAL_ID__|${SERVICE_PRINCIPAL_ID}|g" /tmp/configure-observability-vm.sh
sed -i "s|__SERVICE_PRINCIPAL_CLIENT_SECRET__|${SERVICE_PRINCIPAL_CLIENT_SECRET}|g" /tmp/configure-observability-vm.sh
sed -i "s|__SUBSCRIPTION_ID__|${SUBSCRIPTION_ID}|g" /tmp/configure-observability-vm.sh
sed -i "s|__TENANT_ID__|${TENANT_ID}|g" /tmp/configure-observability-vm.sh
sed -i "s|__RESOURCE_GROUP__|${RESOURCE_GROUP}|g" /tmp/configure-observability-vm.sh
sed -i "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" /tmp/configure-observability-vm.sh
sed -i "s|__NE_IOT_INSTANCE__|${NE_IOT_INSTANCE}|g" /tmp/configure-observability-vm.sh
sed -i "s|__OTEL_COLLECTOR_NAME__|${OTEL_COLLECTOR_NAME}|g" /tmp/configure-observability-vm.sh
sed -i "s|__OTEL_GRPC_PORT__|${OTEL_GRPC_PORT}|g" /tmp/configure-observability-vm.sh
sed -i "s|__OTEL_EXPORT_SECONDS__|${OTEL_EXPORT_SECONDS}|g" /tmp/configure-observability-vm.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Step 5: Copying Observability Files to VM"
echo -e "======================================================================================================${RESET}"
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no /tmp/configure-observability-vm.sh ubuntu@${OT_NETWORK_VM_IP}:/tmp/configure-observability-vm.sh
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$OTEL_VALUES_FILE" ubuntu@${OT_NETWORK_VM_IP}:/tmp/otel-collector-values.yaml
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$PROM_CONFIG_FILE" ubuntu@${OT_NETWORK_VM_IP}:/tmp/ama-metrics-prometheus-config.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to copy files to VM${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 6: Executing Observability Configuration on VM"
echo -e "======================================================================================================${RESET}"
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${OT_NETWORK_VM_IP} "chmod +x /tmp/configure-observability-vm.sh && /tmp/configure-observability-vm.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to configure observability on VM${RESET}"
    exit 1
fi

rm -f /tmp/configure-observability-vm.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Centralized Observability Configuration Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Cluster Name: ${CLUSTER_NAME}${RESET}"
echo -e "${GREEN}IoT Instance: ${NE_IOT_INSTANCE}${RESET}"
echo -e "${GREEN}Metrics Workspace: ${CENTRAL_MONITOR_WORKSPACE_ID}${RESET}"
echo -e "${GREEN}Logs Workspace: ${CENTRAL_LOG_ANALYTICS_ID}${RESET}"
