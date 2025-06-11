#!/bin/bash

# Add Node to Kubernetes Cluster Script
# This script adds new worker nodes to an existing Kubernetes cluster
# Updated with real-world testing experience and improved error handling

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
NEW_NODE_IP=""
NEW_NODE_NAME=""
NODE_TYPE="worker"
INVENTORY="inventory/hosts.yml"
DRY_RUN=false
VERBOSE=""
SKIP_PREPARATION=false
SSH_KEY_PATH=""

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --node-ip IP               New node IP address (required)
    --node-name NAME           New node name (required)
    --node-type TYPE           Node type: worker|master (default: worker)
    -i, --inventory INVENTORY  Specify inventory file (default: inventory/hosts.yml)
    --ssh-key PATH             SSH private key path (optional)
    --skip-preparation         Skip node preparation steps
    -d, --dry-run              Perform a dry run (check mode)
    -vv, --verbose             Verbose output
    -h, --help                 Show this help message

EXAMPLES:
    # Add a worker node
    $0 --node-ip 192.168.1.20 --node-name k8s-worker-03

    # Add a master node
    $0 --node-ip 192.168.1.21 --node-name k8s-master-02 --node-type master

    # Add worker with custom SSH key
    $0 --node-ip 192.168.1.20 --node-name k8s-worker-03 --ssh-key ~/.ssh/k8s-key

    # Dry run to check what would be changed
    $0 --node-ip 192.168.1.20 --node-name k8s-worker-03 --dry-run

PREREQUISITES:
    1. The new node should be accessible via SSH
    2. The new node should have the same OS as existing nodes
    3. The master node should be running and accessible
    4. SSH key should be configured for root access

EOF
}

# Function to test SSH connection
test_ssh_connection() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        ssh_key_option="-i $SSH_KEY_PATH"
    fi
    
    print_message $BLUE "Testing SSH connection to $node_ip..."
    
    if timeout 10 ssh $ssh_key_option -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "echo 'SSH connection successful'" >/dev/null 2>&1; then
        print_message $GREEN "✓ SSH connection successful"
        return 0
    else
        print_message $RED "✗ SSH connection failed"
        print_message $YELLOW "Troubleshooting steps:"
        print_message $YELLOW "1. Check if SSH service is running on target node:"
        print_message $YELLOW "   systemctl status sshd"
        print_message $YELLOW "2. Check if SSH key is properly configured:"
        print_message $YELLOW "   ssh-copy-id root@$node_ip"
        print_message $YELLOW "3. Test manual SSH connection:"
        print_message $YELLOW "   ssh root@$node_ip"
        return 1
    fi
}

# Function to prepare the new node
prepare_node() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        ssh_key_option="-i $SSH_KEY_PATH"
    fi
    
    print_message $BLUE "Preparing new node ($node_ip)..."
    
    # Test if we can connect and get system info
    print_message $BLUE "Getting system information..."
    if ! ssh $ssh_key_option -o ConnectTimeout=10 root@$node_ip "hostname && uname -a" 2>/dev/null; then
        print_message $RED "Cannot get system information from node"
        return 1
    fi
    
    # Prepare basic system configuration
    print_message $BLUE "Setting up basic system configuration..."
    ssh $ssh_key_option root@$node_ip "
        # Ensure SELinux config exists
        mkdir -p /etc/selinux
        if [[ ! -f /etc/selinux/config ]]; then
            echo 'SELINUX=disabled' > /etc/selinux/config
            echo 'SELinux config created'
        fi
        
        # Disable swap
        swapoff -a 2>/dev/null || true
        
        # Load required kernel modules
        modprobe overlay 2>/dev/null || true
        modprobe br_netfilter 2>/dev/null || true
        
        # Set up modules to load at boot
        mkdir -p /etc/modules-load.d
        echo 'overlay' > /etc/modules-load.d/k8s.conf
        echo 'br_netfilter' >> /etc/modules-load.d/k8s.conf
        
        # Set up sysctl parameters
        mkdir -p /etc/sysctl.d
        cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
        sysctl --system >/dev/null 2>&1 || true
        
        # Check if necessary tools are available
        echo 'Basic system preparation completed'
    " || {
        print_message $RED "Node preparation failed"
        return 1
    }
    
    print_message $GREEN "✓ Node preparation completed"
    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --node-ip)
            NEW_NODE_IP="$2"
            shift 2
            ;;
        --node-name)
            NEW_NODE_NAME="$2"
            shift 2
            ;;
        --node-type)
            NODE_TYPE="$2"
            shift 2
            ;;
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --skip-preparation)
            SKIP_PREPARATION=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -vv|--verbose)
            VERBOSE="-vv"
            shift
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

# Validate required parameters
if [[ -z "$NEW_NODE_IP" ]]; then
    print_message $RED "Error: --node-ip is required"
    show_usage
    exit 1
fi

if [[ -z "$NEW_NODE_NAME" ]]; then
    print_message $RED "Error: --node-name is required"
    show_usage
    exit 1
fi

if [[ "$NODE_TYPE" != "worker" && "$NODE_TYPE" != "master" ]]; then
    print_message $RED "Error: --node-type must be 'worker' or 'master'"
    exit 1
fi

# Validate SSH key path if provided
if [[ -n "$SSH_KEY_PATH" && ! -f "$SSH_KEY_PATH" ]]; then
    print_message $RED "Error: SSH key file '$SSH_KEY_PATH' not found"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR"

print_message $BLUE "========================================="
print_message $BLUE "Adding Node to Kubernetes Cluster"
print_message $BLUE "========================================="

# Verify inventory file exists
if [[ ! -f "$INVENTORY" ]]; then
    print_message $RED "Error: Inventory file '$INVENTORY' not found"
    exit 1
fi

print_message $GREEN "Configuration:"
print_message $GREEN "  New Node IP: $NEW_NODE_IP"
print_message $GREEN "  New Node Name: $NEW_NODE_NAME"
print_message $GREEN "  Node Type: $NODE_TYPE"
print_message $GREEN "  Inventory: $INVENTORY"
[[ -n "$SSH_KEY_PATH" ]] && print_message $GREEN "  SSH Key: $SSH_KEY_PATH"
[[ "$SKIP_PREPARATION" == true ]] && print_message $YELLOW "  Skip Preparation: Yes"
[[ "$DRY_RUN" == true ]] && print_message $YELLOW "  Mode: DRY RUN"
echo

# Test SSH connection first
if ! test_ssh_connection "$NEW_NODE_IP"; then
    exit 1
fi

# Prepare the node if not skipped
if [[ "$SKIP_PREPARATION" != true && "$DRY_RUN" != true ]]; then
    if ! prepare_node "$NEW_NODE_IP"; then
        exit 1
    fi
fi

# Check if node already exists in inventory
if grep -q "$NEW_NODE_NAME" "$INVENTORY"; then
    print_message $YELLOW "Warning: Node '$NEW_NODE_NAME' already exists in inventory"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message $YELLOW "Operation cancelled"
        exit 0
    fi
else
    # Add node to inventory
    print_message $BLUE "Adding node to inventory..."
    
    # Create backup of inventory
    cp "$INVENTORY" "${INVENTORY}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ "$NODE_TYPE" == "worker" ]]; then
        # Add to workers section
        if [[ "$DRY_RUN" != true ]]; then
            # Find the k8s_workers section and add the new node
            awk -v node_name="$NEW_NODE_NAME" -v node_ip="$NEW_NODE_IP" '
            /k8s_workers:/{
                print $0
                getline
                print $0  # print "hosts:"
                print "            " node_name ":"
                print "              ansible_host: " node_ip "  # New worker node"
                print "              ansible_user: root"
                print "              ansible_python_interpreter: /usr/bin/python3"
                print "              node_role: worker"
                next
            }
            {print}' "$INVENTORY" > "${INVENTORY}.tmp" && mv "${INVENTORY}.tmp" "$INVENTORY"
        fi
        TARGET_GROUP="k8s_workers"
    else
        # Add to masters section  
        if [[ "$DRY_RUN" != true ]]; then
            # Find the k8s_masters section and add the new node
            awk -v node_name="$NEW_NODE_NAME" -v node_ip="$NEW_NODE_IP" '
            /k8s_masters:/{
                print $0
                getline
                print $0  # print "hosts:"
                print "            " node_name ":"
                print "              ansible_host: " node_ip "  # New master node"
                print "              ansible_user: root"
                print "              ansible_python_interpreter: /usr/bin/python3"
                print "              node_role: master"
                next
            }
            {print}' "$INVENTORY" > "${INVENTORY}.tmp" && mv "${INVENTORY}.tmp" "$INVENTORY"
        fi
        TARGET_GROUP="k8s_masters"
    fi
    
    print_message $GREEN "Node added to inventory successfully"
fi

# Test connectivity to the new node using Ansible
print_message $BLUE "Testing Ansible connectivity to new node..."
ansible_cmd="ansible -i '$INVENTORY' '$NEW_NODE_NAME' -m ping"
[[ -n "$SSH_KEY_PATH" ]] && ansible_cmd="$ansible_cmd --private-key=$SSH_KEY_PATH"

if eval "$ansible_cmd" >/dev/null 2>&1; then
    print_message $GREEN "✓ Ansible connectivity successful"
else
    print_message $RED "✗ Ansible connectivity failed"
    print_message $YELLOW "Trying with SSH key authentication..."
    
    # Try to find SSH key in common locations
    possible_keys=("$HOME/.ssh/id_rsa" "/root/.ssh/id_rsa" "$HOME/.ssh/k8s-cluster")
    
    for key in "${possible_keys[@]}"; do
        if [[ -f "$key" ]]; then
            print_message $BLUE "Trying SSH key: $key"
            if ansible -i "$INVENTORY" "$NEW_NODE_NAME" -m ping --private-key="$key" >/dev/null 2>&1; then
                print_message $GREEN "✓ Ansible connectivity successful with key: $key"
                SSH_KEY_PATH="$key"
                break
            fi
        fi
    done
    
    if [[ -z "$SSH_KEY_PATH" ]]; then
        print_message $RED "Failed to establish Ansible connectivity"
        print_message $YELLOW "Please ensure SSH key is properly configured"
        exit 1
    fi
fi

# Determine which playbook to run
if [[ "$NODE_TYPE" == "worker" ]]; then
    PLAYBOOK="playbooks/k8s-cluster.yml"
    LIMIT_HOSTS="$NEW_NODE_NAME"
    TAGS="common,worker"
else
    PLAYBOOK="playbooks/k8s-cluster.yml"
    LIMIT_HOSTS="$NEW_NODE_NAME"
    TAGS="common,master"
fi

# Build ansible-playbook command
ANSIBLE_CMD="ansible-playbook -i $INVENTORY $PLAYBOOK --limit $LIMIT_HOSTS --tags $TAGS"
[[ -n "$SSH_KEY_PATH" ]] && ANSIBLE_CMD="$ANSIBLE_CMD --private-key=$SSH_KEY_PATH"
[[ "$DRY_RUN" == true ]] && ANSIBLE_CMD="$ANSIBLE_CMD --check --diff"
[[ -n "$VERBOSE" ]] && ANSIBLE_CMD="$ANSIBLE_CMD $VERBOSE"

print_message $BLUE "Executing: $ANSIBLE_CMD"
echo

# Ask for confirmation if not dry run
if [[ "$DRY_RUN" != true ]]; then
    read -p "Do you want to continue with node setup? (y/N): " -n 1 -r
    echo  
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message $YELLOW "Operation cancelled"
        exit 0
    fi
fi

# Execute the playbook
print_message $BLUE "Running Ansible playbook..."
if eval "$ANSIBLE_CMD"; then
    print_message $GREEN "✓ Ansible playbook completed successfully"
    
    # If this is a worker node, get join command and join the cluster
    if [[ "$NODE_TYPE" == "worker" && "$DRY_RUN" != true ]]; then
        print_message $BLUE "Getting cluster join command..."
        
        # Generate new token and get join command
        if command_exists kubectl; then
            JOIN_CMD=$(sudo kubeadm token create --print-join-command 2>/dev/null)
            if [[ -n "$JOIN_CMD" ]]; then
                print_message $BLUE "Joining node to cluster..."
                ssh_key_option=""
                [[ -n "$SSH_KEY_PATH" ]] && ssh_key_option="-i $SSH_KEY_PATH"
                
                if ssh $ssh_key_option root@$NEW_NODE_IP "$JOIN_CMD"; then
                    print_message $GREEN "✓ Node joined cluster successfully"
                else
                    print_message $RED "✗ Failed to join node to cluster"
                    print_message $YELLOW "You can manually join using: $JOIN_CMD"
                fi
            else
                print_message $YELLOW "Could not generate join command automatically"
                print_message $YELLOW "Please run: sudo kubeadm token create --print-join-command"
                print_message $YELLOW "Then execute the command on the new node"
            fi
        else
            print_message $YELLOW "kubectl not found - please join the node manually"
        fi
    fi
    
    print_message $GREEN "========================================="
    print_message $GREEN "Node setup completed successfully!"
    print_message $GREEN "========================================="
    
    print_message $GREEN "Next steps:"
    print_message $GREEN "1. Verify node joined: kubectl get nodes"
    print_message $GREEN "2. Check node status: kubectl describe node $NEW_NODE_NAME"
    if [[ "$NODE_TYPE" == "worker" ]]; then
        print_message $GREEN "3. Wait for node to be Ready (may take 1-2 minutes for CNI)"
        print_message $GREEN "4. Check if pods can be scheduled: kubectl get pods -o wide"
    fi
    
    # Display current cluster status
    print_message $BLUE "Current cluster status:"
    if command_exists kubectl; then
        kubectl get nodes 2>/dev/null || print_message $YELLOW "kubectl not available or cluster not accessible"
    else
        print_message $YELLOW "kubectl not found - please check cluster status manually"
    fi
    
else
    print_message $RED "Node setup failed!"
    print_message $YELLOW "Common issues and solutions:"
    print_message $YELLOW "1. SSH connectivity: Check SSH key configuration"
    print_message $YELLOW "2. Firewall issues: Disable firewall or configure ports"
    print_message $YELLOW "3. SELinux issues: Check /etc/selinux/config"
    print_message $YELLOW "4. Package issues: Check internet connectivity and repositories"
    exit 1
fi 