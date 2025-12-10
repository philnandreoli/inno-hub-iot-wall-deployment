#! /bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# Usage function
usage() {
    cat <<EOF
${YELLOW}Usage: $0 --sp-id <ID> --sp-secret <SECRET> --subscription-id <ID> --tenant-id <ID> --location <LOC> --data-center <DC> --city <CITY> --state-region <STATE> --country <COUNTRY>${RESET}

${GREEN}Required Arguments:${RESET}
  --sp-id             : The Service Principal ID from the IoT-Wall-V2 secret in the MTC SHARED Vault
  --sp-secret         : The Service Principal Client Secret from the vault
  --subscription-id   : The Azure Subscription ID
  --tenant-id         : The Azure Tenant ID
  --location          : Azure Location (e.g., eastus2 for AMERICAS, northeurope for EMEA, southeastasia for APAC)
  --data-center       : Data Center Code (e.g., CHI for Chicago, STL for St. Louis, AMS for Amsterdam)
  --city              : City name (e.g., Chicago, St. Louis, Amsterdam)
  --state-region      : State or Region code (e.g., IL for Illinois, MO for Missouri)
  --country           : Two-letter country code (e.g., US, NL)

${YELLOW}Note: Resource group will be auto-created with naming convention: EXP-MFG-AIO-\${DATA_CENTER}-\${COUNTRY}-RG${RESET}

${GREEN}Example for AMERICAS (Chicago):${RESET}
  $0 --sp-id "sp-id-here" --sp-secret "sp-secret-here" --subscription-id "sub-id-here" --tenant-id "tenant-id-here" \\
     --location "eastus2" --data-center "CHI" --city "Chicago" --state-region "IL" --country "US"

${GREEN}Example for EMEA (Amsterdam):${RESET}
  $0 --sp-id "sp-id-here" --sp-secret "sp-secret-here" --subscription-id "sub-id-here" --tenant-id "tenant-id-here" \\
     --location "northeurope" --data-center "AMS" --city "Amsterdam" --state-region "NH" --country "NL"

${GREEN}Example for APAC (Singapore):${RESET}
  $0 --sp-id "sp-id-here" --sp-secret "sp-secret-here" --subscription-id "sub-id-here" --tenant-id "tenant-id-here" \\
     --location "southeastasia" --data-center "SIN" --city "Singapore" --state-region "SG" --country "SG"
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
        --city)
            CITY="$2"
            shift 2
            ;;
        --state-region)
            STATE_REGION="$2"
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
   [ -z "${TENANT_ID}" ] || [ -z "${LOCATION}" ] || \
   [ -z "${DATA_CENTER}" ] || [ -z "${CITY}" ] || [ -z "${STATE_REGION}" ] || [ -z "${COUNTRY}" ]; then
    echo -e "${RED}Error: Missing required arguments${RESET}"
    usage
fi

export SERVICE_PRINCIPAL_ID
export SERVICE_PRINCIPAL_CLIENT_SECRET
export SUBSCRIPTION_ID
export TENANT_ID
export LOCATION
export DATA_CENTER
export CITY
export STATE_REGION
export COUNTRY

# Dynamically create resource group name based on data center and country
export RESOURCE_GROUP="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"

# Set constant values
export AUTH_TYPE="principal"
export CLOUD="AzureCloud"
export INSTALL_K3S_VERSION="v1.34.1+k3s1"
export IOT_ID="a4e6246e-0a1b-48c6-8fd6-9b0631d78d05"

# Set the SERVICE_TAG to the hostname of the machine.   This is what will be registered in Azure Arc
export SERVICE_TAG=$(hostname -s)

export CLUSTER_NAME="${DATA_CENTER}-${SERVICE_TAG}-k3s"
export KEYVAULT_NAME="${DATA_CENTER}-${SERVICE_TAG}-kv"
export STORAGE_ACCOUNT_NAME="${DATA_CENTER}-${SERVICE_TAG}-sa"
export IOTOPS_CLUSTER_NAME="${DATA_CENTER}-${SERVICE_TAG}-aio-cluster"
export REGISTRY_NAME="${DATA_CENTER}-${SERVICE_TAG}-registry}"
export REGISTRY_NAMESPACE="${DATA_CENTER}-${SERVICE_TAG}-regnamespace"
export NE_IOT_INSTANCE="${DATA_CENTER}-${SERVICE_TAG}-aio-instance"
export NE_IOT_NAMESPACE="${DATA_CENTER}-${SERVICE_TAG}-aio-namespace"
export USER_ASSIGNED_MANAGED_IDENTITY="${DATA_CENTER}-${SERVICE_TAG}-uami"

# Convert to lowercase
NE_IOT_INSTANCE=$(echo "${NE_IOT_INSTANCE}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g'  )
NE_IOT_NAMESPACE=$(echo "${NE_IOT_NAMESPACE}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g'  )

CLUSTER_NAME=$(echo "${CLUSTER_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g'  )
KEYVAULT_NAME=$(echo "${KEYVAULT_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g'  )
USER_ASSIGNED_MANAGED_IDENTITY=$(echo "${USER_ASSIGNED_MANAGED_IDENTITY}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g'  )

# Storage and registry names must be lowercase, alphanumeric, and <= 24 chars
STORAGE_ACCOUNT_NAME=$(echo "${STORAGE_ACCOUNT_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)
REGISTRY_NAME=$(echo "${REGISTRY_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)
REGISTRY_NAMESPACE=$(echo "${REGISTRY_NAMESPACE}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)

echo -e "${GREEN}==========================================================================================="
echo -e " OUTPUTTING ALL THE ENVIRONMENTAL VARIABLES BEING USED FOR THE ONBOARDING SCRIPT"
echo -e "===========================================================================================${RESET}"
echo -e "${GREEN}SERVICE_PRINCIPAL_ID:${SERVICE_PRINCIPAL_ID}${RESET}"
echo -e "${GREEN}SUBSCRIPTION_ID:${SUBSCRIPTION_ID}${RESET}"
echo -e "${GREEN}RESOURCE_GROUP:${RESOURCE_GROUP}${RESET}"
echo -e "${GREEN}TENANT_ID:${TENANT_ID}${RESET}"
echo -e "${GREEN}LOCATION:${LOCATION}${RESET}"
echo -e "${GREEN}DATA_CENTER:${DATA_CENTER}${RESET}"
echo -e "${GREEN}CITY:${CITY}${RESET}"
echo -e "${GREEN}STATE_REGION:${STATE_REGION}${RESET}"
echo -e "${GREEN}COUNTRY:${COUNTRY}${RESET}"
echo -e "${GREEN}SERVICE_TAG:${SERVICE_TAG}${RESET}"
echo -e "${GREEN}CLUSTER_NAME:${CLUSTER_NAME}${RESET}"
echo -e "${GREEN}KEYVAULT_NAME:${KEYVAULT_NAME}${RESET}"
echo -e "${GREEN}STORAGE_ACCOUNT_NAME:${STORAGE_ACCOUNT_NAME}${RESET}"
echo -e "${GREEN}IOTOPS_CLUSTER_NAME:${IOTOPS_CLUSTER_NAME}${RESET}"
echo -e "${GREEN}REGISTRY_NAME:${REGISTRY_NAME}${RESET}"
echo -e "${GREEN}REGISTRY_NAMESPACE:${REGISTRY_NAMESPACE}${RESET}"
echo -e "${GREEN}NE_IOT_INSTANCE:${NE_IOT_INSTANCE}${RESET}"
echo -e "${GREEN}NE_IOT_NAMESPACE:${NE_IOT_NAMESPACE}${RESET}"
echo -e "${GREEN}USER_ASSIGNED_MANAGED_IDENTITY:${USER_ASSIGNED_MANAGED_IDENTITY}${RESET}"
echo -e "${GREEN}INSTALL_K3S_VERSION:${INSTALL_K3S_VERSION}${RESET}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 1........Installing Azure CLI"
echo -e "======================================================================================================${RESET}"
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az extension add --name connectedk8s
az extension add --name k8s-extension
az extension add --name azure-iot-ops
az extension add --name connectedmachine

echo -e "${GREEN}========================================================================================================="
echo -e "Step 2........Downloading and installing the Azure Connected Machine agent"
echo -e "=========================================================================================================${RESET}"
# Download the installation package
LINUX_INSTALL_SCRIPT="/tmp/install_linux_azcmagent.sh"
if [ -f "$LINUX_INSTALL_SCRIPT" ]; then rm -f "$LINUX_INSTALL_SCRIPT"; fi;
output=$(wget https://gbl.his.arc.azure.com/azcmagent-linux -O "$LINUX_INSTALL_SCRIPT" 2>&1);
if [ $? != 0 ]; then wget -qO- --method=PUT --body-data="{\"subscriptionId\":\"$SUBSCRIPTION_ID\",\"resourceGroup\":\"$RESOURCE_GROUP\",\"tenantId\":\"$TENANT_ID\",\"location\":\"$LOCATION\",\"correlationId\":\"$correlationId\",\"authType\":\"$AUTH_TYPE\",\"operation\":\"onboarding\",\"messageType\":\"DownloadScriptFailed\",\"message\":\"$output\"}" "https://gbl.his.arc.azure.com/log" &> /dev/null || true; fi;
echo "$output";

# Install the hybrid agent
bash "$LINUX_INSTALL_SCRIPT";
sleep 5;

echo -e "${GREEN}======================================================================================================"
echo -e " Step 2.2 Logging into Azure using Service Principal"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription $SUBSCRIPTION_ID

# Check if resource group exists
EXISTING_RG=$(az group show --name "${RESOURCE_GROUP}" --query "id" -o tsv 2>/dev/null || echo "")

if [ -z "${EXISTING_RG}" ]; then
    echo -e "${YELLOW}Creating resource group: ${RESOURCE_GROUP}${RESET}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags Environment=MTCDemo CreatedBy=NativeEdge Industry=MFG Partner=NA RGMonthlyCost=1000 Owner=philand@onemtcnet CreatedDate=$(date +%Y-%m-%d) LifeCycleCheck=$(date +%Y-%m-%d)
    

    az role assignment create --assignee "e47cc756-add5-4ae8-b684-10f6c82ee08e" --role "Contributor" --scope "/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${RESOURCE_GROUP}"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create resource group${RESET}"
        exit 1
    fi
    echo -e "${GREEN}Resource group created successfully${RESET}"
else
    echo -e "${YELLOW}Resource group already exists: ${RESOURCE_GROUP}${RESET}"
fi

# Run connect command
sudo azcmagent connect --service-principal-id $SERVICE_PRINCIPAL_ID --service-principal-secret $SERVICE_PRINCIPAL_CLIENT_SECRET --resource-group "$RESOURCE_GROUP" --tenant-id "$TENANT_ID" --location "$LOCATION" --subscription-id "$SUBSCRIPTION_ID" --cloud "$CLOUD" --tags "Datacenter=${DATA_CENTER},City=${CITY},StateOrDistrict=${STATE_REGION},CountryOrRegion=${COUNTRY},ServiceTag=${SERVICE_TAG},ArcSQLServerExtensionDeployment=Disabled";

echo -e "${GREEN}======================================================================================================="
echo -e "Step 2.1 Installing net-tools and AAD SSH Login Extension"
echo -e "=======================================================================================================${RESET}"
sudo apt install net-tools aadsshlogin -y



echo -e "${GREEN}======================================================================================================"
echo -e " Step 2.3........Create the default connectivity endpoint"
echo -e "======================================================================================================${RESET}"
az rest --method put \
  --uri https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.HybridCompute/machines/${SERVICE_TAG}/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15 --body '{"properties": {"type": "default"}}'

echo -e "${GREEN}======================================================================================================="
echo -e " Step 2.4........Verifying the connectivity endpoint status"
echo -e "=======================================================================================================${RESET}"
az rest --method get \
  --uri https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.HybridCompute/machines/${SERVICE_TAG}/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15

echo -e "${GREEN}======================================================================================================="
echo -e " Step 2.5........Enable SSH Functionality"
echo -e "======================================================================================================${RESET}"
az rest --method put \
  --uri https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.HybridCompute/machines/${SERVICE_TAG}/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15 --body "{\"properties\": {\"serviceName\": \"SSH\", \"port\": 22}}"

echo -e "======================================================================================================"
echo -e " Step 2.6 Install the Microsoft  Entra Login Extension"
echo -e "======================================================================================================"
az connectedmachine extension create --machine-name ${SERVICE_TAG} \
  --resource-group ${RESOURCE_GROUP} \
  --publisher Microsoft.Azure.ActiveDirectory \
  --name AADSSHLogin --type AADSSHLoginForLinux \
  --location ${LOCATION}


echo -e "${GREEN}======================================================================================================"
echo -e " Configuring the Ubuntu Server so that it meets our SFI Requirements"
echo -e "======================================================================================================${RESET}"

# Set the owner and group of /etc/cron.weekly to root and permissions to 0700
sudo chown root:root /etc/cron.weekly
sudo chmod 0700 /etc/cron.weekly

# Set the owner and group of /etc/ssh/sshd_config to root and set the permissions to 0600 or run '/opt/microsoft/omsagent/plugin/omsremediate -r sshd-config-file-permissions'
sudo chown root:root /etc/ssh/sshd_config
sudo chmod 600 /etc/ssh/sshd_config

# Set the owner and group of /etc/chron.monthly to root and permissions to 0700 or run '/opt/microsoft/omsagent/plugin/omsremediate -r fix-cron-file-perms
sudo chown root:root /etc/cron.monthly
sudo chmod 700 /etc/cron.monthly

# set the following parameters in /etc/sysctl.conf: 'net.ipv4.conf.all.send_redirects = 0' and 'net.ipv4.conf.default.send_redirects = 0'
sudo sed -i 's/^net\.ipv4\.conf\.all\.send_redirects.*/net.ipv4.conf.all.send_redirects = 0/' /etc/sysctl.conf
sudo sed -i 's/^net\.ipv4\.conf\.default\.send_redirects.*/net.ipv4.conf.default.send_redirects = 0/' /etc/sysctl.conf

sudo sysctl -w net.ipv4.conf.all.send_redirects=0
sudo sysctl -w net.ipv4.conf.default.send_redirects=0



echo -e "${GREEN}======================================================================================================"
echo -e "Step 3........Installing k3s"
echo -e "======================================================================================================${RESET}"
curl -sfL https://get.k3s.io | sh -


echo -e "${GREEN}======================================================================================================"
echo -e "Step 3.1........Configuring kubectl for k3s"
echo -e "======================================================================================================${RESET}"
mkdir ~/.kube
sudo KUBECONFIG=~/.kube/config:/etc/rancher/k3s/k3s.yaml kubectl config view --flatten > ~/.kube/merged
mv ~/.kube/merged ~/.kube/config
chmod  0600 ~/.kube/config
export KUBECONFIG=~/.kube/config
#switch to k3s context
kubectl config use-context default
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

echo -e "${GREEN}======================================================================================================"
echo -e "Step 3.2........Configuring system limits for k3s"
echo -e "======================================================================================================${RESET}"
echo fs.inotify.max_user_instances=8192 | sudo tee -a /etc/sysctl.conf
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
echo fs.file-max = 100000 | sudo tee -a /etc/sysctl.conf

sudo sysctl -p


echo -e "${GREEN}======================================================================================================"
echo -e "Step 4........Connecting k3s to Azure Arc"
echo -e "======================================================================================================"
az connectedk8s connect --name $CLUSTER_NAME \
  -l $LOCATION \
  --resource-group $RESOURCE_GROUP \
  --subscription $SUBSCRIPTION_ID \
  --enable-oidc-issuer --enable-workload-identity --disable-auto-upgrade

echo -e "${GREEN}========================================================================"
echo -e "Step 4.1.................Enabling IoT features ..."
echo -e "========================================================================${RESET}"
az connectedk8s enable-features -n "${CLUSTER_NAME}" \
  -g "${RESOURCE_GROUP}" \
  --custom-locations-oid "${IOT_ID}" \
  --features cluster-connect custom-locations

echo -e "${GREEN}========================================================================"
echo -e "Step 4.2..........................Updating K3s config.yaml ..."
echo -e "========================================================================${RESET}"
SERVICE_ACCOUNT_ISSUER=$(az connectedk8s show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" --query oidcIssuerProfile.issuerUrl --output tsv)
CONFIG_SNIPPET="kube-apiserver-arg:\n - service-account-issuer=${SERVICE_ACCOUNT_ISSUER}\n - service-account-max-token-expiration=24h"
echo -e "${CONFIG_SNIPPET}" | sudo tee -a /etc/rancher/k3s/config.yaml

echo -e "${GREEN}========================================================================="
echo -e "Step 4.3......................Restarting K3S to apply new config...."
echo -e "=========================================================================${RESET}"
sudo systemctl restart k3s

echo -e "${GREEN}======================================================================================================"
echo -e " Step 5........Creating User Assigned Managed Identity if it does not already exist"
echo -e "======================================================================================================${RESET}"
EXISTING_UAMI=$(az identity list --resource-group "${RESOURCE_GROUP}" --query "[?name=='${USER_ASSIGNED_MANAGED_IDENTITY}'].name" -o tsv)
if [ -z "${EXISTING_UAMI}" ]; then
  az identity create --resource-group  "${RESOURCE_GROUP}" \
     --name "${USER_ASSIGNED_MANAGED_IDENTITY}" \
     --location "${LOCATION}" || {
    echo -e "${RED}Failed to create User Assigned Managed Identity${RESET}"
    exit 1
  }
else
  echo -e "${YELLOW}User Assigned Managed Identity already exists: ${EXISTING_UAMI}${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 6........Creating key vault if it does not already exist and if one is deleted then we restore it"
echo -e "Key Vault Name: ${KEYVAULT_NAME}"
echo -e "======================================================================================================${RESET}"
DELETED_KEYVAULT=$(az keyvault list-deleted --query "[?name=='${KEYVAULT_NAME}'].name" -o tsv)
if [ ! -z "${DELETED_KEYVAULT}" ]; then
  echo -e "${YELLOW}A Key Vault with the name ${KEYVAULT_NAME} was found in deleted state. Restoring...${RESET}"
  az keyvault recover --name "${KEYVAULT_NAME}" --resource-group $RESOURCE_GROUP
else
  echo -e "${YELLOW}No deleted Key Vault found with the name ${KEYVAULT_NAME}.${RESET}"
fi

EXISTING_KEYVAULT=$(az keyvault list --query "[?name=='${KEYVAULT_NAME}'].name" -o tsv)
if [ -z "${EXISTING_KEYVAULT}" ]; then
  az keyvault create --enable-rbac-authorization true --name $KEYVAULT_NAME --resource-group "${RESOURCE_GROUP}" --location "${LOCATION}"
else
  echo -e "${YELLOW}Key Vault already exists.${RESET}"
fi


echo -e "${GREEN}========================================================================"
echo -e "Step 7......Createing Storage Account if it does not already exist"
echo -e "Storage Account Name: ${STORAGE_ACCOUNT_NAME}"
echo -e "========================================================================${RESET}"
EXISTING_STORAGE=$(az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --query "id" --output tsv 2>/dev/null || echo "")
if [ -z "${EXISTING_STORAGE}" ]; then
  echo -e "${YELLOW}Storage account does not exist. Creating...${RESET}"
  az storage account create --name "${STORAGE_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 --enable-hierarchical-namespace true --min-tls-version TLS1_2
else
  echo -e "${YELLOW}Storage account already exists: ${EXISTING_STORAGE}${RESET}"
fi

echo -e "${GREEN}Retreive the Storage Id that was just created or already exists${RESET}"
STORAGE_ID=$(az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --query "id" --output tsv)
echo -e "${GREEN}STORAGE_ID=${STORAGE_ID}${RESET}"



echo -e "${GREEN}==========================================================================="
echo -e "Step 8........Creating IoT Ops Schema Registry"
echo -e "===========================================================================${RESET}"
az iot ops schema registry create -n "${REGISTRY_NAME}" \
  -g "${RESOURCE_GROUP}" \
  --registry-namespace "${REGISTRY_NAMESPACE}" \
  --sa-resource-id "${STORAGE_ID}" \
  --location "${LOCATION}" || {
    echo -e "${RED}Failed to create IoT Ops Schema Registry${RESET}"
    exit 1
  }


az extension add --upgrade --name azure-iot-ops --allow-preview

echo -e "${GREEN}========================================================================="
echo -e "Step 9.....Creating IoT Ops Namespace"
echo -e "==========================================================================${RESET}"
az iot ops ns create -n $NE_IOT_NAMESPACE -g $RESOURCE_GROUP --location $LOCATION || {
    echo -e "${RED}Failed to create an IoT Ops Namespace${RESET}"
    exit 1
}

echo -e "${GREEN}==========================================================================="
echo -e "Step 10..................Fetching Schema Registry Resource ID...."
echo -e "===========================================================================${RESET}"
SR_RESOURCE_ID=$(az iot ops schema registry show --name "${REGISTRY_NAME}" --resource-group "${RESOURCE_GROUP}" --query id --output tsv 2>/dev/null || echo "")
if [ -z "${SR_RESOURCE_ID}" ]; then
  echo -e "${RED}Failed to fetch Schema Registry ID for ${REGISTRY_NAME} in ${RESOURCE_GROUP}${RESET}"
  exit 1
fi
echo -e "${GREEN}SR_RESOURCE_ID=${SR_RESOURCE_ID}${RESET}"

echo -e "${GREEN}========================================================================"
echo -e "Step 11.....Fetching Namespace Resource ID ..."
echo -e "========================================================================${RESET}"
NS_RESOURCE_ID=$(az iot ops ns show --name "${NE_IOT_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" --query id --output tsv 2>/dev/null || echo "")
if [ -z "${NS_RESOURCE_ID}" ]; then
  echo -e "${RED}Failed to fetch Namespace ID for ${NE_IOT_NAMESPACE} in ${RESOURCE_GROUP}${RESET}"
  exit 1
fi
echo -e "${GREEN}NS_RESOURCE_ID=${NS_RESOURCE_ID}${RESET}"

echo -e "${GREEN}==========================================================================="
echo -e "Step 12....Initiating the IoT Ops Cluster"
echo -e "==========================================================================="${RESET}
az iot ops init -g "${RESOURCE_GROUP}" --cluster "${CLUSTER_NAME}" || {
  echo -e "${RED}Failed to initialize IoT Ops for cluster '${CLUSTER_NAME}' in resource group '${RESOURCE_GROUP}'${RESET}"
  exit 1
}

echo -e "${GREEN}==========================================================================="
echo -e "Step 13....Creating the IoT Ops Instance"
echo -e "===========================================================================${RESET}"
az iot ops create \
  --cluster "${CLUSTER_NAME}" \
  -g "${RESOURCE_GROUP}" \
  --name "${NE_IOT_INSTANCE}" \
  --sr-resource-id "${SR_RESOURCE_ID}" \
  --ns-resource-id "${NS_RESOURCE_ID}" || {
    echo -e "${RED}Failed to create IoT Ops instance${RESET}"
    exit 1
  }

echo -e "${GREEN}==========================================================================="
echo -e "Step 14.........Assigning User Assigned Managed Identity to the IoT Ops Instance"
echo -e "===========================================================================${RESET}"
USER_ASSIGNED_MI_RESOURCE_ID=$(az identity show --name "${USER_ASSIGNED_MANAGED_IDENTITY}" --resource-group "${RESOURCE_GROUP}" --query id --output tsv)
echo "USER_ASSIGNED_MI_RESOURCE_ID=${USER_ASSIGNED_MI_RESOURCE_ID}"

KEYVAULT_RESOURCE_ID=$(az keyvault show --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}" --query id --output tsv)
echo "KEYVAULT_RESOURCE_ID=${KEYVAULT_RESOURCE_ID}"


az iot ops secretsync enable --instance "${NE_IOT_INSTANCE}" \
  --resource-group "${RESOURCE_GROUP}" \
  --mi-user-assigned "${USER_ASSIGNED_MI_RESOURCE_ID}" \
  --kv-resource-id "${KEYVAULT_RESOURCE_ID}" || {
    echo -e "${RED}Failed to enable Secret Synchronization for IoT Ops${RESET}"
    exit 1 
  }

az iot ops identity assign --name "${NE_IOT_INSTANCE}" \
  --resource-group "${RESOURCE_GROUP}" \
  --mi-user-assigned "${USER_ASSIGNED_MI_RESOURCE_ID}" || {
  echo -e "${RED}Failed to assign User-assigned managed identity for cloud connections${RESET}"
  exit 1
}

sudo kubectl delete pods adr-schema-registry-0 adr-schema-registry-1 -n azure-iot-operations

echo -e "${GREEN}==========================================================================="
echo -e "Step 15.........Grant the Azure Arc Extension that is used for IoT Ops the required permission to send/receive data from EventHub"
echo -e "===========================================================================${RESET}"
AZURE_IOT_OPS_ARC_EXTENSION_RESOURCE_ID=$(az k8s-extension list --cluster-name ${CLUSTER_NAME} --cluster-type connectedClusters --resource-group ${RESOURCE_GROUP} --query "[?extensionType =='microsoft.iotoperations'].id" -o tsv)

AZURE_IOT_OPS_ARC_EXTENSION_OID_FOR_MI=$(az resource show --ids $AZURE_IOT_OPS_ARC_EXTENSION_RESOURCE_ID --query "identity.principalId" -o tsv)

az role assignment create --assignee-object-id  ${AZURE_IOT_OPS_ARC_EXTENSION_OID_FOR_MI} \
  --role "Azure Event Hubs Data Receiver" \
  --scope "subscriptions/084c8f47-bb5d-447e-82cb-63241353edef/resourceGroups/EXP-MFG-AIO-ControlPlane-RG/providers/Microsoft.EventHub/namespaces/aiomfgeventhub001"

az role assignment create --assignee-object-id  ${AZURE_IOT_OPS_ARC_EXTENSION_OID_FOR_MI} \
  --role "Azure Event Hubs Data Sender" \
  --scope "subscriptions/084c8f47-bb5d-447e-82cb-63241353edef/resourceGroups/EXP-MFG-AIO-ControlPlane-RG/providers/Microsoft.EventHub/namespaces/aiomfgeventhub001"

echo -e "${GREEN}Onboarding script completed successfully. Please Review the output to make sure there were no errors.${RESET}"