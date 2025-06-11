#!/bin/bash

# SSH Connectivity Test Script
# This script tests SSH connectivity to all nodes in the inventory

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
INVENTORY="inventory/hosts.yml"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

SSH Connectivity Test Script
Tests SSH connectivity to all nodes in the inventory

OPTIONS:
    -i, --inventory INVENTORY   Specify inventory file (default: inventory/hosts.yml)
    -k, --ssh-key KEY_PATH      SSH private key path (default: ~/.ssh/id_ed25519)
    -h, --help                  Show this help message

EXAMPLES:
    # Test with default settings
    $0

    # Test with custom inventory
    $0 -i custom-inventory.yml

    # Test with custom SSH key
    $0 -k ~/.ssh/custom-key

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -k|--ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_message $RED "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

print_message $BLUE "========================================="
print_message $BLUE "SSH Connectivity Test"
print_message $BLUE "========================================="

# Check if inventory file exists
if [[ ! -f "$INVENTORY" ]]; then
    print_message $RED "Error: Inventory file '$INVENTORY' not found"
    exit 1
fi

# Check if SSH key exists
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    print_message $RED "Error: SSH key file '$SSH_KEY_PATH' not found"
    print_message $YELLOW "Please generate SSH keys first using one of the setup scripts"
    exit 1
fi

print_message $GREEN "Configuration:"
print_message $GREEN "  Inventory: $INVENTORY"
print_message $GREEN "  SSH Key: $SSH_KEY_PATH"
echo

# Test connectivity using ansible
print_message $BLUE "Testing SSH connectivity to all nodes..."
echo

if ansible all -i "$INVENTORY" -m ping --private-key="$SSH_KEY_PATH" --one-line; then
    print_message $GREEN "✅ All nodes are reachable via SSH"
else
    print_message $RED "❌ Some nodes are not reachable"
    print_message $YELLOW "Troubleshooting steps:"
    print_message $YELLOW "1. Verify SSH key is properly configured on target nodes"
    print_message $YELLOW "2. Check if SSH service is running on target nodes"
    print_message $YELLOW "3. Verify network connectivity: ping <node-ip>"
    print_message $YELLOW "4. Try manual SSH connection: ssh -i $SSH_KEY_PATH root@<node-ip>"
    exit 1
fi

echo
print_message $BLUE "Testing individual node connectivity..."
echo

# Get list of nodes from inventory
nodes=$(ansible all -i "$INVENTORY" --list-hosts | grep -v "hosts" | sed 's/^[[:space:]]*//')

for node in $nodes; do
    print_message $BLUE "Testing $node..."
    
    # Get node IP
    node_ip=$(ansible "$node" -i "$INVENTORY" -m debug -a "var=ansible_host" --one-line 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    
    if [[ "$node_ip" != "unknown" ]]; then
        if timeout 10 ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$node_ip" "echo 'SSH connection successful'" >/dev/null 2>&1; then
            print_message $GREEN "  ✅ $node ($node_ip): SSH connection successful"
        else
            print_message $RED "  ❌ $node ($node_ip): SSH connection failed"
        fi
    else
        print_message $YELLOW "  ⚠️  $node: Could not determine IP address"
    fi
done

echo
print_message $GREEN "SSH connectivity test completed!" 