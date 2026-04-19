# Azure IoT Operations Deployment Scripts

This repository contains automated deployment scripts for Azure IoT Operations on Ubuntu hosts. Two deployment approaches are available, each suited for different use cases and requirements.

## 📁 Repository Structure

```
inno-hub-iot-wall-deployment/
├── README.md                    # This file
├── LICENSE
├── v1/                          # Version 1: Direct deployment on host
│   ├── README.md
│   ├── step1-fix-networking.sh
│   ├── step2-iot-operations-onboarding.sh
│   ├── step3-iot-operations-deployment.sh
│   └── step4-leuze-controller-deployment.sh
└── v2/                          # Version 2: VM-based deployment
    ├── README.md
    ├── step0-configure-host-networking.sh
    ├── step1-arc-enable-host.sh
    ├── step2-create-vm.sh
    ├── step3-arc-enable-vm.sh
    ├── step4-install-k3s-on-vm.sh
    ├── step5-iot-operations-deployment.sh
    ├── step6-beckhoff-controller-deployment.sh
    └── step7-leuze-controller-deployment.sh
```

## 🔄 Version Comparison

### Version 1: Direct Deployment on Host
**Simple, fast deployment directly on the Ubuntu host**

```
┌─────────────────────────────────────────┐
│ Ubuntu Host (Arc Enabled)               │
│ - IT Network + OT Network               │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ k3s Kubernetes (Arc Enabled)      │  │
│  │                                   │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │ Azure IoT Operations        │  │  │
│  │  │ - OPC UA Assets             │  │  │
│  │  │ - Data Flows                │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### Version 2: VM-Based Deployment
**Isolated deployment with VM providing flexibility and separation**

```
┌─────────────────────────────────────────────────┐
│ Ubuntu Host (Arc Enabled)                       │
│ - IT Network + OT Network                       │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │ Virtual Machine (Arc Enabled)             │  │
│  │ - Bridged Networks (IT + OT)              │  │
│  │                                           │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │ k3s Kubernetes (Arc Enabled)        │  │  │
│  │  │                                     │  │  │
│  │  │  ┌───────────────────────────────┐  │  │  │
│  │  │  │ Azure IoT Operations          │  │  │  │
│  │  │  │ - OPC UA Assets               │  │  │  │
│  │  │  │ - Data Flows                  │  │  │  │
│  │  │  └───────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

## 📊 Feature Comparison

| Feature | V1 (Direct) | V2 (VM-Based) |
|---------|-------------|---------------|
| **Deployment Target** | Host OS directly | Virtual Machine on host |
| **Number of Scripts** | 4 | 8 |
| **Arc-Enabled Resources** | 1 server + 1 cluster | 2 servers + 1 cluster |
| **Isolation Level** | None | VM-level isolation |
| **Network Configuration** | Direct host NICs | Bridged networks |
| **k3s Location** | Host OS | VM |
| **IoT Operations Location** | Host OS | VM |
| **Complexity** | ⭐⭐ Simple | ⭐⭐⭐⭐ More Complex |
| **Setup Time** | ~30-40 minutes | ~50-65 minutes |
| **Minimum CPU** | 4 cores | 8 cores (4 for VM) |
| **Minimum RAM** | 8 GB | 16 GB (8 GB for VM) |
| **Minimum Disk** | 100 GB | 200 GB |
| **Resource Flexibility** | Fixed | Configurable (VM CPU/RAM/Disk) |
| **Backup/Recovery** | Full host rebuild | VM snapshot/restore |
| **Host Impact** | Direct workload on host | Minimal (only VM overhead) |
| **SSH Key Management** | Manual | Azure Key Vault |
| **VM Management** | N/A | KVM/virsh |

## 🎯 When to Use Each Version

### ✅ Use V1 (Direct Deployment) When:
- You want the **simplest and fastest** deployment
- You have a **dedicated physical machine** for IoT Operations
- You **don't need VM-level isolation** between host and workloads
- You want to **minimize resource overhead**
- You're deploying to **resource-constrained edge devices**
- You want a **straightforward maintenance** model
- The host is **exclusively for IoT Operations**

**Best for:** Quick demos, proof-of-concepts, dedicated edge devices, simple deployments

### ✅ Use V2 (VM-Based Deployment) When:
- You need **isolation** between host and IoT workloads
- You want **flexibility** to adjust VM resources (CPU/RAM/Disk)
- You need **easy backup/restore** capabilities (VM snapshots)
- You want to **test different configurations** without affecting the host
- You plan to run **multiple environments** on one physical host
- You need **better disaster recovery** options
- You want **centralized SSH key management** via Azure Key Vault
- The host is **shared** with other workloads

**Best for:** Production deployments, multi-tenant scenarios, environments requiring isolation, testing/development

## 🚀 Quick Start

### Prerequisites (Both Versions)
- Ubuntu Server 24.04.3 LTS
- Azure subscription
- Service Principal with appropriate permissions
- Two network interfaces (IT and OT networks)
- Console/KVM access (network reconfiguration required)

### V1 Quick Start
```bash
cd v1

# Step 1: Configure networking
./step1-fix-networking.sh --it-mac "aa:bb:cc:dd:ee:ff" --ot-mac "11:22:33:44:55:66"

# Step 2: Deploy IoT Operations
./step2-iot-operations-onboarding.sh \
  --sp-id "..." --sp-secret "..." --subscription-id "..." --tenant-id "..." \
  --location "eastus2" --data-center "CHI" --city "Chicago" \
  --state-region "IL" --country "US"

# Step 3: Configure Beckhoff controller (optional)
./step3-iot-operations-deployment.sh \
  --sp-id "..." --sp-secret "..." --subscription-id "..." --tenant-id "..." \
  --location "eastus2" --data-center "CHI" --country "US"

# Step 4: Configure Leuze controller (optional)
./step4-leuze-controller-deployment.sh \
  --sp-id "..." --sp-secret "..." --subscription-id "..." --tenant-id "..." \
  --location "eastus2" --data-center "CHI" --country "US"
```

### V2 Quick Start
```bash
cd v2

# Step 0: Configure host networking
./step0-configure-host-networking.sh --it-mac "aa:bb:cc:dd:ee:ff" --ot-mac "11:22:33:44:55:66"

# Step 1: Arc enable host
./step1-arc-enable-host.sh \
  --service-principal-id "..." --service-principal-secret "..." \
  --subscription-id "..." --tenant-id "..." --location "eastus2" \
  --data-center "CHI" --city "Chicago" --state-region "IL" --country "US"

# Step 2: Create VM
./step2-create-vm.sh \
  --service-principal-id "..." --service-principal-secret "..." \
  --subscription-id "..." --tenant-id "..." \
  --keyvault-name "my-keyvault" --ssh-key-secret "vm-private-key" \
  --ssh-pub-key-secret "vm-public-key" --it-interface "eth1" --ot-interface "eth2"

# Step 3: Arc enable VM
./step3-arc-enable-vm.sh \
  --service-principal-id "..." --service-principal-secret "..." \
  --subscription-id "..." --tenant-id "..." --location "eastus2" \
  --data-center "CHI" --city "Chicago" --state-region "IL" --country "US"

# Step 4: Install k3s on VM
./step4-install-k3s-on-vm.sh \
  --service-principal-id "..." --service-principal-secret "..." \
  --subscription-id "..." --tenant-id "..." --location "eastus2" \
  --data-center "CHI" --country "US"

# Step 5: Deploy IoT Operations
./step5-iot-operations-deployment.sh \
  --service-principal-id "..." --service-principal-secret "..." \
  --subscription-id "..." --tenant-id "..." --location "eastus2" \
  --data-center "CHI" --country "US"

# Step 6: Configure Beckhoff controller (optional)
./step6-beckhoff-controller-deployment.sh \
  --service-principal-id "..." --service-principal-secret "..." \
  --subscription-id "..." --tenant-id "..." --location "eastus2" \
  --data-center "CHI" --country "US"

# Step 7: Configure Leuze controller (optional)
./step7-leuze-controller-deployment.sh \
  --service-principal-id "..." --service-principal-secret "..." \
  --subscription-id "..." --tenant-id "..." --location "eastus2" \
  --data-center "CHI" --country "US"
```

## 📝 Network Configuration

### V1 Network Settings
- **Host IT Network (eth1):** DHCP
- **Host OT Network (eth2):** 192.168.30.15/24 (static)

### V2 Network Settings
- **Host IT Network (eth1):** DHCP
- **Host OT Network (eth2):** 192.168.30.17/24 (static)
- **VM IT Network (enp1s0):** DHCP via br-it bridge
- **VM OT Network (enp2s0):** 192.168.30.18/24 (static) via br-ot bridge

### OPC UA Devices (Both Versions)
- **Beckhoff CX51x0:** 192.168.30.11:4840
- **Leuze BCL300i:** 192.168.30.21:4840

## 🔐 Security Features (Both Versions)

- Azure Arc-enabled server management
- Microsoft Entra ID SSH login
- Service Principal authentication
- Role-based access control (RBAC)
- Security hardening (SFI requirements)
- Network segmentation (IT/OT isolation)
- V2 adds: SSH key management via Azure Key Vault

## 📚 Detailed Documentation

- [V1 Detailed README](./v1/README.md) - Complete documentation for direct deployment
- [V2 Detailed README](./v2/README.md) - Complete documentation for VM-based deployment

## 🏷️ Resource Naming Convention

Both versions automatically create resource names based on your location:

**Resource Group:** `EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG`
- Example: `EXP-MFG-AIO-CHI-US-RG` (Chicago, US)

**Other Resources:** `${DATA_CENTER}-${HOSTNAME}-${SUFFIX}`
- V1 Example: `chi-iot-wall-01-k3s` (cluster)
- V2 Example: `chi-iot-wall-01-vm-k3s` (cluster)

## 🆘 Support

### Troubleshooting
- Check individual README files for version-specific troubleshooting
- Verify all prerequisites are met
- Ensure network connectivity to OT devices
- Check Azure Arc agent status
- Review k3s and IoT Operations pod logs

### Common Issues
1. **Network disconnection during step1/step0:** Expected - reconnect with new IP
2. **SSH key issues (V2):** Ensure keys exist in Azure Key Vault
3. **VM won't start (V2):** Check libvirtd service and VM configuration
4. **IoT Ops pods not running:** Wait 10-15 minutes, check pod logs

## 📖 References

- [Azure Arc Documentation](https://docs.microsoft.com/en-us/azure/azure-arc/)
- [Azure IoT Operations Documentation](https://docs.microsoft.com/en-us/azure/iot-operations/)
- [k3s Documentation](https://docs.k3s.io/)
- [Ubuntu Netplan Documentation](https://netplan.io/)
- [KVM Documentation](https://www.linux-kvm.org/) (V2 only)

## 📄 License

See [LICENSE](./LICENSE) file for details.

## 🤝 Contributing

This is an internal deployment automation repository. For questions or issues, please contact the MTC team.

---

**Recommendation:** Start with **V1** for initial testing and proof-of-concept. Move to **V2** for production deployments requiring isolation and flexibility.
