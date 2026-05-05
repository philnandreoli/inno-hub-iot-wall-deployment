#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Create Virtual Machine - Step 2
# ============================================================================
# This script creates a KVM virtual machine on the Ubuntu host with:
# - Ubuntu 24.04.3 LTS Cloud Image
# - Bridged networking for both IT (DHCP) and OT (Static IP) networks
# - SSH key authentication from Azure Key Vault
# - Configurable CPU, RAM, and disk size
# - Disk stored in /data directory
#
# Prerequisites:
# - Host must be Arc enabled (step1 completed)
# - Azure CLI installed and logged in
# - KVM/QEMU packages will be installed by this script
#
# Usage:
#   ./step2-create-vm.sh \
#     --service-principal-id <sp-id> \
#     --service-principal-secret <sp-secret> \
#     --subscription-id <subscription-id> \
#     --tenant-id <tenant-id> \
#     --location <location> \
#     --data-center <datacenter> \
#     --city <city> \
#     --state-region <state-region> \
#     --country <country> \
#     --keyvault-name <keyvault-name> \
#     --ssh-key-secret-name <ssh-key-secret> \
#     --ssh-pub-key-secret-name <ssh-pub-key-secret> \
#     --it-network-interface <interface> \
#     --ot-network-interface <interface>
#
# Example:
#   ./step2-create-vm.sh \
#     --service-principal-id "12345678-1234-1234-1234-123456789abc" \
#     --service-principal-secret "your-secret-here" \
#     --subscription-id "12345678-1234-1234-1234-123456789abc" \
#     --tenant-id "12345678-1234-1234-1234-123456789abc" \
#     --location "eastus2" \
#     --data-center "CHI" \
#     --city "Chicago" \
#     --state-region "IL" \
#     --country "US" \
#     --keyvault-name "chi-iot-wall-kv" \
#     --ssh-key-secret-name "vm-ssh-private-key" \
#     --ssh-pub-key-secret-name "vm-ssh-public-key" \
#     --it-network-interface "eth1" \
#     --ot-network-interface "eth2"
# ============================================================================

# Function to display usage
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
    echo "  --city NAME                        City name (e.g., Chicago, St. Louis)"
    echo "  --state-region CODE                State/Region code (e.g., IL, MO)"
    echo "  --country CODE                     2-letter country code (e.g., US, NL)"
    echo "  --keyvault-name NAME               Azure Key Vault name"
    echo "  --ssh-key-secret-name NAME         Name of SSH private key secret in Key Vault"
    echo "  --ssh-pub-key-secret-name NAME     Name of SSH public key secret in Key Vault"
    echo "  --it-network-interface NAME        IT network interface name (e.g., eth1)"
    echo "  --ot-network-interface NAME        OT network interface name (e.g., eth2)"
    echo ""
    echo "Optional Options:"
    echo "  --vm-cpus COUNT                    Number of CPUs for VM (default: 4)"
    echo "  --vm-ram-gb SIZE                   RAM in GB for VM (default: 10)"
    echo "  --vm-disk-gb SIZE                  Disk size in GB for VM (default: 100)"
    echo "  --ot-network-host-ip IP            OT network IP for host (default: 192.168.30.17)"
    echo "  --ot-network-vm-ip IP              OT network IP for VM (default: 192.168.30.18)"
    echo "  -h, --help                         Display this help message"
    echo ""
    echo "Note: Arguments can be provided via command-line or environment variables."
    echo "      Command-line arguments take precedence over environment variables."
    exit 1
}

# Parse command-line arguments
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
        --city)
            ARG_CITY="$2"
            shift 2
            ;;
        --state-region)
            ARG_STATE_REGION="$2"
            shift 2
            ;;
        --country)
            ARG_COUNTRY="$2"
            shift 2
            ;;
        --keyvault-name)
            ARG_KEYVAULT_NAME="$2"
            shift 2
            ;;
        --ssh-key-secret-name)
            ARG_SSH_KEY_SECRET_NAME="$2"
            shift 2
            ;;
        --ssh-pub-key-secret-name)
            ARG_SSH_PUB_KEY_SECRET_NAME="$2"
            shift 2
            ;;
        --it-network-interface)
            ARG_IT_NETWORK_INTERFACE="$2"
            shift 2
            ;;
        --ot-network-interface)
            ARG_OT_NETWORK_INTERFACE="$2"
            shift 2
            ;;
        --vm-cpus)
            ARG_VM_CPUS="$2"
            shift 2
            ;;
        --vm-ram-gb)
            ARG_VM_RAM_GB="$2"
            shift 2
            ;;
        --vm-disk-gb)
            ARG_VM_DISK_GB="$2"
            shift 2
            ;;
        --ot-network-host-ip)
            ARG_OT_NETWORK_HOST_IP="$2"
            shift 2
            ;;
        --ot-network-vm-ip)
            ARG_OT_NETWORK_VM_IP="$2"
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

# Use command-line arguments if provided, otherwise fall back to environment variables
export SERVICE_PRINCIPAL_ID="${ARG_SERVICE_PRINCIPAL_ID:-${SERVICE_PRINCIPAL_ID}}"
export SERVICE_PRINCIPAL_CLIENT_SECRET="${ARG_SERVICE_PRINCIPAL_SECRET:-${SERVICE_PRINCIPAL_CLIENT_SECRET}}"
export SUBSCRIPTION_ID="${ARG_SUBSCRIPTION_ID:-${SUBSCRIPTION_ID}}"
export TENANT_ID="${ARG_TENANT_ID:-${TENANT_ID}}"
export LOCATION="${ARG_LOCATION:-${LOCATION:-eastus2}}"
export DATA_CENTER="${ARG_DATA_CENTER:-${DATA_CENTER}}"
export CITY="${ARG_CITY:-${CITY}}"
export STATE_REGION="${ARG_STATE_REGION:-${STATE_REGION}}"
export COUNTRY="${ARG_COUNTRY:-${COUNTRY}}"
export KEYVAULT_NAME="${ARG_KEYVAULT_NAME:-${KEYVAULT_NAME}}"
export SSH_KEY_SECRET_NAME="${ARG_SSH_KEY_SECRET_NAME:-${SSH_KEY_SECRET_NAME}}"
export SSH_PUB_KEY_SECRET_NAME="${ARG_SSH_PUB_KEY_SECRET_NAME:-${SSH_PUB_KEY_SECRET_NAME}}"
export IT_NETWORK_INTERFACE="${ARG_IT_NETWORK_INTERFACE:-${IT_NETWORK_INTERFACE}}"
export OT_NETWORK_INTERFACE="${ARG_OT_NETWORK_INTERFACE:-${OT_NETWORK_INTERFACE}}"
export VM_CPUS="${ARG_VM_CPUS:-${VM_CPUS:-4}}"
export VM_RAM_GB="${ARG_VM_RAM_GB:-${VM_RAM_GB:-16}}"
export VM_DISK_GB="${ARG_VM_DISK_GB:-${VM_DISK_GB:-100}}"
export OT_NETWORK_HOST_IP="${ARG_OT_NETWORK_HOST_IP:-${OT_NETWORK_HOST_IP:-192.168.30.17}}"
export OT_NETWORK_VM_IP="${ARG_OT_NETWORK_VM_IP:-${OT_NETWORK_VM_IP:-192.168.30.18}}"
export OT_NETWORK_NETMASK="255.255.255.0"

# VM settings
export HOST_NAME=$(hostname -s)
export VM_NAME="${HOST_NAME}-vm"
export VM_DISK_PATH="/data/${VM_NAME}.qcow2"
export UBUNTU_CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"

echo -e "${GREEN}======================================================================================================"
echo -e " Create Virtual Machine - Configuration Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Host Name: ${HOST_NAME}${RESET}"
echo -e "${GREEN}VM Name: ${VM_NAME}${RESET}"
echo -e "${GREEN}VM CPUs: ${VM_CPUS}${RESET}"
echo -e "${GREEN}VM RAM: ${VM_RAM_GB} GB${RESET}"
echo -e "${GREEN}VM Disk: ${VM_DISK_GB} GB${RESET}"
echo -e "${GREEN}VM Disk Path: ${VM_DISK_PATH}${RESET}"
echo -e "${GREEN}IT Network Interface: ${IT_NETWORK_INTERFACE}${RESET}"
echo -e "${GREEN}OT Network Interface: ${OT_NETWORK_INTERFACE}${RESET}"
echo -e "${GREEN}OT Network Host IP: ${OT_NETWORK_HOST_IP}${RESET}"
echo -e "${GREEN}OT Network VM IP: ${OT_NETWORK_VM_IP}${RESET}"
echo -e "${GREEN}Key Vault Name: ${KEYVAULT_NAME}${RESET}"
echo -e "${GREEN}SSH Key Secret: ${SSH_KEY_SECRET_NAME}${RESET}"
echo ""

# Validation
if [ -z "$SERVICE_PRINCIPAL_ID" ] || [ -z "$SERVICE_PRINCIPAL_CLIENT_SECRET" ] || \
   [ -z "$SUBSCRIPTION_ID" ] || [ -z "$TENANT_ID" ] || \
   [ -z "$KEYVAULT_NAME" ] || [ -z "$SSH_KEY_SECRET_NAME" ] || [ -z "$SSH_PUB_KEY_SECRET_NAME" ] || \
   [ -z "$IT_NETWORK_INTERFACE" ] || [ -z "$OT_NETWORK_INTERFACE" ]; then
    echo -e "${RED}ERROR: Required parameters are missing.${RESET}"
    echo -e "${RED}Please provide all required arguments or set environment variables.${RESET}"
    echo ""
    usage
fi

# Create resource group with naming convention: EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG
RESOURCE_GROUP="EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG"
echo -e "${GREEN}Resource Group Name: ${RESOURCE_GROUP}${RESET}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 1: Logging into Azure"
echo -e "======================================================================================================${RESET}"
az login --service-principal -u "${SERVICE_PRINCIPAL_ID}" -p="${SERVICE_PRINCIPAL_CLIENT_SECRET}" --tenant "${TENANT_ID}"
az account set --subscription "$SUBSCRIPTION_ID"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 2: Retrieving SSH Keys from Azure Key Vault"
echo -e "======================================================================================================${RESET}"

# Create .ssh directory if it doesn't exist
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Retrieve SSH private key
echo -e "${YELLOW}Retrieving SSH private key from Key Vault...${RESET}"
az keyvault secret show --vault-name "${KEYVAULT_NAME}" --name "${SSH_KEY_SECRET_NAME}" --query value -o tsv > ~/.ssh/vm_id_rsa
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to retrieve SSH private key from Key Vault${RESET}"
    echo -e "${RED}Vault: ${KEYVAULT_NAME}, Secret: ${SSH_KEY_SECRET_NAME}${RESET}"
    exit 1
fi

# Validate private key was retrieved
if [ ! -s ~/.ssh/vm_id_rsa ]; then
    echo -e "${RED}ERROR: SSH private key file is empty!${RESET}"
    echo -e "${RED}Check that the secret '${SSH_KEY_SECRET_NAME}' exists in Key Vault '${KEYVAULT_NAME}'${RESET}"
    exit 1
fi

# Check if it looks like a valid SSH private key
if ! grep -q "BEGIN.*PRIVATE KEY" ~/.ssh/vm_id_rsa; then
    echo -e "${RED}ERROR: Retrieved file doesn't appear to be a valid SSH private key!${RESET}"
    echo -e "${YELLOW}First few lines of retrieved content:${RESET}"
    head -n 3 ~/.ssh/vm_id_rsa
    echo -e "${YELLOW}File size: $(wc -c < ~/.ssh/vm_id_rsa) bytes${RESET}"
    echo -e "${YELLOW}File location: ~/.ssh/vm_id_rsa${RESET}"
    ls -lah ~/.ssh/vm_id_rsa
    exit 1
fi

chmod 600 ~/.ssh/vm_id_rsa
echo -e "${GREEN}✓ SSH private key retrieved and validated${RESET}"
echo -e "${YELLOW}  File: ~/.ssh/vm_id_rsa ($(wc -c < ~/.ssh/vm_id_rsa) bytes)${RESET}"
echo -e "${YELLOW}  First line: $(head -n 1 ~/.ssh/vm_id_rsa)${RESET}"

# Retrieve SSH public key
echo -e "${YELLOW}Retrieving SSH public key from Key Vault...${RESET}"
az keyvault secret show --vault-name "${KEYVAULT_NAME}" --name "${SSH_PUB_KEY_SECRET_NAME}" --query value -o tsv > ~/.ssh/vm_id_rsa.pub
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to retrieve SSH public key from Key Vault${RESET}"
    echo -e "${RED}Vault: ${KEYVAULT_NAME}, Secret: ${SSH_PUB_KEY_SECRET_NAME}${RESET}"
    exit 1
fi

# Validate public key was retrieved
if [ ! -s ~/.ssh/vm_id_rsa.pub ]; then
    echo -e "${RED}ERROR: SSH public key file is empty!${RESET}"
    echo -e "${RED}Check that the secret '${SSH_PUB_KEY_SECRET_NAME}' exists in Key Vault '${KEYVAULT_NAME}'${RESET}"
    exit 1
fi

# Check if it looks like a valid SSH public key
if ! grep -q "^ssh-" ~/.ssh/vm_id_rsa.pub; then
    echo -e "${RED}ERROR: Retrieved file doesn't appear to be a valid SSH public key!${RESET}"
    echo -e "${YELLOW}Content:${RESET}"
    cat ~/.ssh/vm_id_rsa.pub
    echo -e "${YELLOW}File size: $(wc -c < ~/.ssh/vm_id_rsa.pub) bytes${RESET}"
    ls -lah ~/.ssh/vm_id_rsa.pub
    exit 1
fi

chmod 644 ~/.ssh/vm_id_rsa.pub
SSH_PUBLIC_KEY=$(cat ~/.ssh/vm_id_rsa.pub)
echo -e "${GREEN}✓ SSH public key retrieved and validated${RESET}"
echo -e "${YELLOW}  File: ~/.ssh/vm_id_rsa.pub ($(wc -c < ~/.ssh/vm_id_rsa.pub) bytes)${RESET}"
echo -e "${YELLOW}  Content: $(head -c 50 ~/.ssh/vm_id_rsa.pub)...${RESET}"

# Display key fingerprints for verification
echo -e "${YELLOW}Key information:${RESET}"
echo -e "  Private key: ~/.ssh/vm_id_rsa"
echo -e "  Public key:  ~/.ssh/vm_id_rsa.pub"
echo -e "  Private key fingerprint: $(ssh-keygen -lf ~/.ssh/vm_id_rsa 2>/dev/null || echo 'Unable to generate fingerprint')"
echo -e "  Public key fingerprint:  $(ssh-keygen -lf ~/.ssh/vm_id_rsa.pub 2>/dev/null || echo 'Unable to generate fingerprint')"
echo ""
echo -e "${YELLOW}Verifying keys match (generating public key from private key):${RESET}"
GENERATED_PUB_KEY=$(ssh-keygen -y -f ~/.ssh/vm_id_rsa 2>/dev/null)
STORED_PUB_KEY=$(cat ~/.ssh/vm_id_rsa.pub)
if [ "$GENERATED_PUB_KEY" = "$STORED_PUB_KEY" ]; then
    echo -e "${GREEN}✓ SSH keys are a matching pair!${RESET}"
else
    echo -e "${RED}✗ WARNING: SSH keys DO NOT match!${RESET}"
    echo -e "${YELLOW}Generated from private key:${RESET}"
    echo "$GENERATED_PUB_KEY"
    echo -e "${YELLOW}Stored in Key Vault:${RESET}"
    echo "$STORED_PUB_KEY"
    echo -e "${RED}This will cause authentication failures. Keys must be regenerated.${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 3: Installing KVM and Required Packages"
echo -e "======================================================================================================${RESET}"
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager cloud-image-utils genisoimage

# Add current user to libvirt groups
sudo usermod -aG libvirt $(whoami)
sudo usermod -aG kvm $(whoami)

# Start and enable libvirtd
sudo systemctl enable --now libvirtd
sudo systemctl start libvirtd

echo -e "${GREEN}======================================================================================================"
echo -e "Step 4: Verifying Network Bridges"
echo -e "======================================================================================================${RESET}"

# Verify that bridges exist (should have been created in step0)
BR_IT_EXISTS=$(ip link show br-it 2>/dev/null)
BR_OT_EXISTS=$(ip link show br-ot 2>/dev/null)

if [ -z "$BR_IT_EXISTS" ]; then
    echo -e "${RED}ERROR: Bridge br-it does not exist!${RESET}"
    echo -e "${RED}Please run step0-configure-host-networking.sh first to create network bridges.${RESET}"
    exit 1
fi

if [ -z "$BR_OT_EXISTS" ]; then
    echo -e "${RED}ERROR: Bridge br-ot does not exist!${RESET}"
    echo -e "${RED}Please run step0-configure-host-networking.sh first to create network bridges.${RESET}"
    exit 1
fi

echo -e "${GREEN}Network bridges verified successfully:${RESET}"
ip addr show br-it | grep -E "^[0-9]+:|inet "
echo ""
ip addr show br-ot | grep -E "^[0-9]+:|inet "

echo -e "${GREEN}======================================================================================================"
echo -e "Step 5: Creating Virtual Network Bridges in libvirt"
echo -e "======================================================================================================${RESET}"

# Create IT network bridge definition
cat > /tmp/br-it-network.xml <<EOF
<network>
  <name>br-it</name>
  <forward mode="bridge"/>
  <bridge name="br-it"/>
</network>
EOF

# Create OT network bridge definition
cat > /tmp/br-ot-network.xml <<EOF
<network>
  <name>br-ot</name>
  <forward mode="bridge"/>
  <bridge name="br-ot"/>
</network>
EOF

# Define and start networks
sudo virsh net-define /tmp/br-it-network.xml
sudo virsh net-start br-it
sudo virsh net-autostart br-it

sudo virsh net-define /tmp/br-ot-network.xml
sudo virsh net-start br-ot
sudo virsh net-autostart br-ot

# Clean up temporary files
rm /tmp/br-it-network.xml /tmp/br-ot-network.xml

echo -e "${GREEN}======================================================================================================"
echo -e "Step 6: Creating /data Directory for VM Storage"
echo -e "======================================================================================================${RESET}"
sudo mkdir -p /data
sudo chown -R $(whoami):$(whoami) /data
sudo chmod 755 /data

echo -e "${GREEN}======================================================================================================"
echo -e "Step 7: Downloading Ubuntu 24.04 Cloud Image"
echo -e "======================================================================================================${RESET}"
CLOUD_IMAGE="/tmp/ubuntu-24.04-server-cloudimg-amd64.img"
if [ ! -f "$CLOUD_IMAGE" ]; then
    echo -e "${YELLOW}Downloading Ubuntu 24.04 cloud image...${RESET}"
    wget -O "$CLOUD_IMAGE" "$UBUNTU_CLOUD_IMAGE_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to download Ubuntu cloud image${RESET}"
        exit 1
    fi
else
    echo -e "${YELLOW}Cloud image already exists, skipping download${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 8: Creating VM Disk from Cloud Image"
echo -e "======================================================================================================${RESET}"
if [ -f "$VM_DISK_PATH" ]; then
    echo -e "${YELLOW}VM disk already exists at ${VM_DISK_PATH}. Removing old disk...${RESET}"
    rm -f "$VM_DISK_PATH"
fi

# Convert cloud image to standalone disk without backing file
# This prevents "Cannot access backing file" errors after reboots
echo -e "${YELLOW}Converting cloud image to standalone VM disk (this may take a minute)...${RESET}"
qemu-img convert -f qcow2 -O qcow2 "$CLOUD_IMAGE" "$VM_DISK_PATH"
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to convert cloud image to VM disk${RESET}"
    exit 1
fi

# Resize the disk to the specified size
echo -e "${YELLOW}Resizing disk to ${VM_DISK_GB}GB...${RESET}"
qemu-img resize "$VM_DISK_PATH" "${VM_DISK_GB}G"
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to resize VM disk${RESET}"
    exit 1
fi

# Verify the disk has no backing file
BACKING_FILE=$(sudo qemu-img info "$VM_DISK_PATH" | grep "backing file:" || true)
if [ -n "$BACKING_FILE" ]; then
    echo -e "${RED}Warning: VM disk still has a backing file. This may cause issues.${RESET}"
else
    echo -e "${GREEN}VM disk is standalone (no backing file dependency)${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 9: Creating Cloud-Init Configuration"
echo -e "======================================================================================================${RESET}"

# Create cloud-init user-data
cat > /tmp/user-data <<EOF
#cloud-config
hostname: ${VM_NAME}
fqdn: ${VM_NAME}.local
manage_etc_hosts: true

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

# Disable password authentication
ssh_pwauth: false

# Package management
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - net-tools
  - curl
  - wget

# Network configuration will be done via cloud-init network config
# Also persist network config to netplan for post-reboot persistence
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - |
    cat > /etc/netplan/50-cloud-init.yaml <<NETPLAN
    network:
      version: 2
      ethernets:
        enp1s0:
          dhcp4: true
          dhcp6: false
          optional: false
        enp2s0:
          addresses:
            - ${OT_NETWORK_VM_IP}/24
          dhcp4: false
          dhcp6: false
          optional: false
    NETPLAN
  - chmod 600 /etc/netplan/50-cloud-init.yaml
  - netplan apply
  - echo "VM initialization complete" > /tmp/cloud-init-complete

power_state:
  mode: reboot
  condition: true
EOF

# Create cloud-init network configuration for VM
cat > /tmp/network-config <<EOF
version: 2
ethernets:
  enp1s0:
    dhcp4: true
    dhcp6: false
    optional: false
  enp2s0:
    addresses:
      - ${OT_NETWORK_VM_IP}/24
    dhcp4: false
    dhcp6: false
    optional: false
EOF

# Create cloud-init meta-data
cat > /tmp/meta-data <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

# Create cloud-init ISO
echo -e "${YELLOW}Creating cloud-init ISO...${RESET}"
cloud-localds /tmp/cloud-init.iso /tmp/user-data /tmp/meta-data --network-config=/tmp/network-config

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create cloud-init ISO${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 10: Creating and Starting Virtual Machine"
echo -e "======================================================================================================${RESET}"

# Create the VM using virt-install
# Convert GB to MB for virt-install (requires integer MB value)
VM_RAM_MB=$((VM_RAM_GB * 1024))

sudo virt-install \
    --name "${VM_NAME}" \
    --memory "${VM_RAM_MB}" \
    --vcpus "${VM_CPUS}" \
    --disk path="${VM_DISK_PATH}",format=qcow2,bus=virtio \
    --disk path=/tmp/cloud-init.iso,device=cdrom \
    --network bridge=br-it,model=virtio \
    --network bridge=br-ot,model=virtio \
    --os-variant ubuntu24.04 \
    --graphics none \
    --console pty,target_type=serial \
    --import \
    --noautoconsole \
    --features acpi=on,apic=on \
    --pm suspend_to_mem.enabled=on,suspend_to_disk.enabled=on

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create virtual machine${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 11: Configuring VM Autostart on Host Reboot"
echo -e "======================================================================================================${RESET}"
sudo virsh autostart "${VM_NAME}"

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Warning: Failed to set VM autostart${RESET}"
else
    echo -e "${GREEN}VM configured to automatically start on host reboot${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 11b: Removing Cloud-Init ISO from VM Configuration"
echo -e "======================================================================================================${RESET}"
echo -e "${YELLOW}Waiting 30 seconds for cloud-init to complete before ejecting ISO...${RESET}"
sleep 30

# Eject the cloud-init ISO to prevent boot errors after reboot
sudo virsh change-media "${VM_NAME}" sda --eject --config 2>/dev/null || \
sudo virsh detach-disk "${VM_NAME}" /tmp/cloud-init.iso --persistent 2>/dev/null || \
echo -e "${YELLOW}Cloud-init ISO already ejected or not found${RESET}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Cloud-init ISO ejected from VM${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 12: Waiting for VM to Start"
echo -e "======================================================================================================${RESET}"
echo -e "${YELLOW}Waiting 90 seconds for VM to boot and cloud-init to complete...${RESET}"
sleep 90

# Check VM status
VM_STATUS=$(sudo virsh domstate "${VM_NAME}")
echo -e "${GREEN}VM Status: ${VM_STATUS}${RESET}"

if [ "$VM_STATUS" != "running" ]; then
    echo -e "${RED}ERROR: VM is not running! Status: ${VM_STATUS}${RESET}"
    echo -e "${YELLOW}Try accessing VM console: sudo virsh console ${VM_NAME}${RESET}"
    exit 1
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 13: Verifying Network Connectivity to VM"
echo -e "======================================================================================================${RESET}"

echo -e "${YELLOW}Checking host network configuration first...${RESET}"
echo -e "Host OT network bridge (br-ot) status:"
ip addr show br-ot
echo ""
echo -e "Host firewall status:"
sudo iptables -L -n -v | grep -E "FORWARD|br-ot|${OT_NETWORK_VM_IP}" || echo "No specific firewall rules found"
echo ""

echo -e "${YELLOW}Testing network connectivity to VM at ${OT_NETWORK_VM_IP}...${RESET}"

# Wait for VM network to be ready (retry ping with timeout)
PING_RETRIES=5
PING_COUNT=0
PING_SUCCESS=false

while [ $PING_COUNT -lt $PING_RETRIES ]; do
    echo -e "${YELLOW}Ping attempt $((PING_COUNT + 1))/$PING_RETRIES...${RESET}"
    
    if ping -c 3 -W 2 ${OT_NETWORK_VM_IP}; then
        PING_SUCCESS=true
        echo -e "${GREEN}✓ Network ping to VM successful!${RESET}"
        break
    else
        echo -e "${YELLOW}Ping failed, waiting 5 seconds before retry...${RESET}"
        PING_COUNT=$((PING_COUNT + 1))
        if [ $PING_COUNT -lt $PING_RETRIES ]; then
            sleep 5
        fi
    fi
done

if [ "$PING_SUCCESS" = false ]; then
    echo -e "${RED}WARNING: Cannot ping VM at ${OT_NETWORK_VM_IP} after $PING_RETRIES attempts${RESET}"
    echo -e "${YELLOW}Network may still be initializing. Checking OT network bridge status...${RESET}"
    ip addr show br-ot
    echo ""
    echo -e "${YELLOW}Checking ARP table for VM...${RESET}"
    arp -n | grep ${OT_NETWORK_VM_IP} || echo "VM not found in ARP table (not on network yet)"
    echo ""
    echo -e "${YELLOW}Checking if we can reach the VM's subnet...${RESET}"
    ip route get ${OT_NETWORK_VM_IP}
    echo ""
    echo -e "${YELLOW}Proceeding to SSH test anyway (VM may respond to SSH even if ping fails)${RESET}"
fi

echo -e "${GREEN}======================================================================================================"
echo -e "Step 14: Testing SSH Connection to VM"
echo -e "======================================================================================================${RESET}"

# Remove any old SSH host key for this IP to avoid "REMOTE HOST IDENTIFICATION HAS CHANGED" warnings
echo -e "${YELLOW}Removing any old SSH host keys for ${OT_NETWORK_VM_IP}...${RESET}"
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${OT_NETWORK_VM_IP}" 2>/dev/null || true

# Test SSH connection
MAX_RETRIES=15
RETRY_COUNT=0
SSH_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo -e "${YELLOW}Attempting SSH connection (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)...${RESET}"
    
    # Try SSH with verbose error output for first few attempts
    if [ $RETRY_COUNT -lt 3 ]; then
        ssh -i ~/.ssh/vm_id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ubuntu@${OT_NETWORK_VM_IP} "echo 'SSH connection successful'" 2>&1 | grep -i "connection\|refused\|timeout" || true
    fi
    
    ssh -i ~/.ssh/vm_id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ubuntu@${OT_NETWORK_VM_IP} "echo 'SSH connection successful'" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        SSH_SUCCESS=true
        echo -e "${GREEN}SSH connection to VM successful!${RESET}"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 15
done

if [ "$SSH_SUCCESS" = false ]; then
    echo -e "${RED}======================================================================================================"
    echo -e "ERROR: Could not establish SSH connection to VM after $MAX_RETRIES attempts"
    echo -e "======================================================================================================${RESET}"
    echo ""
    echo -e "${YELLOW}Possible causes:${RESET}"
    echo -e "  1. VM still booting or cloud-init not finished"
    echo -e "  2. SSH keys not properly configured in cloud-init"
    echo -e "  3. Network configuration issue (VM doesn't have ${OT_NETWORK_VM_IP})"
    echo -e "  4. Firewall blocking SSH connections"
    echo ""
    echo -e "${YELLOW}Troubleshooting steps:${RESET}"
    echo -e "  ${GREEN}Step 1: Check if VM is running${RESET}"
    echo -e "    sudo virsh domstate ${VM_NAME}"
    echo ""
    echo -e "  ${GREEN}Step 2: Connect to VM console (Ctrl+] to exit)${RESET}"
    echo -e "    sudo virsh console ${VM_NAME}"
    echo -e "    Login as: ubuntu (no password needed)"
    echo -e "    Check IP: ip addr show"
    echo -e "    Check cloud-init: sudo cloud-init status"
    echo ""
    echo -e "  ${GREEN}Step 3: Check network bridges on host${RESET}"
    echo -e "    ip addr show br-it"
    echo -e "    ip addr show br-ot"
    echo ""
    echo -e "  ${GREEN}Step 4: Check VM network from console${RESET}"
    echo -e "    sudo virsh console ${VM_NAME}"
    echo -e "    ip addr show enp1s0  # Should have DHCP address"
    echo -e "    ip addr show enp2s0  # Should have ${OT_NETWORK_VM_IP}"
    echo -e "    sudo journalctl -u cloud-init -f  # Watch cloud-init logs"
    echo ""
    echo -e "  ${GREEN}Step 5: Manually trigger DHCP on VM (from console)${RESET}"
    echo -e "    sudo dhclient enp1s0"
    echo -e "    sudo systemctl restart systemd-networkd"
    echo ""
    echo -e "  ${GREEN}Step 6: Try SSH with password (if needed)${RESET}"
    echo -e "    From console, set password: sudo passwd ubuntu"
    echo -e "    Then SSH: ssh ubuntu@${OT_NETWORK_VM_IP}"
    echo ""
    echo -e "${RED}NOTE: You should resolve SSH connectivity before proceeding to step3${RESET}"
    exit 1
else
    echo -e "${GREEN}======================================================================================================"
    echo -e "Step 15: Checking VM Network Configuration"
    echo -e "======================================================================================================${RESET}"
    
    echo -e "${YELLOW}IT Network (enp1s0) - Should have DHCP address:${RESET}"
    ssh -i ~/.ssh/vm_id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${OT_NETWORK_VM_IP} "ip addr show enp1s0" 2>/dev/null
    IT_IP=$(ssh -i ~/.ssh/vm_id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${OT_NETWORK_VM_IP} "ip addr show enp1s0 | grep 'inet ' | awk '{print \$2}'" 2>/dev/null)
    if [ -n "$IT_IP" ]; then
        echo -e "${GREEN}IT Network IP: ${IT_IP}${RESET}"
    else
        echo -e "${RED}WARNING: No IP address found on IT network interface!${RESET}"
        echo -e "${YELLOW}You may need to manually configure DHCP on the VM${RESET}"
    fi
    
    echo ""
    echo -e "${YELLOW}OT Network (enp2s0) - Should have ${OT_NETWORK_VM_IP}:${RESET}"
    ssh -i ~/.ssh/vm_id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${OT_NETWORK_VM_IP} "ip addr show enp2s0" 2>/dev/null
    
    echo ""
    echo -e "${YELLOW}Testing internet connectivity from VM:${RESET}"
    ssh -i ~/.ssh/vm_id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${OT_NETWORK_VM_IP} "ping -c 2 8.8.8.8" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Internet connectivity: OK${RESET}"
    else
        echo -e "${RED}✗ Internet connectivity: FAILED${RESET}"
        echo -e "${YELLOW}  This may prevent Azure Arc enablement in step3${RESET}"
    fi
    
    echo ""
    echo -e "${YELLOW}Cloud-init status:${RESET}"
    ssh -i ~/.ssh/vm_id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${OT_NETWORK_VM_IP} "sudo cloud-init status" 2>/dev/null
fi

# Clean up temporary files
rm -f /tmp/user-data /tmp/meta-data /tmp/network-config

echo -e "${GREEN}======================================================================================================"
echo -e "Virtual Machine Creation Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}VM Name: ${VM_NAME}${RESET}"
echo -e "${GREEN}IT Network: DHCP (br-it)${RESET}"
echo -e "${GREEN}OT Network: ${OT_NETWORK_VM_IP}/24 (br-ot)${RESET}"
echo -e "${GREEN}SSH Access: ssh -i ~/.ssh/vm_id_rsa ubuntu@${OT_NETWORK_VM_IP}${RESET}"
echo ""
echo -e "${GREEN}Useful Commands:${RESET}"
echo -e "  View VM status:  sudo virsh domstate ${VM_NAME}"
echo -e "  Start VM:        sudo virsh start ${VM_NAME}"
echo -e "  Stop VM:         sudo virsh shutdown ${VM_NAME}"
echo -e "  Force stop VM:   sudo virsh destroy ${VM_NAME}"
echo -e "  Delete VM:       sudo virsh undefine ${VM_NAME}"
echo -e "  VM console:      sudo virsh console ${VM_NAME}"
echo ""
echo -e "${GREEN}Next Step: Run step3-arc-enable-vm.sh to Arc enable the virtual machine.${RESET}"
