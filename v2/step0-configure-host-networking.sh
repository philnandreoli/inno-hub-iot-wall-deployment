#!/bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# ============================================================================
# Configure Host Networking - Step 0
# ============================================================================
# This script configures the network interfaces on the Ubuntu host.
# It MUST be run BEFORE Arc enabling the host.
#
# WARNING: This script will reconfigure your network interfaces and will
# likely disconnect your current SSH session. You may receive a new IP
# address after the configuration is applied.
#
# Prerequisites:
# - Ubuntu Server 24.04.3 LTS
# - Two network interfaces (IT and OT)
# - Physical access or console access (in case SSH is lost)
#
# Usage:
#   ./step0-configure-host-networking.sh \
#     --it-network-mac <mac-address> \
#     --ot-network-mac <mac-address>
#
# Example:
#   ./step0-configure-host-networking.sh \
#     --it-network-mac "aa:bb:cc:dd:ee:ff" \
#     --ot-network-mac "11:22:33:44:55:66"
# ============================================================================

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required Options:"
    echo "  --it-network-mac MAC     MAC address of IT network interface"
    echo "  --ot-network-mac MAC     MAC address of OT network interface"
    echo ""
    echo "Optional Options:"
    echo "  --ot-network-ip IP       Static IP for OT network (default: 192.168.30.17)"
    echo "  --ot-network-netmask N   Netmask for OT network (default: 24)"
    echo "  -h, --help               Display this help message"
    echo ""
    echo "Note: Arguments can be provided via command-line or environment variables."
    echo "      Command-line arguments take precedence over environment variables."
    echo ""
    echo "To find MAC addresses, run: ip link show"
    exit 1
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --it-network-mac)
            ARG_IT_NETWORK_MAC_ADDRESS="$2"
            shift 2
            ;;
        --ot-network-mac)
            ARG_OT_NETWORK_MAC_ADDRESS="$2"
            shift 2
            ;;
        --ot-network-ip)
            ARG_OT_NETWORK_HOST_IP="$2"
            shift 2
            ;;
        --ot-network-netmask)
            ARG_OT_NETWORK_NETMASK="$2"
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
export IT_NETWORK_MAC_ADDRESS="${ARG_IT_NETWORK_MAC_ADDRESS:-${IT_NETWORK_MAC_ADDRESS}}"
export OT_NETWORK_MAC_ADDRESS="${ARG_OT_NETWORK_MAC_ADDRESS:-${OT_NETWORK_MAC_ADDRESS}}"
export OT_NETWORK_HOST_IP="${ARG_OT_NETWORK_HOST_IP:-${OT_NETWORK_HOST_IP:-192.168.30.17}}"
export OT_NETWORK_NETMASK="${ARG_OT_NETWORK_NETMASK:-${OT_NETWORK_NETMASK:-24}}"

echo -e "${GREEN}======================================================================================================"
echo -e " Configure Host Networking - Configuration Summary"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}IT Network MAC: ${IT_NETWORK_MAC_ADDRESS}${RESET}"
echo -e "${GREEN}OT Network MAC: ${OT_NETWORK_MAC_ADDRESS}${RESET}"
echo -e "${GREEN}OT Network IP: ${OT_NETWORK_HOST_IP}/${OT_NETWORK_NETMASK}${RESET}"
echo ""

# Validation
if [ -z "$IT_NETWORK_MAC_ADDRESS" ] || [ -z "$OT_NETWORK_MAC_ADDRESS" ]; then
    echo -e "${RED}ERROR: Required parameters are missing.${RESET}"
    echo -e "${RED}Please provide MAC addresses via command-line arguments or environment variables.${RESET}"
    echo ""
    usage
fi

echo -e "${YELLOW}======================================================================================================"
echo -e " WARNING: This script will reconfigure your network interfaces!"
echo -e " Your current SSH session will likely be disconnected."
echo -e " You may receive a new IP address from DHCP."
echo -e " Make sure you have console access or can reconnect via the new IP."
echo -e "======================================================================================================${RESET}"
echo ""

echo -e "${GREEN}======================================================================================================"
echo -e "Step 1: Creating udev Rules for Network Interface Naming"
echo -e "======================================================================================================${RESET}"

# Create udev rules to rename network interfaces based on MAC addresses
echo "Creating udev rules for network interface naming..."
sudo tee /etc/udev/rules.d/10-network-naming.rules > /dev/null <<EOF
# IT Network Interface - rename to eth1
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${IT_NETWORK_MAC_ADDRESS}", NAME="eth1"

# OT Network Interface - rename to eth2
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${OT_NETWORK_MAC_ADDRESS}", NAME="eth2"
EOF

echo -e "${GREEN}======================================================================================================"
echo -e "Step 2: Creating Netplan Configuration with Bridges"
echo -e "======================================================================================================${RESET}"

# Create netplan configuration with bridges for VM networking
echo "Configuring netplan with bridges for eth1 (br-it) and eth2 (br-ot)..."
sudo tee /etc/netplan/99-custom-network.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth1:
      dhcp4: false
      dhcp6: false
      match:
        macaddress: ${IT_NETWORK_MAC_ADDRESS}
      set-name: eth1
    eth2:
      dhcp4: false
      dhcp6: false
      match:
        macaddress: ${OT_NETWORK_MAC_ADDRESS}
      set-name: eth2
  bridges:
    br-it:
      interfaces: [eth1]
      dhcp4: true
      dhcp6: false
    br-ot:
      interfaces: [eth2]
      addresses:
        - ${OT_NETWORK_HOST_IP}/${OT_NETWORK_NETMASK}
      dhcp4: false
      dhcp6: false
EOF

echo -e "${GREEN}======================================================================================================"
echo -e "Step 3: Applying udev Rules"
echo -e "======================================================================================================${RESET}"
sudo udevadm control --reload-rules
sudo udevadm trigger

echo -e "${GREEN}======================================================================================================"
echo -e "Step 4: Configuring IP Forwarding and Bridge Settings"
echo -e "======================================================================================================${RESET}"

# Enable IP forwarding for bridge networking
echo "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-iptables=0' | sudo tee -a /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-ip6tables=0' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo -e "${GREEN}======================================================================================================"
echo -e "Step 5: Configuring NAT/Masquerading for VM Internet Access"
echo -e "======================================================================================================${RESET}"

# Install iptables-persistent to save rules across reboots
echo "Installing iptables-persistent..."
DEBIAN_FRONTEND=noninteractive sudo apt-get install -y iptables-persistent

# Configure NAT/masquerading for br-it bridge
# This allows VMs on br-it to access the internet through the host
echo "Configuring NAT for br-it bridge..."

# Get the IT network interface name (will be eth1 after udev rules apply)
IT_IFACE="eth1"

# Add masquerading rule for traffic from br-it going out eth1
sudo iptables -t nat -A POSTROUTING -o "$IT_IFACE" -j MASQUERADE
sudo iptables -A FORWARD -i br-it -o "$IT_IFACE" -j ACCEPT
sudo iptables -A FORWARD -i "$IT_IFACE" -o br-it -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save iptables rules
echo "Saving iptables rules..."
sudo netfilter-persistent save

echo -e "${GREEN}NAT/Masquerading configured for VM internet access${RESET}"

echo -e "${GREEN}======================================================================================================"
echo -e "Step 6: Disabling Network Offload Features (e1000e Hardware Hang Fix)"
echo -e "======================================================================================================${RESET}"

# Install ethtool if not present
if ! command -v ethtool &> /dev/null; then
    echo "Installing ethtool..."
    sudo apt-get update -qq
    sudo apt-get install -y ethtool
fi

# Create systemd service to disable offload features on boot
cat << 'EOF' | sudo tee /etc/systemd/system/disable-nic-offload.service
[Unit]
Description=Disable NIC offload features to prevent e1000e hardware hangs
After=network-pre.target
Before=network.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/disable-nic-offload.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Create script to disable offload features
cat << 'EOF' | sudo tee /usr/local/bin/disable-nic-offload.sh
#!/bin/bash
# Disable TCP offload features on all network interfaces to prevent e1000e hardware hangs
# This is especially important when using network bridges

for iface in $(ls /sys/class/net/ | grep -E '^(eth|ens|enp)'); do
    if [ -d "/sys/class/net/$iface" ]; then
        echo "Disabling offload features on $iface..."
        ethtool -K "$iface" tso off gso off gro off tx off rx off 2>/dev/null || true
        ethtool -K "$iface" sg off 2>/dev/null || true
        ethtool -G "$iface" rx 256 tx 256 2>/dev/null || true
    fi
done
EOF

sudo chmod +x /usr/local/bin/disable-nic-offload.sh

# Enable the service
sudo systemctl daemon-reload
sudo systemctl enable disable-nic-offload.service

# Run it now
echo "Applying offload settings to current interfaces..."
sudo /usr/local/bin/disable-nic-offload.sh

echo -e "${GREEN}======================================================================================================"
echo -e "Step 7: Applying Netplan Configuration"
echo -e "======================================================================================================${RESET}"
echo -e "${YELLOW}WARNING: Your SSH connection will likely be lost after this command!${RESET}"
sleep 3

# Apply netplan configuration
sudo netplan apply

# If we get here, the script is still running (unlikely if SSH was disconnected)
sleep 5

echo -e "${GREEN}======================================================================================================"
echo -e "Step 8: Displaying Current Network Interfaces"
echo -e "======================================================================================================${RESET}"
ip link show
echo ""
ip addr show

echo -e "${GREEN}======================================================================================================"
echo -e "Network Configuration Complete!"
echo -e "======================================================================================================${RESET}"
echo -e "${GREEN}Network interfaces and bridges have been configured:${RESET}"
echo -e "${GREEN}  br-it (IT Network): DHCP - Bridge for eth1${RESET}"
echo -e "${GREEN}  br-ot (OT Network): ${OT_NETWORK_HOST_IP}/${OT_NETWORK_NETMASK} - Bridge for eth2${RESET}"
echo ""
echo -e "${YELLOW}If your SSH session was disconnected, reconnect using:${RESET}"
echo -e "${YELLOW}  - The new DHCP IP address assigned to br-it, OR${RESET}"
echo -e "${YELLOW}  - The static IP ${OT_NETWORK_HOST_IP} (if accessible from your network)${RESET}"
echo ""
echo -e "${GREEN}Next Step: Run step1-arc-enable-host.sh to Arc enable the host.${RESET}"
