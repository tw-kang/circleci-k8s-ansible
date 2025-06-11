#!/bin/bash

# Add Node to Kubernetes Cluster Script
# This script adds new worker nodes to an existing Kubernetes cluster
# Updated for Kubernetes v1.28.15 with ARM64 support and improved automation

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
SKIP_SSH_SETUP=false

# Current supported versions
KUBERNETES_VERSION="1.28.15"
CONTAINERD_VERSION="1.7.27"

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to auto-generate SSH keys
setup_ssh_keys() {
    local ssh_key_path="$HOME/.ssh/id_ed25519"
    local ssh_pub_key_path="$HOME/.ssh/id_ed25519.pub"
    
    print_message $BLUE "🔑 SSH 키 자동 설정 시작..."
    
    # Ensure .ssh directory exists
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Check if SSH keys already exist
    if [[ -f "$ssh_key_path" && -f "$ssh_pub_key_path" ]]; then
        print_message $GREEN "✅ SSH 키가 이미 존재합니다: $ssh_key_path"
        print_message $YELLOW "기존 키를 사용합니다."
    else
        print_message $YELLOW "🔧 SSH 키 쌍을 자동 생성합니다..."
        
        # Generate SSH key pair
        ssh-keygen -t ed25519 -f "$ssh_key_path" -N "" -C "ansible-auto-generated-$(date +%s)" 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            print_message $GREEN "✅ SSH 키 쌍이 성공적으로 생성되었습니다!"
            print_message $GREEN "   개인 키: $ssh_key_path"
            print_message $GREEN "   공개 키: $ssh_pub_key_path"
        else
            print_message $RED "❌ SSH 키 생성에 실패했습니다."
            return 1
        fi
    fi
    
    # Set correct permissions
    chmod 600 "$ssh_key_path" 2>/dev/null
    chmod 644 "$ssh_pub_key_path" 2>/dev/null
    
    print_message $BLUE "📋 SSH 공개 키 내용:"
    print_message $YELLOW "$(cat "$ssh_pub_key_path")"
    echo
    
    return 0
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Add Node to Kubernetes Cluster Script
Supports: Kubernetes v${KUBERNETES_VERSION}, containerd v${CONTAINERD_VERSION}, ARM64/x86_64
🔑 Automatically generates SSH keys (no manual ssh-keygen required!)

OPTIONS:
    --node-ip IP               New node IP address (required)
    --node-name NAME           New node name (required)
    --node-type TYPE           Node type: worker|master (default: worker)
    -i, --inventory INVENTORY  Specify inventory file (default: inventory/hosts.yml)
    --ssh-key PATH             SSH private key path (optional)
    --skip-preparation         Skip node preparation steps
    --skip-ssh-setup           Skip SSH key auto-generation
    -d, --dry-run              Perform a dry run (check mode)
    -vv, --verbose             Verbose output
    -h, --help                 Show this help message

EXAMPLES:
    # Add a worker node (recommended)
    $0 --node-ip 198.19.249.230 --node-name k8s-worker-01

    # Add a master node (for HA setup)
    $0 --node-ip 198.19.249.231 --node-name k8s-master-02 --node-type master

    # Add worker with custom SSH key
    $0 --node-ip 198.19.249.230 --node-name k8s-worker-01 --ssh-key ~/.ssh/k8s-key

    # Skip preparation if node is already prepared
    $0 --node-ip 198.19.249.230 --node-name k8s-worker-01 --skip-preparation

    # Dry run to check what would be changed
    $0 --node-ip 198.19.249.230 --node-name k8s-worker-01 --dry-run

PROCESS:
    1. Test SSH connectivity to new node
    2. Detect node architecture (ARM64/x86_64)
    3. Prepare node (install containerd, Kubernetes components)
    4. Update inventory file with new node
    5. Run Ansible playbook to join the cluster
    6. Verify node successfully joined

PREREQUISITES:
    - The new node should be accessible via SSH (root access)
    - The new node should have Rocky Linux 8 or compatible OS
    - The master node should be running and accessible
    - SSH key should be configured for passwordless access
    - Internet connectivity on the new node for package downloads

ARCHITECTURE SUPPORT:
    - ARM64: Automatically installs ARM64 binaries and configures Flannel CNI
    - x86_64: Uses package manager and configures Calico CNI
    - Mixed architectures: Each node configured based on its architecture

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
        print_message $YELLOW "4. Verify network connectivity:"
        print_message $YELLOW "   ping $node_ip"
        return 1
    fi
}

# Function to detect node architecture
detect_node_architecture() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        ssh_key_option="-i $SSH_KEY_PATH"
    fi
    
    print_message $BLUE "Detecting node architecture..."
    
    local arch=$(ssh $ssh_key_option root@$node_ip "uname -m" 2>/dev/null)
    
    case "$arch" in
        "x86_64"|"amd64")
            print_message $GREEN "Detected architecture: x86_64"
            print_message $YELLOW "Will configure with Calico CNI for performance"
            echo "x86_64"
            ;;
        "aarch64"|"arm64")
            print_message $GREEN "Detected architecture: ARM64 (aarch64)"
            print_message $YELLOW "Will configure with Flannel CNI for compatibility"
            echo "arm64"
            ;;
        *)
            print_message $RED "Unsupported architecture: $arch"
            print_message $RED "Supported architectures: x86_64, aarch64"
            return 1
            ;;
    esac
}

# Function to prepare the new node
prepare_node() {
    local node_ip=$1
    local node_arch=$2
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        ssh_key_option="-i $SSH_KEY_PATH"
    fi
    
    print_message $BLUE "Preparing new node ($node_ip) for Kubernetes..."
    
    # Call the prepare-worker-node.sh script
    local prepare_script="$SCRIPT_DIR/prepare-worker-node.sh"
    
    if [[ ! -f "$prepare_script" ]]; then
        print_message $RED "Prepare script not found: $prepare_script"
        return 1
    fi
    
    print_message $BLUE "Running node preparation script..."
    
    local prepare_cmd="$prepare_script --target-node $node_ip"
    [[ -n "$SSH_KEY_PATH" ]] && prepare_cmd="$prepare_cmd --ssh-key $SSH_KEY_PATH"
    
    if $prepare_cmd; then
        print_message $GREEN "✓ Node preparation completed successfully"
        return 0
    else
        print_message $RED "✗ Node preparation failed"
        return 1
    fi
}

# Function to update inventory file
update_inventory() {
    local node_ip=$1
    local node_name=$2
    local node_type=$3
    local inventory_file=$4
    
    print_message $BLUE "Updating inventory file: $inventory_file"
    
    # Create backup
    cp "$inventory_file" "${inventory_file}.backup.$(date +%s)"
    
    # Determine the group to add the node to
    local group=""
    case "$node_type" in
        "worker")
            group="k8s_workers"
            ;;
        "master")
            group="k8s_masters"
            ;;
        *)
            print_message $RED "Invalid node type: $node_type"
            return 1
            ;;
    esac
    
    # Check if node already exists
    if grep -q "$node_name:" "$inventory_file"; then
        print_message $YELLOW "Node $node_name already exists in inventory"
        return 0
    fi
    
    # Add the new node to the appropriate group
    print_message $BLUE "Adding $node_name to $group group..."
    
    # Use a temporary file for safe editing
    local temp_file=$(mktemp)
    local in_group=false
    local group_found=false
    
    while IFS= read -r line; do
        echo "$line" >> "$temp_file"
        
        # Check if we're entering the target group
        if [[ "$line" =~ ^[[:space:]]*${group}:[[:space:]]*$ ]]; then
            in_group=true
            group_found=true
            continue
        fi
        
        # Check if we're leaving the current group
        if [[ "$in_group" == true ]] && [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$ ]]; then
            # We've hit another group, insert our node before this line
            cat >> "$temp_file" << EOF
        hosts:
          ${node_name}:
            ansible_host: ${node_ip}
            ansible_user: root
            ansible_python_interpreter: /usr/bin/python3
            node_role: ${node_type}
EOF
            in_group=false
        fi
        
        # If we're in the hosts section of our target group, and we hit the first host entry
        if [[ "$in_group" == true ]] && [[ "$line" =~ ^[[:space:]]*hosts:[[:space:]]*$ ]]; then
            # Check if there are existing hosts
            read -r next_line
            if [[ -n "$next_line" ]]; then
                echo "$next_line" >> "$temp_file"
                # Add our node after existing hosts
                cat >> "$temp_file" << EOF
          ${node_name}:
            ansible_host: ${node_ip}
            ansible_user: root
            ansible_python_interpreter: /usr/bin/python3
            node_role: ${node_type}
EOF
            else
                # No existing hosts, add our node
                cat >> "$temp_file" << EOF
          ${node_name}:
            ansible_host: ${node_ip}
            ansible_user: root
            ansible_python_interpreter: /usr/bin/python3
            node_role: ${node_type}
EOF
            fi
        fi
    done < "$inventory_file"
    
    # If group wasn't found or we didn't add the node yet, handle it
    if [[ "$group_found" == false ]]; then
        print_message $RED "Group $group not found in inventory file"
        rm -f "$temp_file"
        return 1
    fi
    
    # Replace the original file
    mv "$temp_file" "$inventory_file"
    
    print_message $GREEN "✓ Node added to inventory successfully"
    return 0
}

# Function to join node to cluster
join_node_to_cluster() {
    local node_name=$1
    local node_type=$2
    local inventory_file=$3
    
    print_message $BLUE "Joining $node_name to Kubernetes cluster..."
    
    # Determine the appropriate playbook
    local playbook=""
    case "$node_type" in
        "worker")
            playbook="playbooks/k8s-cluster.yml"
            ;;
        "master")
            print_message $YELLOW "Master node joining not fully automated yet"
            print_message $YELLOW "Please refer to Kubernetes documentation for HA master setup"
            return 0
            ;;
    esac
    
    # Build ansible-playbook command
    local ansible_cmd="ansible-playbook -i $inventory_file $playbook --limit $node_name"
    
    # Add options
    [[ "$DRY_RUN" == true ]] && ansible_cmd="$ansible_cmd --check --diff"
    [[ -n "$VERBOSE" ]] && ansible_cmd="$ansible_cmd $VERBOSE"
    
    print_message $BLUE "Executing: $ansible_cmd"
    
    if eval "$ansible_cmd"; then
        print_message $GREEN "✓ Node successfully joined to cluster"
        return 0
    else
        print_message $RED "✗ Failed to join node to cluster"
        return 1
    fi
}

# Function to verify node joining
verify_node_joining() {
    local node_name=$1
    local inventory_file=$2
    
    print_message $BLUE "Verifying node joining..."
    
    # Check cluster status from master node
    if ansible k8s_masters -i "$inventory_file" -m shell -a "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes" --become | grep -q "$node_name"; then
        print_message $GREEN "✓ Node $node_name successfully joined and visible in cluster"
        
        # Show node status
        print_message $BLUE "Current cluster nodes:"
        ansible k8s_masters -i "$inventory_file" -m shell -a "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide" --become 2>/dev/null | grep -E "(SUCCESS|CHANGED)" || true
        
        return 0
    else
        print_message $RED "✗ Node $node_name not found in cluster"
        print_message $YELLOW "Check the logs above for errors"
        return 1
    fi
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
        --skip-ssh-setup)
            SKIP_SSH_SETUP=true
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
print_message $BLUE "🔑 SSH 키 자동 생성 포함"
print_message $BLUE "========================================="

# Setup SSH keys automatically (unless skipped)
if [[ "$SKIP_SSH_SETUP" != true ]]; then
    if ! setup_ssh_keys; then
        print_message $RED "SSH 키 설정에 실패했습니다. --skip-ssh-setup 옵션을 사용하여 건너뛸 수 있습니다."
        exit 1
    fi
    echo
fi

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

# Detect node architecture
node_arch=$(detect_node_architecture "$NEW_NODE_IP")
if [[ -z "$node_arch" ]]; then
    exit 1
fi

# Prepare the node if not skipped
if [[ "$SKIP_PREPARATION" != true && "$DRY_RUN" != true ]]; then
    if ! prepare_node "$NEW_NODE_IP" "$node_arch"; then
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
print_message $BLUE "Starting node addition process..."

if eval "$ANSIBLE_CMD"; then
    print_message $GREEN "========================================="
    print_message $GREEN "Node addition completed successfully!"
    print_message $GREEN "========================================="
    
    # Verify node is in cluster
    print_message $BLUE "Verifying node is in cluster..."
    
    if ansible k8s_masters -i "$INVENTORY" -m shell -a "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes" --become | grep -q "$NEW_NODE_NAME"; then
        print_message $GREEN "✓ Node $NEW_NODE_NAME successfully joined cluster"
        
        # Show cluster status
        print_message $BLUE "Current cluster status:"
        ansible k8s_masters -i "$INVENTORY" -m shell -a "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide" --become 2>/dev/null || true
        
        echo
        print_message $GREEN "Next steps:"
        print_message $GREEN "1. Wait for node to be Ready:"
        print_message $GREEN "   kubectl get nodes -w"
        print_message $GREEN "2. Check node labels:"
        print_message $GREEN "   kubectl describe node $NEW_NODE_NAME"
        print_message $GREEN "3. Test workload scheduling (for workers):"
        print_message $GREEN "   kubectl run test-pod --image=nginx --restart=Never"
        echo
        print_message $GREEN "🔑 SSH 키 파일 위치:"
        print_message $GREEN "  개인 키: ~/.ssh/id_ed25519"
        print_message $GREEN "  공개 키: ~/.ssh/id_ed25519.pub"
        
        if [[ "$NODE_TYPE" == "worker" ]]; then
            print_message $BLUE "Worker node $NEW_NODE_NAME is ready for workloads!"
        else
            print_message $BLUE "Master node $NEW_NODE_NAME added to cluster!"
            print_message $YELLOW "Note: For HA master setup, additional configuration may be required."
        fi
    else
        print_message $YELLOW "⚠ Node may not have joined cluster yet or needs more time"
        print_message $YELLOW "Check cluster status manually:"
        print_message $YELLOW "  kubectl get nodes"
    fi
    
else
    print_message $RED "Node addition failed!"
    print_message $RED "Check the error output above for details"
    
    # Cleanup on failure
    if [[ -f "${INVENTORY}.backup.$(date +%Y%m%d_%H%M%S)" ]]; then
        print_message $YELLOW "Restoring inventory backup..."
        mv "${INVENTORY}.backup."* "$INVENTORY" 2>/dev/null || true
    fi
    
    print_message $YELLOW "Troubleshooting steps:"
    print_message $YELLOW "1. Check SSH connectivity: ssh root@$NEW_NODE_IP"
    print_message $YELLOW "2. Verify node preparation: systemctl status kubelet containerd"
    print_message $YELLOW "3. Check master node status: kubectl get nodes"
    print_message $YELLOW "4. Review Ansible logs above for specific errors"
    
    exit 1
fi 