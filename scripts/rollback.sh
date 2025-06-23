#!/bin/bash

# Kubernetes Cluster Rollback/Reset Script (Kubespray-based)
# This script safely resets Kubernetes clusters using Kubespray reset functionality
# Updated for Kubespray integration with enhanced safety checks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
INVENTORY="inventory/production/hosts.ini"
VAULT_PASSWORD_FILE=""
DRY_RUN=false
FORCE=false
SKIP_CONFIRMATION=false
VERBOSE=""
RESET_LEVEL="cluster"
BACKUP_DIR=""

# Kubespray paths
KUBESPRAY_DIR="$PROJECT_DIR/3rdparty/kubespray"

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo
    print_message $BOLD "========================================="
    print_message $BOLD "$1"
    print_message $BOLD "========================================="
    echo
}

print_warning() {
    print_message $YELLOW "WARNING: $1"
}

print_error() {
    print_message $RED "ERROR: $1"
}

print_success() {
    print_message $GREEN "$1"
}

print_info() {
    print_message $BLUE "INFO: $1"
}

# Function to validate prerequisites
validate_prerequisites() {
    print_info "Checking prerequisites..."
    
    local errors=0
    
    # Check ansible
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "ansible-playbook not found"
        ((errors++))
    fi
    
    # Check kubespray
    if [[ ! -d "$KUBESPRAY_DIR" ]]; then
        print_error "Kubespray not found at $KUBESPRAY_DIR"
        print_info "Initialize submodule: git submodule update --init --recursive"
        ((errors++))
    fi
    
    # Check reset playbook
    if [[ ! -f "$KUBESPRAY_DIR/reset.yml" ]]; then
        print_error "Kubespray reset playbook not found"
        ((errors++))
    fi
    
    # Check inventory
    if [[ ! -f "$INVENTORY" ]]; then
        print_error "Inventory file not found: $INVENTORY"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        print_error "Prerequisites check failed with $errors error(s)"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to validate inventory and show cluster info
validate_inventory() {
    print_info "Validating inventory and gathering cluster information..."
    
    # Test inventory parsing
    if ! ansible-inventory -i "$INVENTORY" --list >/dev/null 2>&1; then
        print_error "Inventory parsing failed"
        exit 1
    fi
    
    # Get cluster information
    local control_plane_count=$(ansible kube_control_plane -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | wc -l)
    local total_nodes=$(ansible kube_node -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | wc -l)
    local etcd_count=$(ansible etcd -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | wc -l)
    
    print_info "Cluster information:"
    print_info "  Control plane nodes: $control_plane_count"
    print_info "  Total nodes: $total_nodes"
    print_info "  Etcd nodes: $etcd_count"
    
    # Show nodes that will be affected
    print_info "Nodes that will be reset:"
    ansible all -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | sed 's/^/    /'
    
    return 0
}

# Function to create backup of important data
create_backup() {
    if [[ -z "$BACKUP_DIR" ]]; then
        return 0
    fi
    
    print_info "Creating backup of cluster configuration..."
    
    # Create backup directory
    local backup_path="$BACKUP_DIR/k8s-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_path"
    
    # Backup kubeconfig if kubectl is available
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        print_info "Backing up Kubernetes resources..."
        
        # Backup cluster info
        kubectl cluster-info > "$backup_path/cluster-info.txt" 2>/dev/null || true
        
        # Backup node information
        kubectl get nodes -o yaml > "$backup_path/nodes.yaml" 2>/dev/null || true
        
        # Backup all namespaces
        kubectl get namespaces -o yaml > "$backup_path/namespaces.yaml" 2>/dev/null || true
        
        # Backup persistent volumes
        kubectl get pv -o yaml > "$backup_path/persistent-volumes.yaml" 2>/dev/null || true
        
        # Backup config maps in kube-system
        kubectl get configmaps -n kube-system -o yaml > "$backup_path/kube-system-configmaps.yaml" 2>/dev/null || true
        
        # Backup secrets in kube-system (be careful with this)
        if [[ "$FORCE" == "true" ]]; then
            kubectl get secrets -n kube-system -o yaml > "$backup_path/kube-system-secrets.yaml" 2>/dev/null || true
        fi
        
        print_success "Kubernetes resources backed up to: $backup_path"
    else
        print_warning "kubectl not available or cluster not accessible - skipping Kubernetes backup"
    fi
    
    # Backup project configuration
    print_info "Backing up project configuration..."
    cp -r group_vars "$backup_path/" 2>/dev/null || true
    cp -r inventory "$backup_path/" 2>/dev/null || true
    cp ansible.cfg "$backup_path/" 2>/dev/null || true
    
    print_success "Configuration backup completed: $backup_path"
    echo "export BACKUP_PATH=\"$backup_path\"" > "$backup_path/restore_info.sh"
}

# Function to show safety warnings
show_safety_warnings() {
    print_header "DESTRUCTIVE OPERATION WARNING"
    
    print_warning "This operation will COMPLETELY RESET the Kubernetes cluster!"
    print_warning "ALL DATA AND WORKLOADS WILL BE PERMANENTLY LOST!"
    echo
    
    print_message $RED "What will be destroyed:"
    print_message $RED "  - All Kubernetes workloads and pods"
    print_message $RED "  - All Kubernetes configurations and secrets"
    print_message $RED "  - All container images on nodes"
    print_message $RED "  - All persistent data (unless using external storage)"
    print_message $RED "  - All network configurations"
    print_message $RED "  - All etcd data"
    echo
    
    print_message $YELLOW "What will be preserved:"
    print_message $YELLOW "  - Node operating systems"
    print_message $YELLOW "  - Project configuration files"
    print_message $YELLOW "  - External storage (if properly configured)"
    print_message $YELLOW "  - Network infrastructure"
    echo
    
    print_message $BLUE "Reset method: Kubespray reset.yml playbook"
    print_message $BLUE "Inventory: $INVENTORY"
    print_message $BLUE "Reset level: $RESET_LEVEL"
    echo
}

# Function to get confirmation
get_confirmation() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$FORCE" == "true" ]]; then
        print_warning "Skipping confirmation due to --force or --skip-confirmation flag"
        return 0
    fi
    
    echo
    print_message $BOLD "FINAL CONFIRMATION REQUIRED"
    echo
    
    # Get cluster name for additional safety
    local cluster_name="unknown"
    if [[ -f "group_vars/k8s_cluster/k8s-cluster.yml" ]]; then
        cluster_name=$(grep "^cluster_name:" "group_vars/k8s_cluster/k8s-cluster.yml" 2>/dev/null | cut -d':' -f2 | tr -d ' "' || echo "unknown")
    fi
    
    print_message $YELLOW "Please type the cluster name '$cluster_name' to confirm:"
    read -p "Cluster name: " input_cluster_name
    
    if [[ "$input_cluster_name" != "$cluster_name" ]]; then
        print_error "Cluster name mismatch. Reset cancelled for safety."
        exit 1
    fi
    
    print_message $YELLOW "Type 'RESET' in capital letters to proceed:"
    read -p "Confirmation: " confirmation
    
    if [[ "$confirmation" != "RESET" ]]; then
        print_error "Invalid confirmation. Reset cancelled."
        exit 1
    fi
    
    print_message $YELLOW "Are you absolutely sure? This cannot be undone! (yes/no):"
    read -p "Final confirmation: " final_confirmation
    
    if [[ "$final_confirmation" != "yes" ]]; then
        print_error "Reset cancelled by user."
        exit 1
    fi
    
    print_success "Confirmation received. Proceeding with reset..."
}

# Function to run kubespray reset
run_kubespray_reset() {
    print_header "Executing Kubespray Reset"
    
    # Change to project directory for relative paths
    cd "$PROJECT_DIR"
    
    # Build ansible-playbook command using our playbook wrapper
    local cmd="ansible-playbook -i $INVENTORY playbooks/reset-cluster.yml"
    
    # Add optional parameters
    [[ -n "$VAULT_PASSWORD_FILE" ]] && cmd="$cmd --vault-password-file $VAULT_PASSWORD_FILE"
    [[ "$DRY_RUN" == "true" ]] && cmd="$cmd --check"
    [[ -n "$VERBOSE" ]] && cmd="$cmd $VERBOSE"
    
    # Add become
    cmd="$cmd --become"
    
    # Add kubespray reset confirmation
    cmd="$cmd -e reset_confirmation=yes"
    
    print_info "Executing command: $cmd"
    echo
    
    # Execute the reset
    print_info "Starting cluster reset process..."
    if eval "$cmd"; then
        print_success "Kubespray reset completed successfully!"
        return 0
    else
        print_error "Kubespray reset failed!"
        return 1
    fi
}

# Function to verify reset completion
verify_reset() {
    print_header "Verifying Reset Completion"
    
    # Check if kubectl still works (it shouldn't)
    if command -v kubectl &> /dev/null; then
        if kubectl cluster-info &> /dev/null; then
            print_warning "kubectl can still connect to cluster - reset may be incomplete"
        else
            print_success "kubectl cannot connect to cluster (expected after reset)"
        fi
    fi
    
    # Test SSH connectivity to nodes
    print_info "Testing SSH connectivity to nodes..."
    local ssh_failures=0
    local total_nodes=0
    
    # Get list of all nodes
    local nodes=$(ansible all -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | sed 's/^[[:space:]]*//' || echo "")
    
    for node in $nodes; do
        ((total_nodes++))
        
        # Get node IP
        local node_ip=$(ansible "$node" -i "$INVENTORY" -m debug -a "var=ansible_host" --one-line 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "")
        
        if [[ -n "$node_ip" ]]; then
            if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "echo 'SSH test successful'" >/dev/null 2>&1; then
                print_success "$node ($node_ip): SSH connectivity OK"
            else
                print_warning "$node ($node_ip): SSH connectivity failed"
                ((ssh_failures++))
            fi
        else
            print_warning "$node: Cannot resolve IP address"
            ((ssh_failures++))
        fi
    done
    
    if [[ $ssh_failures -eq 0 ]]; then
        print_success "All nodes are accessible via SSH"
    else
        print_warning "$ssh_failures/$total_nodes nodes have SSH connectivity issues"
    fi
    
    # Check if kubernetes processes are stopped
    print_info "Checking if Kubernetes processes are stopped on nodes..."
    local process_check_cmd="pgrep -f 'kube-|etcd|containerd' || echo 'no kubernetes processes found'"
    
    if ansible all -i "$INVENTORY" -m shell -a "$process_check_cmd" --one-line 2>/dev/null | grep -q "no kubernetes processes found"; then
        print_success "Kubernetes processes appear to be stopped"
    else
        print_warning "Some Kubernetes processes may still be running"
    fi
}

# Function to provide post-reset guidance
provide_post_reset_guidance() {
    print_header "Post-Reset Information"
    
    print_success "Cluster reset completed successfully!"
    echo
    
    print_message $BLUE "What happened:"
    print_message $BLUE "  - All Kubernetes components were removed"
    print_message $BLUE "  - Container runtime was reset"
    print_message $BLUE "  - Network configurations were cleared"
    print_message $BLUE "  - etcd data was removed"
    print_message $BLUE "  - Node operating systems remain intact"
    echo
    
    print_message $BLUE "Next steps:"
    print_message $BLUE "1. Verify nodes are clean and accessible:"
    print_message $YELLOW "   ansible all -i $INVENTORY -m ping"
    echo
    print_message $BLUE "2. Deploy new cluster when ready:"
    print_message $YELLOW "   ./scripts/setup-cluster.sh cluster-only"
    echo
    print_message $BLUE "3. Or deploy with CircleCI:"
    print_message $YELLOW "   ./scripts/setup-cluster.sh cluster-only --enable-circleci"
    echo
    
    if [[ -n "$BACKUP_PATH" ]]; then
        print_message $BLUE "Backup location:"
        print_message $YELLOW "   $BACKUP_PATH"
        print_message $BLUE "   Review backed up configurations if needed"
        echo
    fi
    
    print_message $BLUE "For troubleshooting:"
    print_message $BLUE "  - Check node logs: journalctl -u kubelet"
    print_message $BLUE "  - Check ansible connectivity: ansible all -i $INVENTORY -m ping"
    print_message $BLUE "  - Review kubespray docs: 3rdparty/kubespray/docs/"
}

# Function to show usage
show_usage() {
    cat << EOF
Kubernetes Cluster Rollback/Reset Script (Kubespray-based)
==========================================================

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -i, --inventory FILE        Inventory file (default: inventory/production/hosts.ini)
    -v, --vault-password FILE   Vault password file for encrypted variables
    -d, --dry-run              Check what would be reset without actually doing it
    -f, --force                Skip all confirmations (DANGEROUS!)
    --skip-confirmation        Skip interactive confirmations
    --backup DIR               Create backup before reset in specified directory
    -vv, --verbose             Verbose ansible output (-vv)
    -vvv                       Very verbose ansible output (-vvv)
    
    -h, --help                 Show this help message

EXAMPLES:
    # Safe reset with confirmation prompts
    $0
    
    # Reset with backup
    $0 --backup /home/user/k8s-backups
    
    # Dry run to see what would be reset
    $0 --dry-run
    
    # Force reset without confirmations (DANGEROUS!)
    $0 --force
    
    # Reset staging environment
    $0 -i inventory/staging/hosts.ini
    
    # Verbose reset with vault file
    $0 --vault-password .vault-password -vv

SAFETY FEATURES:
    - Multiple confirmation prompts by default
    - Cluster name verification
    - Dry run mode for testing
    - Optional backup creation
    - Prerequisites validation
    - Post-reset verification

WHAT GETS RESET:
    X All Kubernetes workloads and pods
    X All Kubernetes configurations and secrets  
    X All container images on nodes
    X All persistent data (unless external storage)
    X All network configurations
    X All etcd data

WHAT IS PRESERVED:
    O Node operating systems
    O SSH access and configuration
    O Project configuration files
    O External storage (if properly configured)
    O Network infrastructure

RESET METHOD:
    This script uses our reset-cluster.yml playbook which wraps 
    Kubespray's reset.yml playbook to safely remove all Kubernetes 
    components. It's the recommended way to completely reset a 
    kubespray-deployed cluster.

WARNING:
    This operation is DESTRUCTIVE and IRREVERSIBLE!
    All cluster data will be permanently lost!
    Always create backups of important data before proceeding!

EOF
}

# Parse command line arguments
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
        -f|--force)
            FORCE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --backup)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -vv|--verbose)
            VERBOSE="-vv"
            shift
            ;;
        -vvv)
            VERBOSE="-vvv"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Change to project directory
cd "$PROJECT_DIR"

# Main execution flow
print_header "Kubernetes Cluster Reset (Kubespray-based)"
print_info "Inventory: $INVENTORY"
print_info "Dry run: $DRY_RUN"
print_info "Force mode: $FORCE"

# Execute the reset process
validate_prerequisites
validate_inventory
create_backup
show_safety_warnings
get_confirmation

if run_kubespray_reset; then
    verify_reset
    provide_post_reset_guidance
    exit 0
else
    print_error "Cluster reset failed!"
    exit 1
fi 