# Azure IoT Operations Deployment - Version 2

## Overview

This version 2 deployment creates a virtualized architecture where:
- The **Ubuntu host** networking is configured first (step0)
- The **Ubuntu host** is Arc-enabled (step1)
- A **virtual machine** is created on the host with KVM (step2)
- The **VM** is Arc-enabled separately (step3)
- **k3s Kubernetes** is installed on the VM (step4)
- The **k3s cluster** is Arc-enabled (step4)
- **Azure IoT Operations** is deployed on the VM's k3s cluster (step5)

This approach provides isolation and flexibility for IoT Operations deployment while maintaining connectivity to both IT and OT networks.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Ubuntu Host (24.04.3 LTS)                                  │
│ - Arc Enabled                                               │
│ - IT Network (eth1): DHCP                                   │
│ - OT Network (eth2): 192.168.30.17/24 (Static)             │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Virtual Machine (Ubuntu 24.04.3 LTS Cloud Image)      │  │
│  │ - Arc Enabled                                          │  │
│  │ - IT Network (enp1s0): DHCP via br-it bridge          │  │
│  │ - OT Network (enp2s0): 192.168.30.16/24 (Static)      │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────────┐ │  │
│  │  │ k3s Kubernetes Cluster                           │ │  │
│  │  │ - Arc Enabled                                     │ │  │
│  │  │                                                   │ │  │
│  │  │  ┌────────────────────────────────────────────┐  │ │  │
│  │  │  │ Azure IoT Operations                       │  │ │  │
│  │  │  │ - Schema Registry                          │  │ │  │
│  │  │  │ - IoT Operations Instance                  │  │ │  │
│  │  │  │ - OPC UA Connector                         │  │ │  │
│  │  │  │ - Dataflows to Event Hub                   │  │ │  │
│  │  │  └────────────────────────────────────────────┘  │ │  │
│  │  └──────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Hardware/Infrastructure
- Ubuntu Server 24.04.3 LTS host
- Minimum 8 CPU cores (4 for VM, 4 for host)
- Minimum 16 GB RAM (8 GB for VM, 8 GB for host)
- Minimum 200 GB disk space (/data directory will store VM disk)
- Two network interfaces:
  - IT Network interface (for internet/Azure connectivity)
  - OT Network interface (for OPC UA devices)
- **Console access or KVM recommended** (network reconfiguration in step0 will disconnect SSH)

### Azure Requirements
- Azure subscription with appropriate permissions
- Service Principal with the following roles:
  - Contributor on the resource group
  - Azure Connected Machine Resource Administrator
  - Kubernetes Cluster - Azure Arc Onboarding
- Azure Resource Group (pre-created based on region)
- Azure Key Vault with SSH key pair stored as secrets

### Network Requirements
- IT Network: DHCP enabled, internet connectivity
- OT Network: Isolated network (no gateway required)
  - Host IP: 192.168.30.17/24
  - VM IP: 192.168.30.18/24
- OPC UA devices should be accessible from OT network:
  - Beckhoff CX51x0 at 192.168.30.11:4840
  - Leuze BCL300i at 192.168.30.21:4840

## Azure Resources

The deployment creates the following Azure resources:


### Per Deployment (Auto-created)
- 2 Arc-enabled Servers (host + VM)
- 1 Arc-enabled Kubernetes cluster
- 1 Azure Key Vault
- 1 Storage Account (for Schema Registry)
- 1 IoT Operations Schema Registry
- 1 IoT Operations Namespace
- 1 IoT Operations Instance
- 1 User Assigned Managed Identity

## Environment Variables

All scripts require the following environment variables to be configured:

### Service Principal Credentials
```bash
export SERVICE_PRINCIPAL_ID="<your-sp-app-id>"
export SERVICE_PRINCIPAL_CLIENT_SECRET="<your-sp-secret>"
export SUBSCRIPTION_ID="<your-subscription-id>"
export TENANT_ID="<your-tenant-id>"
```

### Regional Settings
```bash
# For Americas
export LOCATION="eastus2"

# For EMEA
export LOCATION="northeurope"

# For APAC
export LOCATION="southeastasia"
```

### Innovation Hub Settings
```bash
export DATA_CENTER="CHI"        # e.g., CHI, STL, AMS
export CITY="Chicago"           # e.g., Chicago, St. Louis
export STATE_REGION="IL"        # e.g., IL, MO
export COUNTRY="US"             # 2-letter country code
```

### VM Configuration (step2-create-vm.sh)
```bash
# Network interfaces on host
export IT_NETWORK_INTERFACE="eth1"
export OT_NETWORK_INTERFACE="eth2"

# Azure Key Vault settings
export KEYVAULT_NAME="<your-keyvault-name>"
export SSH_KEY_SECRET_NAME="<ssh-private-key-secret>"
export SSH_PUB_KEY_SECRET_NAME="<ssh-public-key-secret>"

# Optional: VM resource configuration
export VM_CPUS="4"              # Default: 4
export VM_RAM_MB="8192"         # Default: 8192 (8 GB)
export VM_DISK_GB="100"         # Default: 100 GB
```

## Deployment Steps

### Step 0: Configure Host Networking
**Script:** `step0-configure-host-networking.sh`

**Purpose:** Configures the network interfaces on the Ubuntu host with proper naming and IP addressing.

**What it does:**
- Creates udev rules to rename network interfaces based on MAC addresses
- Configures eth1 (IT Network) with DHCP
- Configures eth2 (OT Network) with static IP 192.168.30.17/24
- Applies netplan configuration

**Run on:** Ubuntu host (directly - requires console access recommended)

**⚠️ WARNING:** This script will reconfigure your network and will disconnect your SSH session. You may receive a new IP address.

**Usage:**
```bash
./step0-configure-host-networking.sh --it-network-mac <IT_NETWORK_MAC_ADDRESS> --ot-mac <OT_NETWORK_MAC_ADDRESS>
```

**Example:**
```bash
# First, find your MAC addresses
ip link show
# or
ifconfig -a

# Run the script with MAC addresses as arguments
chmod +x step0-configure-host-networking.sh
./step0-configure-host-networking.sh --it-network-mac "aa:bb:cc:dd:ee:ff" --ot-network-mac "11:22:33:44:55:66"
```

**After Running:**
- Your SSH session will be disconnected
- Reconnect using the new DHCP IP address or static IP 192.168.30.17
- Verify interfaces: `ip addr show eth1` and `ip addr show eth2`

---

### Step 1: Arc Enable Host
**Script:** `step1-arc-enable-host.sh`

**Purpose:** Connects the Ubuntu host to Azure Arc, enabling remote management and SSH access.

**What it does:**
- Installs Azure CLI
- Installs Azure Connected Machine agent
- Connects host to Azure Arc with appropriate tags
- Configures SSH and Microsoft Entra login
- Applies security hardening (SFI requirements)

**Run on:** Ubuntu host (directly)

**Usage:**
```bash
./step1-arc-enable-host.sh \
  --service-principal-id <SERVICE_PRINCIPAL_ID> \
  --service-principal-secret <SERVICE_PRINCIPAL_CLIENT_SECRET> \
  --subscription-id <SUBSCRIPTION_ID> \
  --tenant-id <TENANT_ID> \
  --location <LOCATION> \
  --data-center <DATA_CENTER> \
  --city <CITY> \
  --state-region <STATE_REGION> \
  --country <COUNTRY>
```

**Example (AMERICAS - Chicago):**
```bash
chmod +x step1-arc-enable-host.sh
./step1-arc-enable-host.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-service-principal-secret" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --location "eastus2" \
  --data-center "CHI" \
  --city "Chicago" \
  --state-region "IL" \
  --country "US"
```

**Example (EMEA - Amsterdam):**
```bash
./step1-arc-enable-host.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-service-principal-secret" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --location "northeurope" \
  --data-center "AMS" \
  --city "Amsterdam" \
  --state-region "NH" \
  --country "NL"
```

**Note:** Resource group will be automatically created with naming convention: `EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG`

**Verification:**
- Check Azure Portal for Arc-enabled server in your resource group
- Server name should match your hostname

---

### Step 2: Create Virtual Machine
**Script:** `step2-create-vm.sh`

**Purpose:** Creates a KVM virtual machine on the host with bridged networking.

**What it does:**
- Retrieves SSH keys from Azure Key Vault
- Installs KVM/QEMU and virtualization packages
- Creates bridged networks (br-it and br-ot)
- Downloads Ubuntu 24.04 cloud image
- Creates VM disk in /data directory
- Creates VM with cloud-init configuration
- Configures dual network interfaces (IT DHCP + OT Static)
- Tests SSH connectivity

**Run on:** Ubuntu host (directly)

**Usage:**
```bash
./step2-create-vm.sh \
  --service-principal-id <SERVICE_PRINCIPAL_ID> \
  --service-principal-secret <SERVICE_PRINCIPAL_CLIENT_SECRET> \
  --subscription-id <SUBSCRIPTION_ID> \
  --tenant-id <TENANT_ID> \
  --keyvault-name <KEYVAULT_NAME> \
  --ssh-key-secret <SSH_KEY_SECRET_NAME> \
  --ssh-pub-key-secret <SSH_PUB_KEY_SECRET_NAME> \
  --it-interface <IT_NETWORK_INTERFACE> \
  --ot-interface <OT_NETWORK_INTERFACE> \
  [--vm-cpus <VM_CPUS>] \
  [--vm-ram-mb <VM_RAM_MB>] \
  [--vm-disk-gb <VM_DISK_GB>]
```

**Example:**
```bash
chmod +x step2-create-vm.sh
./step2-create-vm.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-service-principal-secret" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --keyvault-name "my-keyvault" \
  --ssh-key-secret "vm-ssh-private-key" \
  --ssh-pub-key-secret "vm-ssh-public-key" \
  --it-interface "eth1" \
  --ot-interface "eth2"
```

**Example with custom VM resources:**
```bash
./step2-create-vm.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-service-principal-secret" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --keyvault-name "my-keyvault" \
  --ssh-key-secret "vm-ssh-private-key" \
  --ssh-pub-key-secret "vm-ssh-public-key" \
  --it-interface "eth1" \
  --ot-interface "eth2" \
  --vm-cpus 8 \
  --vm-ram-mb 16384 \
  --vm-disk-gb 200
```

**Verification:**
- VM should be running: `sudo virsh domstate <hostname>-vm`
- SSH should work: `ssh -i ~/.ssh/vm_id_rsa ubuntu@192.168.30.18`
- Check networks: `ssh -i ~/.ssh/vm_id_rsa ubuntu@192.168.30.18 "ip addr"``

---

### Step 3: Arc Enable VM
**Script:** `step3-arc-enable-vm.sh`

**Purpose:** Connects the virtual machine to Azure Arc.

**What it does:**
- Connects to VM via SSH
- Installs Azure CLI on VM
- Installs Azure Connected Machine agent on VM
- Connects VM to Azure Arc with appropriate tags (Role=VM)
- Configures SSH and Microsoft Entra login
- Applies security hardening

**Run on:** Ubuntu host (connects to VM via SSH)

**Usage:**
```bash
./step3-arc-enable-vm.sh \
  --service-principal-id <SERVICE_PRINCIPAL_ID> \
  --service-principal-secret <SERVICE_PRINCIPAL_CLIENT_SECRET> \
  --subscription-id <SUBSCRIPTION_ID> \
  --tenant-id <TENANT_ID> \
  --location <LOCATION> \
  --data-center <DATA_CENTER> \
  --city <CITY> \
  --state-region <STATE_REGION> \
  --country <COUNTRY>
```

**Example:**
```bash
chmod +x step3-arc-enable-vm.sh
./step3-arc-enable-vm.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-service-principal-secret" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --location "eastus2" \
  --data-center "CHI" \
  --city "Chicago" \
  --state-region "IL" \
  --country "US"
```

**Note:** Resource group will be automatically derived as `EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG`

**Verification:**
- Check Azure Portal for second Arc-enabled server (name: `<hostname>-vm`)
- Both host and VM should appear as Arc-enabled servers

---

### Step 4: Install k3s and Arc Enable Kubernetes
**Script:** `step4-install-k3s-on-vm.sh`

**Purpose:** Installs k3s on the VM and connects it to Azure Arc as a Kubernetes cluster.

**What it does:**
- Connects to VM via SSH
- Installs k3s Kubernetes
- Configures kubectl
- Sets system limits for k3s
- Connects k3s cluster to Azure Arc
- Enables IoT Operations features (custom locations, cluster connect)
- Configures OIDC issuer for workload identity
- Restarts k3s with new configuration

**Run on:** Ubuntu host (connects to VM via SSH)

**Usage:**
```bash
./step4-install-k3s-on-vm.sh \
  --service-principal-id <SERVICE_PRINCIPAL_ID> \
  --service-principal-secret <SERVICE_PRINCIPAL_CLIENT_SECRET> \
  --subscription-id <SUBSCRIPTION_ID> \
  --tenant-id <TENANT_ID> \
  --location <LOCATION> \
  --data-center <DATA_CENTER> \
  --country <COUNTRY>
```

**Example:**
```bash
chmod +x step4-install-k3s-on-vm.sh
./step4-install-k3s-on-vm.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-service-principal-secret" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --location "eastus2" \
  --data-center "CHI" \
  --country "US"
```

**Note:** Resource group will be automatically derived as `EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG`

**Verification:**
- Check Azure Portal for Arc-enabled Kubernetes cluster (name: `<datacenter>-<hostname>-vm-k3s`)
- SSH to VM and check: `ssh -i ~/.ssh/vm_id_rsa ubuntu@192.168.30.18 "kubectl get nodes"``

---

### Step 5: Deploy Azure IoT Operations
**Script:** `step5-iot-operations-deployment.sh`

**Purpose:** Deploys Azure IoT Operations on the k3s cluster.

**What it does:**
- Creates Azure resources (Key Vault, Storage, Schema Registry, Namespace)
- Initializes IoT Operations on the cluster
- Creates IoT Operations instance
- Configures managed identities and secret sync
- Grants Event Hub permissions

**Run on:** Ubuntu host (manages Azure resources and connects to VM)

**Usage:**
```bash
./step5-iot-operations-deployment.sh \
  --service-principal-id <SERVICE_PRINCIPAL_ID> \
  --service-principal-secret <SERVICE_PRINCIPAL_CLIENT_SECRET> \
  --subscription-id <SUBSCRIPTION_ID> \
  --tenant-id <TENANT_ID> \
  --location <LOCATION> \
  --data-center <DATA_CENTER> \
  --country <COUNTRY>
```

**Example:**
```bash
chmod +x step5-iot-operations-deployment.sh
./step5-iot-operations-deployment.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-service-principal-secret" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --location "eastus2" \
  --data-center "CHI" \
  --country "US"
```

**Note:** 
- Resource group will be automatically derived as `EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG`
- This step takes 10-15 minutes to complete

**Verification:**
- Check Azure Portal for IoT Operations instance
- SSH to VM: `ssh -i ~/.ssh/vm_id_rsa ubuntu@192.168.30.18`
- Check pods: `kubectl get pods -n azure-iot-operations`

---

### Step 6: Configure Beckhoff Controller
**Script:** `step6-beckhoff-controller-deployment.sh`

**Purpose:** Configures the Beckhoff CX51x0 PLC as an OPC UA asset.

**What it does:**
- Creates IoT Operations device for Beckhoff controller
- Creates OPC UA endpoint (opc.tcp://192.168.30.11:4840)
- Creates OPC UA asset
- Adds dataset with 3 datapoints:
  - FanSpeed (ns=4;s=MAIN.nFan)
  - Temperature (ns=4;s=MAIN.nTemperature)
  - IsLampOn (ns=4;s=MAIN.bLamp)
- Creates Event Hub endpoint
- Creates dataflow to send data to Event Hub

**Run on:** Ubuntu host (connects to VM via SSH)

**Usage:**
```bash
./step6-beckhoff-controller-deployment.sh \
  --service-principal-id <SERVICE_PRINCIPAL_ID> \
  --service-principal-secret <SERVICE_PRINCIPAL_CLIENT_SECRET> \
  --subscription-id <SUBSCRIPTION_ID> \
  --tenant-id <TENANT_ID> \
  --location <LOCATION> \
  --data-center <DATA_CENTER> \
  --country <COUNTRY>
```

**Example:**
```bash
chmod +x step6-beckhoff-controller-deployment.sh
./step6-beckhoff-controller-deployment.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-service-principal-secret" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --location "eastus2" \
  --data-center "CHI" \
  --country "US"
```

**Note:** Resource group will be automatically derived as `EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG`

**Verification:**
- Check Azure Portal -> IoT Operations instance -> Assets
- Should see `beckhoff-controller` asset with 3 datapoints
- Data should flow to Event Hub (check Event Hub metrics)

---

### Step 7: Configure Leuze Controller
**Script:** `step7-leuze-controller-deployment.sh`

**Purpose:** Configures the Leuze BCL300i barcode scanner as an OPC UA asset.

**What it does:**
- Creates IoT Operations device for Leuze controller
- Creates OPC UA endpoint (opc.tcp://192.168.30.21:4840)
- Creates OPC UA asset
- Adds dataset with 6 datapoints:
  - LastReadBarcode
  - LastReadBarcodeAngle
  - LastReadBarcodeQuality
  - ReadingGatesCounter
  - ReadingGatesPerMinute
  - Temperature
- Creates Event Hub endpoint
- Creates dataflow to send data to Event Hub

**Run on:** Ubuntu host (connects to VM via SSH)

**Usage:**
```bash
./step7-leuze-controller-deployment.sh \
  --service-principal-id <SERVICE_PRINCIPAL_ID> \
  --service-principal-secret <SERVICE_PRINCIPAL_CLIENT_SECRET> \
  --subscription-id <SUBSCRIPTION_ID> \
  --tenant-id <TENANT_ID> \
  --location <LOCATION> \
  --data-center <DATA_CENTER> \
  --country <COUNTRY>
```

**Example:**
```bash
chmod +x step7-leuze-controller-deployment.sh
./step7-leuze-controller-deployment.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-service-principal-secret" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --location "eastus2" \
  --data-center "CHI" \
  --country "US"
```

**Note:** Resource group will be automatically derived as `EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG`

**Verification:**
- Check Azure Portal -> IoT Operations instance -> Assets
- Should see `leuze-controller` asset with 6 datapoints
- Data should flow to Event Hub (check Event Hub metrics)

---

## Deployment Sequence

**IMPORTANT:** Execute scripts in order:

0. **step0-configure-host-networking.sh** - Configure network interfaces (FIRST!)
1. **step1-arc-enable-host.sh** - Arc enable the host
2. **step2-create-vm.sh** - Create virtual machine
3. **step3-arc-enable-vm.sh** - Arc enable the VM
4. **step4-install-k3s-on-vm.sh** - Install k3s and Arc enable cluster
5. **step5-iot-operations-deployment.sh** - Deploy IoT Operations
6. **step6-beckhoff-controller-deployment.sh** - Configure Beckhoff asset (optional)
7. **step7-leuze-controller-deployment.sh** - Configure Leuze asset (optional)

**Total Estimated Time:** 50-65 minutes

## SSH Access

### Host
```bash
# Via Azure Arc (from anywhere)
az ssh arc --resource-group <RESOURCE_GROUP> --name <hostname>

# Direct SSH (if on same network)
ssh <user>@<host-ip>
```

### VM
```bash
# From host
ssh -i ~/.ssh/vm_id_rsa ubuntu@192.168.30.18

# Via Azure Arc (from anywhere)
az ssh arc --resource-group <RESOURCE_GROUP> --name <hostname>-vm
```

## Useful Commands

### VM Management (on host)
```bash
# Check VM status
sudo virsh domstate <hostname>-vm

# Start VM
sudo virsh start <hostname>-vm

# Stop VM gracefully
sudo virsh shutdown <hostname>-vm

# Force stop VM
sudo virsh destroy <hostname>-vm

# Access VM console
sudo virsh console <hostname>-vm

# List all VMs
sudo virsh list --all

# Delete VM (does not delete disk)
sudo virsh undefine <hostname>-vm
```

### Kubernetes (on VM)
```bash
# Get nodes
kubectl get nodes

# Get all pods in IoT Operations namespace
kubectl get pods -n azure-iot-operations

# Get all namespaces
kubectl get namespaces

# View logs for a pod
kubectl logs <pod-name> -n azure-iot-operations

# Describe a pod
kubectl describe pod <pod-name> -n azure-iot-operations
```

### Network (on host)
```bash
# Check bridge status
ip addr show br-it
ip addr show br-ot

# List libvirt networks
sudo virsh net-list --all

# View bridge configuration
sudo virsh net-dumpxml br-it
sudo virsh net-dumpxml br-ot
```

## Troubleshooting

### VM Won't Start
```bash
# Check libvirtd status
sudo systemctl status libvirtd

# Check VM configuration
sudo virsh dumpxml <hostname>-vm

# View VM logs
sudo virsh console <hostname>-vm
```

### Can't SSH to VM
```bash
# Check VM is running
sudo virsh domstate <hostname>-vm

# Check network bridges
ip addr show br-it
ip addr show br-ot

# Try pinging VM
ping 192.168.30.18

# Check cloud-init status on VM (via console)
sudo virsh console <hostname>-vm
# Then on VM: cloud-init status
```

### IoT Operations Pods Not Running
```bash
# SSH to VM
ssh -i ~/.ssh/vm_id_rsa ubuntu@192.168.30.18

# Check pod status
kubectl get pods -n azure-iot-operations

# Check pod logs
kubectl logs <failing-pod> -n azure-iot-operations

# Check events
kubectl get events -n azure-iot-operations --sort-by='.lastTimestamp'
```

### OPC UA Connection Issues
- Verify OPC UA server is reachable from VM:
  ```bash
  # On VM
  nc -zv 192.168.30.21 4840
  ```
- Check firewall rules on OPC UA device
- Verify OT network bridge is working
- Check asset endpoint configuration in Azure Portal

## Differences from V1

| Aspect | V1 | V2 |
|--------|----|----|
| Deployment Target | Direct on host | VM on host |
| Arc Resources | 1 server + 1 cluster | 2 servers + 1 cluster |
| Isolation | None | VM provides isolation |
| Networking | Direct host NICs | Bridged networks |
| k3s Location | Host | VM |
| IoT Ops Location | Host | VM |
| SSH Keys | Not managed | Retrieved from Key Vault |
| VM Management | N/A | KVM/virsh |
| Resource Flexibility | Fixed | Configurable (CPU/RAM/Disk) |

## Resource Naming Convention

All resources follow this naming pattern:

- **Cluster:** `<datacenter>-<hostname>-vm-k3s`
- **Key Vault:** `<datacenter>-<hostname>-vm-kv`
- **Storage Account:** `<datacenter><hostname>vmsa` (alphanumeric only)
- **Registry:** `<datacenter><hostname>vmregistry`
- **IoT Instance:** `<datacenter>-<hostname>-vm-aio-instance`
- **IoT Namespace:** `<datacenter>-<hostname>-vm-aio-namespace`
- **Managed Identity:** `<datacenter>-<hostname>-vm-uami`

Example for hostname `iot-wall-01` in Chicago datacenter:
- Cluster: `chi-iot-wall-01-vm-k3s`
- IoT Instance: `chi-iot-wall-01-vm-aio-instance`

## Security Considerations

- Service Principal credentials should be stored securely (e.g., in Azure Key Vault)
- SSH keys are retrieved from Azure Key Vault
- Private key permissions are set to 600
- VMs use key-based authentication only (password auth disabled)
- Security hardening is applied per SFI requirements
- Network segmentation between IT and OT networks
- Role-based tags applied to Arc resources

## Additional Configuration

### Adding More OPC UA Assets
You can create additional asset configuration scripts based on the existing controller deployment scripts:

1. Copy step6 or step7 script as a template
2. Modify device/endpoint/asset details
3. Update OPC UA server address
4. Modify datapoint node IDs
5. Update dataflow configuration
6. Run the new script after step 5

### Available Controller Scripts
- **step6-beckhoff-controller-deployment.sh**: Beckhoff CX51x0 PLC at 192.168.30.11:4840
- **step7-leuze-controller-deployment.sh**: Leuze BCL300i barcode scanner at 192.168.30.21:4840

### Customizing VM Resources
Before running step2, set these environment variables:

```bash
export VM_CPUS="8"          # Increase CPU count
export VM_RAM_MB="16384"    # 16 GB RAM
export VM_DISK_GB="200"     # 200 GB disk
```

## Uninstalling

### Uninstall Script
**Script:** `uninstall.sh`

**Purpose:** Removes the VM and most Azure resources created during deployment. Designed to allow redeployment while keeping the host Arc-enabled.

**What it does:**
- Disconnects and removes Arc-enabled k3s cluster
- Disconnects and removes VM from Azure Arc
- Deletes Key Vault (soft delete, recoverable for 90 days)
- Deletes Storage Account
- Stops and deletes the VM on the host
- Removes the VM disk from `/data`
- Optionally removes network bridges

**What it does NOT do:**
- Delete the Azure Resource Group
- Remove the host from Azure Arc
- Delete Azure IoT Operations instance (must be deleted manually via Azure Portal)
- Delete Schema Registry
- Delete User Assigned Managed Identity

**Usage Examples:**

```bash
# Basic uninstall (removes k3s cluster, VM, Key Vault, Storage Account)
./uninstall.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-secret-here" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --data-center "CHI" \
  --country "US"

# Uninstall with network cleanup
./uninstall.sh \
  --service-principal-id "12345678-1234-1234-1234-123456789abc" \
  --service-principal-secret "your-secret-here" \
  --subscription-id "12345678-1234-1234-1234-123456789abc" \
  --tenant-id "12345678-1234-1234-1234-123456789abc" \
  --data-center "CHI" \
  --country "US" \
  --delete-network-bridges

# Local VM cleanup only (skip Azure Arc cleanup)
./uninstall.sh \
  --data-center "CHI" \
  --country "US" \
  --skip-azure-cleanup
```

**Available Options:**
- `--delete-network-bridges`: Removes br-it and br-ot network bridges (default: keeps bridges)
- `--skip-azure-cleanup`: Only delete local VM, skip all Azure resource cleanup

**Warning:** The uninstall script will permanently delete the VM, its disk, and Azure resources. It will prompt for confirmation before proceeding.

**Manual Cleanup Required:**
After running the uninstall script, you may want to manually delete:

**Via Azure Portal or CLI:**
- Azure IoT Operations instance (if deployed)
- Schema Registry (if created)
- User Assigned Managed Identity
- The entire Resource Group (if you want to start completely fresh)

**To purge Key Vault permanently (removes soft-deleted vault):**
```bash
az keyvault purge --name "<datacenter>-<hostname>-vm-kv"
```

**To delete the entire resource group:**
```bash
az group delete --name "EXP-MFG-AIO-CHI-US-RG" --yes
```

**Redeployment After Uninstall:**
After running the uninstall script, you can redeploy by starting from step 2 (create-vm.sh) since the host remains Arc-enabled. This makes it easy to test different configurations or recover from failed deployments.

## Support and Maintenance

### Backup Considerations
- VM disk is stored at `/data/<hostname>-vm.qcow2`
- Consider backing up VM disk regularly
- Azure IoT Operations configuration is stored in Azure (recoverable)
- SSH keys are stored in Azure Key Vault

### Updates
- Host OS updates: Standard Ubuntu update process
- VM OS updates: SSH to VM and run `sudo apt update && sudo apt upgrade`
- k3s updates: Manual process (update `INSTALL_K3S_VERSION` variable)
- IoT Operations updates: Managed through Azure

## References

- [Azure Arc Documentation](https://docs.microsoft.com/en-us/azure/azure-arc/)
- [Azure IoT Operations Documentation](https://docs.microsoft.com/en-us/azure/iot-operations/)
- [k3s Documentation](https://docs.k3s.io/)
- [KVM Documentation](https://www.linux-kvm.org/)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
