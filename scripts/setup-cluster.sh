#!/bin/bash

# Unified Kubernetes Cluster Management Script
# This script provides comprehensive Kubernetes cluster management capabilities
# Updated for Kubernetes v1.28.15 with ARM64 support and containerd v1.7.27

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
MODE=""
INVENTORY="inventory/production/hosts.yml"
VAULT_PASSWORD_FILE=""
DRY_RUN=false
VERBOSE=""
SKIP_SSH_SETUP=false
NEW_NODE_IP=""
NEW_NODE_NAME=""
NODE_TYPE="worker"

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
    
    print_message $BLUE "🔑 Starting SSH key auto-setup..."
    
    # Ensure .ssh directory exists
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Check if SSH keys already exist
    if [[ -f "$ssh_key_path" && -f "$ssh_pub_key_path" ]]; then
        print_message $GREEN "✅ SSH key already exists: $ssh_key_path"
        print_message $YELLOW "Using existing key."
    else
        print_message $YELLOW "🔧 Auto-generating SSH key pair..."
        
        # Generate SSH key pair
        ssh-keygen -t ed25519 -f "$ssh_key_path" -N "" -C "k8s-cluster-$(date +%s)" 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            print_message $GREEN "✅ SSH key pair generated successfully!"
            print_message $GREEN "   Private key: $ssh_key_path"
            print_message $GREEN "   Public key: $ssh_pub_key_path"
        else
            print_message $RED "❌ SSH key generation failed."
            return 1
        fi
    fi
    
    # Set correct permissions
    chmod 600 "$ssh_key_path" 2>/dev/null
    chmod 644 "$ssh_pub_key_path" 2>/dev/null
    
    print_message $BLUE "📋 SSH public key contents:"
    print_message $YELLOW "$(cat "$ssh_pub_key_path")"
    echo
    
    return 0
}

# Function to copy SSH keys to target nodes
copy_ssh_keys() {
    print_message $BLUE "🔐 Deploying SSH keys to target nodes..."
    
    # Get SSH password from vault
    local ssh_password=""
    if [[ -f "group_vars/all/vault.yml" && -n "$VAULT_PASSWORD_FILE" ]]; then
        ssh_password=$(ansible-vault view group_vars/all/vault.yml --vault-password-file "$VAULT_PASSWORD_FILE" 2>/dev/null | grep "vault_ssh_password:" | cut -d':' -f2 | tr -d ' "'"'" | head -1)
    fi
    
    # Get list of all nodes from inventory
    local nodes=$(ansible all -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | sed 's/^[[:space:]]*//' || echo "")
    
    if [[ -z "$nodes" ]]; then
        print_message $YELLOW "⚠️ Cannot find nodes in inventory."
        return 1
    fi
    
    for node in $nodes; do
        # Get node IP
        local node_ip=$(ansible "$node" -i "$INVENTORY" -m debug -a "var=ansible_host" --one-line 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "")
        
        if [[ -n "$node_ip" ]]; then
            print_message $BLUE "📤 Copying SSH key to $node ($node_ip)..."
            
            # Try ssh-copy-id with password if available
            if [[ -n "$ssh_password" ]]; then
                print_message $YELLOW "Attempting SSH key copy using password..."
                
                if command -v expect &> /dev/null; then
                    expect -c "
                        set timeout 30
                        spawn ssh-copy-id -o StrictHostKeyChecking=no -i $HOME/.ssh/id_ed25519.pub root@$node_ip
                        expect {
                            \"*password*\" { send \"$ssh_password\r\"; exp_continue }
                            \"*Password*\" { send \"$ssh_password\r\"; exp_continue }
                            \"*(yes/no)*\" { send \"yes\r\"; exp_continue }
                            \"*Are you sure*\" { send \"yes\r\"; exp_continue }
                            eof
                        }
                    " 2>/dev/null || {
                        print_message $YELLOW "Automatic copy failed using expect. Please copy manually:"
                        print_message $YELLOW "ssh-copy-id -i $HOME/.ssh/id_ed25519.pub root@$node_ip"
                    }
                else
                    print_message $YELLOW "expect is not installed. Please copy manually:"
                    print_message $YELLOW "ssh-copy-id -i $HOME/.ssh/id_ed25519.pub root@$node_ip"
                fi
            else
                print_message $YELLOW "SSH password is not configured. Please copy manually:"
                print_message $YELLOW "ssh-copy-id -i $HOME/.ssh/id_ed25519.pub root@$node_ip"
            fi
            
            # Test SSH connection
            if timeout 10 ssh -i "$HOME/.ssh/id_ed25519" -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "echo 'SSH connection successful'" >/dev/null 2>&1; then
                print_message $GREEN "✅ $node: SSH connection successful"
            else
                print_message $RED "❌ $node: SSH connection failed"
            fi
        else
            print_message $YELLOW "⚠️ $node: Cannot find IP address"
        fi
    done
}

# Function to add node to inventory
add_node_to_inventory() {
    local node_name="$1"
    local node_ip="$2"
    local node_type="$3"
    
    print_message $BLUE "📝 Adding node to inventory: $node_name ($node_ip)"
    
    # Create backup
    cp "$INVENTORY" "${INVENTORY}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ "$node_type" == "worker" ]]; then
        # Add to workers section
        awk -v node_name="$node_name" -v node_ip="$node_ip" '
        /k8s_workers:/{
            print $0
            getline
            print $0  # print "hosts:"
            print "            " node_name ":"
            print "              ansible_host: " node_ip "  # Added by setup-cluster.sh"
            print "              ansible_user: root"
            print "              node_role: worker"
            next
        }
        {print}' "$INVENTORY" > "${INVENTORY}.tmp" && mv "${INVENTORY}.tmp" "$INVENTORY"
    else
        # Add to masters section
        awk -v node_name="$node_name" -v node_ip="$node_ip" '
        /k8s_masters:/{
            print $0
            getline
            print $0  # print "hosts:"
            print "            " node_name ":"
            print "              ansible_host: " node_ip "  # Added by setup-cluster.sh"
            print "              ansible_user: root"
            print "              node_role: master"
            next
        }
        {print}' "$INVENTORY" > "${INVENTORY}.tmp" && mv "${INVENTORY}.tmp" "$INVENTORY"
    fi
    
    print_message $GREEN "✅ Node added to inventory successfully"
}

# Function to detect target architecture
detect_target_architecture() {
    if [[ -f "$INVENTORY" ]]; then
        print_message $BLUE "Detecting target system architecture..."
        local arch=$(ansible all -i "$INVENTORY" -m setup -a "filter=ansible_architecture" --one-line 2>/dev/null | head -1 | grep -o 'aarch64\|x86_64' || echo "unknown")
        
        case "$arch" in
            "aarch64")
                print_message $GREEN "Target architecture: ARM64 (aarch64)"
                print_message $YELLOW "Using Flannel CNI for ARM64 compatibility"
                ;;
            "x86_64")
                print_message $GREEN "Target architecture: x86_64"
                print_message $YELLOW "Using Calico CNI for x86_64 performance"
                ;;
            *)
                print_message $YELLOW "Cannot detect target architecture or mixed architecture"
                print_message $YELLOW "Please ensure all nodes have the same architecture"
                ;;
        esac
    fi
}

# Function to run ansible playbook
run_ansible_playbook() {
    local playbook="$1"
    local tags="$2"
    local limit="$3"
    
    print_message $BLUE "Running Ansible playbook: $playbook"
    
    # Build ansible-playbook command
    local cmd="ansible-playbook -i $INVENTORY playbooks/$playbook"
    
    [[ -n "$tags" ]] && cmd="$cmd --tags $tags"
    [[ -n "$limit" ]] && cmd="$cmd --limit $limit"
    [[ -n "$VAULT_PASSWORD_FILE" ]] && cmd="$cmd --vault-password-file $VAULT_PASSWORD_FILE"
    [[ "$DRY_RUN" == true ]] && cmd="$cmd --check --diff"
    [[ -n "$VERBOSE" ]] && cmd="$cmd $VERBOSE"
    
    print_message $BLUE "Command to execute: $cmd"
    echo
    
    # Ask for confirmation if not dry run
    if [[ "$DRY_RUN" != true ]]; then
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message $YELLOW "Operation cancelled"
            return 1
        fi
    fi
    
    # Execute the playbook
    if eval "$cmd"; then
        print_message $GREEN "✅ Playbook execution completed successfully!"
        return 0
    else
        print_message $RED "❌ Playbook execution failed!"
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Integrated Kubernetes Cluster Management Script
Kubernetes v${KUBERNETES_VERSION}, containerd v${CONTAINERD_VERSION}, ARM64/x86_64 Support

Usage: $0 <MODE> [OPTIONS]

Modes (MODE):
    cluster-only        Configure Kubernetes cluster only
    add-node           Add node to existing cluster
    cluster-circleci   Kubernetes + CircleCI container-agent (Helm)
    add-node-circleci  Add node + CircleCI container-agent (Helm)
    deploy-circleci    Configure CircleCI agent on existing cluster (Helm)

Options (OPTIONS):
    -i, --inventory FILE        inventory file (default: inventory/production/hosts.yml)
    -v, --vault-password FILE   vault password file
    -d, --dry-run              Check only without actual execution
    -vv, --verbose             verbose output
    --skip-ssh-setup           Skip SSH key setup
    --verify-k8s-tools         Run Kubernetes tools installation verification
    
    # Options for node addition mode
    --node-ip IP               New node IP address (required)
    --node-name NAME           New node name (required)
    --node-type TYPE           Node type: worker|master (default: worker)
    
    -h, --help                 Show help

Examples:
    # 1. Configure Kubernetes cluster only
    $0 cluster-only

    # 2. Add worker node
    $0 add-node --node-ip 198.19.249.230 --node-name k8s-worker-01

    # 3. Configure Kubernetes + CircleCI
    $0 cluster-circleci

    # 4. Add node + CircleCI setup
    $0 add-node-circleci --node-ip 198.19.249.230 --node-name k8s-worker-01

    # 5. Deploy CircleCI agent only to existing cluster
    $0 deploy-circleci

    # Check with dry run
    $0 cluster-only --dry-run

    # Use vault file
    $0 cluster-circleci --vault-password ~/.ansible-vault-pass

Architecture Support:
    - x86_64: Full support with Calico CNI
    - ARM64: Full support with Flannel CNI
    - Automatic detection and architecture-specific configuration

Requirements:
    - Ansible 2.9+
    - Target nodes: Rocky Linux 8 or compatible OS
    - SSH access to target nodes
    - Internet connection (for package downloads)

EOF
}

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
fi

MODE="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -v|--vault-password)
            VAULT_PASSWORD_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -vv|--verbose)
            VERBOSE="-vv"
            shift
            ;;
        --skip-ssh-setup)
            SKIP_SSH_SETUP=true
            shift
            ;;
        --verify-k8s-tools)
            VERIFY_K8S_TOOLS=true
            shift
            ;;
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

# Validate mode
case "$MODE" in
    cluster-only|add-node|cluster-circleci|add-node-circleci|deploy-circleci)
        ;;
    *)
        print_message $RED "Invalid mode: $MODE"
        show_usage
        exit 1
        ;;
esac

# Validate node addition parameters
if [[ "$MODE" == "add-node" || "$MODE" == "add-node-circleci" ]]; then
    if [[ -z "$NEW_NODE_IP" || -z "$NEW_NODE_NAME" ]]; then
        print_message $RED "--node-ip and --node-name are required for node addition mode"
        exit 1
    fi
fi

# Change to project directory
cd "$PROJECT_DIR"

print_message $BLUE "========================================="
print_message $BLUE "Integrated Kubernetes Cluster Management"
print_message $BLUE "Mode: $MODE"
print_message $BLUE "Kubernetes: v${KUBERNETES_VERSION}"
print_message $BLUE "containerd: v${CONTAINERD_VERSION}"
print_message $BLUE "========================================="

# Check prerequisites
if ! command -v ansible-playbook &> /dev/null; then
    print_message $RED "Error: ansible-playbook is not installed"
    print_message $YELLOW "Please install Ansible first:"
    print_message $YELLOW "  dnf install ansible"
    exit 1
fi

if [[ ! -f "$INVENTORY" ]]; then
    print_message $RED "Error: Cannot find inventory file: $INVENTORY"
    exit 1
fi

# Execute based on mode
case "$MODE" in
    cluster-only|cluster-circleci|deploy-circleci)
        # Setup SSH keys automatically (unless skipped)
        if [[ "$SKIP_SSH_SETUP" != true ]]; then
            if ! setup_ssh_keys; then
                print_message $RED "SSH key setup failed. You can skip it using --skip-ssh-setup option."
                exit 1
            fi
            
            # Copy SSH keys to target nodes
            copy_ssh_keys
            echo
        fi

        # Detect target architecture
        detect_target_architecture
        
        case "$MODE" in
            cluster-only)
                print_message $GREEN "🚀 Starting Kubernetes cluster setup..."
                tags="common,kubernetes,verification"
                [[ "$VERIFY_K8S_TOOLS" == true ]] && tags="$tags,k8s-verification"
                
                if run_ansible_playbook "cluster-only.yml" "$tags" ""; then
                    print_message $GREEN "✅ Kubernetes cluster setup completed!"
                    print_message $BLUE "Next steps:"
                    print_message $BLUE "1. Check cluster status: kubectl get nodes"
                    print_message $BLUE "2. Check all pods: kubectl get pods -A"
                    print_message $BLUE "3. Verify Kubernetes tools: kubeadm version && kubectl version --client"
                fi
                ;;
                
            cluster-circleci)
                print_message $GREEN "🚀 Starting Kubernetes + CircleCI setup..."
                tags=""
                [[ "$VERIFY_K8S_TOOLS" == true ]] && tags="k8s-verification"
                
                if run_ansible_playbook "cluster-circleci.yml" "$tags" ""; then
                    print_message $GREEN "✅ Kubernetes + CircleCI setup completed!"
                    print_message $BLUE "Next steps:"
                    print_message $BLUE "1. Check cluster status: kubectl get nodes"
                    print_message $BLUE "2. Check CircleCI runner: kubectl get pods -n circleci"
                    print_message $BLUE "3. Configure resource class in CircleCI project settings"
                fi
                ;;
                
            deploy-circleci)
                print_message $GREEN "🎯 Starting CircleCI agent deployment to existing cluster..."
                tags="circleci,runner"
                [[ "$VERIFY_K8S_TOOLS" == true ]] && tags="$tags,k8s-verification"
                
                if run_ansible_playbook "deploy-circleci.yml" "$tags" ""; then
                    print_message $GREEN "✅ CircleCI agent deployment completed!"
                    print_message $BLUE "Next steps:"
                    print_message $BLUE "1. Check CircleCI runner status: kubectl get pods -n circleci"
                    print_message $BLUE "2. Check runner logs: kubectl logs -n circleci -l app=circleci-runner"
                    print_message $BLUE "3. Set resource class in CircleCI project"
                    print_message $BLUE "4. Use self-hosted runner in .circleci/config.yml"
                fi
                ;;
        esac
        ;;
        
    add-node|add-node-circleci)
        # For node addition, add to inventory first, then setup SSH keys
        print_message $GREEN "🔗 Starting node addition to cluster..."
        
        # Add node to inventory first
        add_node_to_inventory "$NEW_NODE_NAME" "$NEW_NODE_IP" "$NODE_TYPE"
        
        # Setup SSH keys automatically (unless skipped)
        if [[ "$SKIP_SSH_SETUP" != true ]]; then
            if ! setup_ssh_keys; then
                print_message $RED "SSH key setup failed. You can skip it using --skip-ssh-setup option."
                exit 1
            fi
            
            # Copy SSH keys to all nodes (including the new one)
            copy_ssh_keys
            echo
        fi

        # Detect target architecture
        detect_target_architecture
        
        case "$MODE" in
            add-node)
                # Run playbook for the new node
                tags=""
                [[ "$VERIFY_K8S_TOOLS" == true ]] && tags="k8s-verification"
                
                if run_ansible_playbook "add-node.yml" "$tags" "$NEW_NODE_NAME"; then
                    print_message $GREEN "✅ Node addition completed!"
                    print_message $BLUE "Next steps:"
                    print_message $BLUE "1. Check cluster status: kubectl get nodes"
                    print_message $BLUE "2. Verify new node: kubectl describe node $NEW_NODE_NAME"
                fi
                ;;
                
            add-node-circleci)
                # Run full playbook for new node + CircleCI on master
                tags=""
                [[ "$VERIFY_K8S_TOOLS" == true ]] && tags="k8s-verification"
                
                if run_ansible_playbook "add-node-circleci.yml" "$tags" "$NEW_NODE_NAME,k8s_masters"; then
                    print_message $GREEN "✅ Node addition + CircleCI setup completed!"
                    print_message $BLUE "Next steps:"
                    print_message $BLUE "1. Check cluster status: kubectl get nodes"
                    print_message $BLUE "2. Check CircleCI runner: kubectl get pods -n circleci"
                    print_message $BLUE "3. Verify new node: kubectl describe node $NEW_NODE_NAME"
                fi
                ;;
        esac
        ;;
esac

print_message $GREEN "========================================="
print_message $GREEN "Task completed!"
print_message $GREEN "Completion time: $(date)"
print_message $GREEN "=========================================" 