#! /bin/bash
export RED='\e[31m'
export YELLOW='\e[33m'
export GREEN='\e[32m'
export RESET='\e[0m'

# BE AWARE: WHEN YOU RUN THIS SCRIPT, IT WILL KICK YOUR CURRENT SSH SESSION OUT DUE TO NETWORK RECONFIGURATION
# YOU MAY GET A NEW IP ADDRESS ALL TOGETHER

# Usage function
usage() {
    cat <<EOF
${YELLOW}Usage: $0 --it-mac <IT_NETWORK_MAC_ADDRESS> --ot-mac <OT_NETWORK_MAC_ADDRESS>${RESET}

${GREEN}Required Arguments:${RESET}
  --it-mac    : MAC address for IT network interface (eth1)
  --ot-mac    : MAC address for OT network interface (eth2)

${GREEN}Example:${RESET}
  $0 --it-mac 00:15:5d:01:23:45 --ot-mac 00:15:5d:01:23:46

${YELLOW}Note: You can run 'ifconfig -a' or 'ip link show' to see the MAC addresses of the network interfaces.${RESET}
EOF
    exit 1
}

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --it-mac)
            IT_NETWORK_MAC_ADDRESS="$2"
            shift 2
            ;;
        --ot-mac)
            OT_NETWORK_MAC_ADDRESS="$2"
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
if [ -z "${IT_NETWORK_MAC_ADDRESS}" ] || [ -z "${OT_NETWORK_MAC_ADDRESS}" ]; then
    echo -e "${RED}Error: Missing required arguments${RESET}"
    usage
fi

export IT_NETWORK_MAC_ADDRESS
export OT_NETWORK_MAC_ADDRESS


echo -e "${GREEN}======================================================================================================"
echo -e "Step 15........Configuring Network Interfaces (eth1 for IT, eth2 for OT)"
echo -e "======================================================================================================${RESET}"

# Create udev rules to rename network interfaces based on MAC addresses
echo "Creating udev rules for network interface naming..."
sudo tee /etc/udev/rules.d/10-network-naming.rules > /dev/null <<EOF
# IT Network Interface - rename to eth1
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${IT_NETWORK_MAC_ADDRESS}", NAME="eth1"

# OT Network Interface - rename to eth2
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${OT_NETWORK_MAC_ADDRESS}", NAME="eth2"
EOF

# Create netplan configuration for the renamed interfaces
echo "Configuring netplan for eth1 and eth2..."
sudo tee /etc/netplan/99-custom-network.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth1:
      dhcp4: true
      dhcp6: false
      match:
        macaddress: ${IT_NETWORK_MAC_ADDRESS}
      set-name: eth1
    eth2:
      addresses:
        - 192.168.30.15/24
      dhcp4: false
      dhcp6: false
      match:
        macaddress: ${OT_NETWORK_MAC_ADDRESS}
      set-name: eth2
      optional: true
EOF

# Apply the udev rules
echo "Applying udev rules..."
sudo udevadm control --reload-rules
sudo udevadm trigger

# Apply netplan configuration
echo "Applying netplan configuration..."
sudo netplan apply

# Display current network interfaces
echo -e "${GREEN}Current network interfaces:${RESET}"
ip link show

echo -e "${GREEN}Network interface configuration completed.${RESET}"