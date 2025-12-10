# Azure IoT Operations Deployment - Version 1

## Overview

Version 1 is a **direct deployment** approach where all components are installed directly on the Ubuntu host machine:
- The **Ubuntu host** is Arc-enabled
- **k3s Kubernetes** is installed directly on the host
- The **k3s cluster** is Arc-enabled
- **Azure IoT Operations** is deployed on the host's k3s cluster
- **OPC UA assets** (Beckhoff and Leuze) are configured

This approach provides a simpler deployment model with everything running on a single machine.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Ubuntu Host (24.04.3 LTS)                                   │
│ - Arc Enabled                                               │
│ - IT Network (eth1): DHCP                                   │
│ - OT Network (eth2): 192.168.30.15/24 (Static)             │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ k3s Kubernetes Cluster                               │  │
│  │ - Arc Enabled                                         │  │
│  │                                                       │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │ Azure IoT Operations                           │  │  │
│  │  │ - Schema Registry                              │  │  │
│  │  │ - IoT Operations Instance                      │  │  │
│  │  │ - OPC UA Connector                             │  │  │
│  │  │ - Dataflows to Event Hub                       │  │  │
│  │  │                                                 │  │  │
│  │  │ Assets:                                         │  │  │
│  │  │ - Beckhoff CX51x0 (192.168.30.11:4840)        │  │  │
│  │  │ - Leuze BCL300i (192.168.30.21:4840)          │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Hardware/Infrastructure
- Ubuntu Server 24.04.3 LTS
- Minimum 4 CPU cores
- Minimum 8 GB RAM
- Minimum 100 GB disk space
- Two network interfaces:
  - IT Network interface (for internet/Azure connectivity)
  - OT Network interface (for OPC UA devices)
- **Console access or KVM recommended** (network reconfiguration in step1 will disconnect SSH)

### Azure Requirements
- Azure subscription with appropriate permissions
- Service Principal with the following roles:
  - Contributor on the resource group
  - Azure Connected Machine Resource Administrator
  - Kubernetes Cluster - Azure Arc Onboarding
- Azure Resource Group (pre-created based on region)

### Network Requirements
- IT Network: DHCP enabled, internet connectivity
- OT Network: Isolated network (no gateway required)
  - Host IP: 192.168.30.15/24
- OPC UA devices should be accessible from OT network:
  - Beckhoff CX51x0 at 192.168.30.11:4840
  - Leuze BCL300i at 192.168.30.21:4840

## Azure Resources

The deployment creates the following Azure resources:

### Per Region (Pre-created)
- Resource Group
  - Americas: `EXP-MFG-AIO-RG` (eastus2)
  - EMEA: `EXP-MFG-AIO-EMEA-RG` (northeurope)
  - APAC: `EXP-MFG-AIO-AP-RG` (southeastasia)

### Per Deployment (Auto-created)
- 1 Arc-enabled Server (host)
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
export RESOURCE_GROUP="EXP-MFG-AIO-RG"
export LOCATION="eastus2"

# For EMEA
export RESOURCE_GROUP="EXP-MFG-AIO-EMEA-RG"
export LOCATION="northeurope"

# For APAC
export RESOURCE_GROUP="EXP-MFG-AIO-AP-RG"
export LOCATION="southeastasia"
```

### Innovation Hub Settings
```bash
export DATA_CENTER="CHI"        # e.g., CHI, STL, AMS
export CITY="Chicago"           # e.g., Chicago, St. Louis
export STATE_REGION="IL"        # e.g., IL, MO
export COUNTRY="US"             # 2-letter country code
```

### Network Configuration (step1-fix-networking.sh)
```bash
# Get these from `ip link show` or `ifconfig -a`
export IT_NETWORK_MAC_ADDRESS="aa:bb:cc:dd:ee:ff"
export OT_NETWORK_MAC_ADDRESS="11:22:33:44:55:66"
```

### Optional Configuration
```bash
export INSTALL_K3S_VERSION="v1.34.1+k3s1"  # k3s version
```

## Deployment Steps

### Step 1: Fix Networking
**Script:** `step1-fix-networking.sh`

**Purpose:** Configures network interfaces on the host with proper naming and IP addressing.

**What it does:**
- Creates udev rules to rename network interfaces based on MAC addresses
- Configures eth1 (IT Network) with DHCP
- Configures eth2 (OT Network) with static IP 192.168.30.15/24
- Applies netplan configuration

**Run on:** Ubuntu host (directly)

**⚠️ WARNING:** This script will reconfigure your network and will disconnect your SSH session.

**Example:**
```bash
# First, find your MAC addresses
ip link show

# Configure the script
export IT_NETWORK_MAC_ADDRESS="aa:bb:cc:dd:ee:ff"
export OT_NETWORK_MAC_ADDRESS="11:22:33:44:55:66"

# Run the script
chmod +x step1-fix-networking.sh
./step1-fix-networking.sh
```

**After Running:**
- Your SSH session will be disconnected
- Reconnect using the new DHCP IP address or static IP 192.168.30.15
- Verify interfaces: `ip addr show eth1` and `ip addr show eth2`

---

### Step 2: IoT Operations Onboarding
**Script:** `step2-iot-operations-onboarding.sh`

**Purpose:** Onboards the host to Azure Arc, installs k3s, Arc-enables the cluster, and deploys Azure IoT Operations.

**What it does:**
1. Installs Azure CLI and extensions
2. Downloads and installs Azure Connected Machine agent
3. Connects host to Azure Arc
4. Configures SSH and Microsoft Entra login
5. Applies security hardening (SFI requirements)
6. Installs k3s Kubernetes
7. Configures kubectl
8. Sets system limits for k3s
9. Connects k3s to Azure Arc
10. Enables IoT Operations features
11. Updates k3s config with OIDC issuer
12. Creates Azure resources (Key Vault, Storage Account, Schema Registry, Namespace)
13. Initializes IoT Operations cluster
14. Creates IoT Operations instance
15. Configures managed identities and secret sync
16. Grants Event Hub permissions

**Run on:** Ubuntu host (directly)

**Example:**
```bash
# Configure all environment variables
export SERVICE_PRINCIPAL_ID="..."
export SERVICE_PRINCIPAL_CLIENT_SECRET="..."
export SUBSCRIPTION_ID="..."
export TENANT_ID="..."
export RESOURCE_GROUP="EXP-MFG-AIO-RG"
export LOCATION="eastus2"
export DATA_CENTER="CHI"
export CITY="Chicago"
export STATE_REGION="IL"
export COUNTRY="US"

# Optional: specify k3s version
export INSTALL_K3S_VERSION="v1.34.1+k3s1"

# Run the script
chmod +x step2-iot-operations-onboarding.sh
./step2-iot-operations-onboarding.sh
```

**Duration:** 15-20 minutes

**Verification:**
- Check Azure Portal for Arc-enabled server (hostname)
- Check Azure Portal for Arc-enabled Kubernetes cluster
- Check Azure Portal for IoT Operations instance
- Run `kubectl get pods -n azure-iot-operations` to verify pods are running

---

### Step 3: IoT Operations Deployment (Beckhoff Controller)
**Script:** `step3-iot-operations-deployment.sh`

**Purpose:** Configures the Beckhoff CX51x0 PLC as an OPC UA asset in Azure IoT Operations.

**What it does:**
- Creates IoT Operations device for Beckhoff controller
- Creates OPC UA endpoint (opc.tcp://192.168.30.11:4840)
- Creates OPC UA asset
- Adds dataset with 3 datapoints:
  - FanSpeed (ns=4;s=MAIN.nFan)
  - Temperature (ns=4;s=MAIN.nTemperature)
  - IsLampOn (ns=4;s=MAIN.bLamp)
- Creates Event Hub endpoint
- Creates dataflow to send data to Event Hub with metadata

**Run on:** Ubuntu host (directly)

**Example:**
```bash
# Environment variables should already be set from step2
# Run the script
chmod +x step3-iot-operations-deployment.sh
./step3-iot-operations-deployment.sh
```

**Verification:**
- Check Azure Portal -> IoT Operations instance -> Assets
- Should see `beckhoff-controller` asset with 3 datapoints
- Data should flow to Event Hub

---

### Step 4: Leuze Controller Deployment
**Script:** `step4-leuze-controller-deployment.sh`

**Purpose:** Configures the Leuze BCL300i barcode scanner as an OPC UA asset in Azure IoT Operations.

**What it does:**
- Creates IoT Operations device for Leuze controller
- Creates OPC UA endpoint (opc.tcp://192.168.30.21:4840)
- Creates OPC UA asset
- Adds dataset with 6 datapoints:
  - LastReadBarcode (ns=3;i=40901)
  - LastReadBarcodeAngle (ns=3;i=40903)
  - LastReadBarcodeQuality (ns=3;i=40902)
  - ReadingGatesCounter (ns=3;i=40905)
  - ReadingGatesPerMinute (ns=3;i=40904)
  - Temperature (ns=3;i=70001)
- Creates Event Hub endpoint
- Creates dataflow to send data to Event Hub with metadata

**Run on:** Ubuntu host (directly)

**Example:**
```bash
# Environment variables should already be set
# Run the script
chmod +x step4-leuze-controller-deployment.sh
./step4-leuze-controller-deployment.sh
```

**Verification:**
- Check Azure Portal -> IoT Operations instance -> Assets
- Should see `leuze-controller` asset with 6 datapoints
- Data should flow to Event Hub

---

## Deployment Sequence

**IMPORTANT:** Execute scripts in order:

1. **step1-fix-networking.sh** - Configure network interfaces (FIRST!)
2. **step2-iot-operations-onboarding.sh** - Arc enable, install k3s, deploy IoT Ops
3. **step3-iot-operations-deployment.sh** - Configure Beckhoff asset (optional)
4. **step4-leuze-controller-deployment.sh** - Configure Leuze asset (optional)

**Total Estimated Time:** 30-40 minutes

## Useful Commands

### Network Management
```bash
# Check network interfaces
ip addr show

# Check specific interface
ip addr show eth1
ip addr show eth2

# Test connectivity
ping 192.168.30.11  # Beckhoff
ping 192.168.30.21  # Leuze
```

### Kubernetes Management
```bash
# Get nodes
kubectl get nodes

# Get all pods in IoT Operations namespace
kubectl get pods -n azure-iot-operations

# View logs for a pod
kubectl logs <pod-name> -n azure-iot-operations

# Describe a pod
kubectl describe pod <pod-name> -n azure-iot-operations

# Check k3s status
sudo systemctl status k3s
```

### Azure Arc Management
```bash
# Check Arc agent status
sudo azcmagent show

# Check Arc connection status
sudo azcmagent check

# View Arc-enabled Kubernetes cluster
az connectedk8s list -g <RESOURCE_GROUP>
```

## Troubleshooting

### Network Configuration Issues
```bash
# If network configuration fails, check netplan
sudo netplan --debug apply

# View netplan configuration
cat /etc/netplan/99-custom-network.yaml

# Check udev rules
cat /etc/udev/rules.d/10-network-naming.rules

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Arc Enablement Issues
```bash
# Check Arc agent logs
sudo journalctl -u himdsd -f

# Reconnect to Arc
sudo azcmagent connect --service-principal-id <ID> \
  --service-principal-secret <SECRET> \
  --resource-group <RG> \
  --tenant-id <TENANT> \
  --location <LOCATION> \
  --subscription-id <SUBSCRIPTION>
```

### k3s Issues
```bash
# Restart k3s
sudo systemctl restart k3s

# Check k3s logs
sudo journalctl -u k3s -f

# Check k3s status
sudo systemctl status k3s

# Verify k3s configuration
sudo cat /etc/rancher/k3s/config.yaml
```

### IoT Operations Issues
```bash
# Check IoT Ops pods
kubectl get pods -n azure-iot-operations

# Check pod logs
kubectl logs <pod-name> -n azure-iot-operations

# Check events
kubectl get events -n azure-iot-operations --sort-by='.lastTimestamp'

# Restart schema registry pods
kubectl delete pods adr-schema-registry-0 adr-schema-registry-1 -n azure-iot-operations
```

### OPC UA Connection Issues
- Verify OPC UA server is reachable:
  ```bash
  nc -zv 192.168.30.11 4840  # Beckhoff
  nc -zv 192.168.30.21 4840  # Leuze
  ```
- Check firewall rules on OPC UA devices
- Verify OT network configuration
- Check asset endpoint configuration in Azure Portal

## Resource Naming Convention

All resources follow this naming pattern:

- **Cluster:** `<datacenter>-<hostname>-k3s`
- **Key Vault:** `<datacenter>-<hostname>-kv`
- **Storage Account:** `<datacenter><hostname>sa` (alphanumeric only)
- **Registry:** `<datacenter><hostname>registry`
- **IoT Instance:** `<datacenter>-<hostname>-aio-instance`
- **IoT Namespace:** `<datacenter>-<hostname>-aio-namespace`
- **Managed Identity:** `<datacenter>-<hostname>-uami`

Example for hostname `iot-wall-01` in Chicago datacenter:
- Cluster: `chi-iot-wall-01-k3s`
- IoT Instance: `chi-iot-wall-01-aio-instance`

## Differences from V2

| Aspect | V1 | V2 |
|--------|----|----|
| Deployment Target | Direct on host | VM on host |
| Arc Resources | 1 server + 1 cluster | 2 servers + 1 cluster |
| Isolation | None | VM provides isolation |
| Networking | Direct host NICs | Bridged networks |
| k3s Location | Host | VM |
| IoT Ops Location | Host | VM |
| Scripts | 4 scripts | 8 scripts |
| Complexity | Simpler | More complex |
| Flexibility | Limited | High (configurable VM resources) |
| Recovery | Rebuild host | Rebuild VM only |

## When to Use V1

✅ **Use V1 when:**
- You want a simpler, faster deployment
- You have a dedicated physical machine for IoT Operations
- You don't need VM-level isolation
- You want to minimize resource overhead
- You're deploying to edge devices with limited resources

❌ **Consider V2 when:**
- You need isolation between host and IoT workloads
- You want flexibility to adjust VM resources
- You need to easily backup/restore the deployment (VM snapshots)
- You want to run multiple environments on one physical host
- You need to test different configurations without affecting the host

## Security Considerations

- Service Principal credentials should be stored securely (e.g., in Azure Key Vault)
- Password-based SSH is allowed (configure as needed)
- Security hardening is applied per SFI requirements
- Network segmentation between IT and OT networks
- Role-based tags applied to Arc resources

## Support and Maintenance

### Backup Considerations
- k3s configuration is stored at `/etc/rancher/k3s/`
- Azure IoT Operations configuration is stored in Azure (recoverable)
- Consider backing up important configurations regularly

### Updates
- Host OS updates: Standard Ubuntu update process (`sudo apt update && sudo apt upgrade`)
- k3s updates: Manual process (update `INSTALL_K3S_VERSION` variable and re-run installation)
- IoT Operations updates: Managed through Azure

## References

- [Azure Arc Documentation](https://docs.microsoft.com/en-us/azure/azure-arc/)
- [Azure IoT Operations Documentation](https://docs.microsoft.com/en-us/azure/iot-operations/)
- [k3s Documentation](https://docs.k3s.io/)
- [Ubuntu Netplan Documentation](https://netplan.io/)
