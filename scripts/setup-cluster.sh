#!/bin/bash

# Kubernetes Cluster Management Script (Kubespray-based)
# This script provides comprehensive Kubernetes cluster management using Kubespray
# with optional CircleCI support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script directory and project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
MODE=""
INVENTORY="inventory/production/hosts.ini"
VAULT_PASSWORD_FILE=""
DRY_RUN=false
VERBOSE=""
TAGS=""
CIRCLECI_ENABLED=false
EXTRA_VARS=""

# Kubespray directory
KUBESPRAY_DIR="$PROJECT_DIR/3rdparty/kubespray"

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    local message=$1
    echo
    print_message $BOLD "========================================="
    print_message $BOLD "$message"
    print_message $BOLD "========================================="
    echo
}

print_step() {
    local step=$1
    local message=$2
    print_message $BLUE "[STEP $step] $message"
}

print_substep() {
    local message=$1
    print_message $YELLOW "  └─ $message"
}

# Function to check prerequisites
check_prerequisites() {
    print_step "1" "Checking system prerequisites..."
    
    local errors=0
    
    # Check ansible
    if ! command -v ansible-playbook &> /dev/null; then
        print_message $RED "ansible-playbook not found. Please install Ansible."
        ((errors++))
    else
        local ansible_version=$(ansible --version | head -1 | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        print_substep "Ansible found: v$ansible_version"
    fi
    
    # Check python
    if ! command -v python3 &> /dev/null; then
        print_message $RED "python3 not found. Please install Python 3."
        ((errors++))
    else
        print_substep "Python 3 found"
    fi
    
    # Check kubespray
    if [[ ! -d "$KUBESPRAY_DIR" ]]; then
        print_message $RED "Kubespray not found at $KUBESPRAY_DIR"
        print_message $YELLOW "Please initialize kubespray submodule:"
        print_message $YELLOW "  git submodule update --init --recursive"
        ((errors++))
    else
        print_substep "Kubespray found"
    fi
    
    # Check inventory
    if [[ ! -f "$INVENTORY" ]]; then
        print_message $RED "Inventory file not found: $INVENTORY"
        ((errors++))
    else
        print_substep "Inventory file found"
    fi
    
    # Check required group_vars structure
    local inventory_dir=$(dirname "$INVENTORY")
    local required_dirs=("$inventory_dir/group_vars/all" "$inventory_dir/group_vars/k8s_cluster")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            print_message $RED "Required directory missing: $dir"
            ((errors++))
        else
            print_substep "Directory found: $dir"
        fi
    done
    
    # Check CircleCI configuration if CircleCI is enabled
    if [[ "$CIRCLECI_ENABLED" == "true" ]]; then
        if [[ ! -d "inventory/production/group_vars/circleci" && ! -d "inventory/staging/group_vars/circleci" ]]; then
            print_message $RED "CircleCI configuration missing: group_vars/circleci"
            ((errors++))
        else
            print_substep "CircleCI configuration found"
        fi
    fi
    
    if [[ $errors -gt 0 ]]; then
        print_message $RED "Prerequisites check failed with $errors error(s)"
        exit 1
    fi
    
    print_substep "All prerequisites satisfied"
}

# Function to detect versions
detect_versions() {
    print_step "2" "Detecting version information..."
    
    # Get kubespray version
    if [[ -f "$KUBESPRAY_DIR/README.md" ]]; then
        local kubespray_version=$(grep -E "^# Kubespray v" "$KUBESPRAY_DIR/README.md" | head -1 | sed 's/# Kubespray v//' || echo "unknown")
        print_substep "Kubespray version: $kubespray_version"
    fi
    
    # Get supported kubernetes versions
    if [[ -f "$KUBESPRAY_DIR/roles/kubespray_defaults/defaults/main.yml" ]]; then
        local kube_version=$(grep "^kube_version:" "$KUBESPRAY_DIR/roles/kubespray_defaults/defaults/main.yml" | cut -d'"' -f2 2>/dev/null || echo "unknown")
        print_substep "Default Kubernetes version: $kube_version"
    fi
    
    # Get container runtime
    local inventory_dir=$(dirname "$INVENTORY")
    if [[ -f "$inventory_dir/group_vars/k8s_cluster/k8s-cluster.yml" ]]; then
        local container_manager=$(grep "^container_manager:" "$inventory_dir/group_vars/k8s_cluster/k8s-cluster.yml" | cut -d' ' -f2 2>/dev/null || echo "containerd")
        print_substep "Container runtime: $container_manager"
    fi
}

# Function to validate inventory structure
validate_inventory() {
    print_step "3" "Validating inventory structure..."
    
    # Check if inventory can be parsed
    if ! ansible-inventory -i "$INVENTORY" --list >/dev/null 2>&1; then
        print_message $RED "Inventory parsing failed"
        exit 1
    fi
    
    # Check required groups
    local required_groups=("kube_control_plane" "kube_node" "etcd" "k8s_cluster")
    for group in "${required_groups[@]}"; do
        if ansible-inventory -i "$INVENTORY" --list 2>/dev/null | grep -q "\"$group\""; then
            print_substep "Group found: $group"
        else
            print_message $RED "Required group missing: $group"
            exit 1
        fi
    done
    
    # Count nodes
    local control_plane_count=$(ansible kube_control_plane -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | wc -l)
    local worker_count=$(ansible kube_node -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | wc -l)
    local etcd_count=$(ansible etcd -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | wc -l)
    
    print_substep "Control plane nodes: $control_plane_count"
    print_substep "Total nodes: $worker_count" 
    print_substep "Etcd nodes: $etcd_count"
    
    # Validate node counts
    if [[ $control_plane_count -eq 0 ]]; then
        print_message $RED "No control plane nodes found"
        exit 1
    fi
    
    if [[ $etcd_count -eq 0 ]]; then
        print_message $RED "No etcd nodes found"
        exit 1
    fi
    
    if [[ $etcd_count -gt 1 && $((etcd_count % 2)) -eq 0 ]]; then
        print_message $YELLOW "Warning: Even number of etcd nodes ($etcd_count) - consider odd numbers for quorum"
    fi
}

# Function to run ansible playbook
run_ansible_playbook() {
    local playbook="$1"
    local tags="$2"
    local limit="$3"
    local extra_vars="$4"
    
    print_step "4" "Running Ansible playbook: $playbook"
    
    # Build ansible command
    local cmd="ansible-playbook -i \"$INVENTORY\""
    
    # Add vault password file if provided
    if [[ -n "$VAULT_PASSWORD_FILE" ]]; then
        cmd="$cmd --vault-password-file=\"$VAULT_PASSWORD_FILE\""
    fi
    
    # Add verbosity
    if [[ -n "$VERBOSE" ]]; then
        cmd="$cmd $VERBOSE"
    fi
    
    # Add tags if provided
    if [[ -n "$tags" ]]; then
        cmd="$cmd --tags=\"$tags\""
    fi
    
    # Add host limit if provided
    if [[ -n "$limit" ]]; then
        cmd="$cmd --limit=\"$limit\""
    fi
    
    # Add extra vars
    local all_extra_vars=""
    if [[ "$CIRCLECI_ENABLED" == "true" ]]; then
        all_extra_vars="circleci_enabled=true"
    else
        all_extra_vars="circleci_enabled=false"
    fi
    
    if [[ -n "$extra_vars" ]]; then
        all_extra_vars="$all_extra_vars,$extra_vars"
    fi
    
    if [[ -n "$all_extra_vars" ]]; then
        cmd="$cmd --extra-vars=\"$all_extra_vars\""
    fi
    
    # Add playbook path
    cmd="$cmd playbooks/$playbook"
    
    print_substep "Command: $cmd"
    
    # Dry run check
    if [[ "$DRY_RUN" == "true" ]]; then
        print_message $YELLOW "DRY RUN: Command would be executed but not actually run"
        return 0
    fi
    
    # Execute the playbook
    print_substep "Executing playbook..."
    if eval "$cmd"; then
        print_substep "Playbook execution completed successfully!"
        return 0
    else
        print_substep "Playbook execution failed!"
        return 1
    fi
}

# Function to show post-deployment information
show_post_deployment_info() {
    local mode="$1"
    
    print_header "Deployment Completed Successfully!"
    
    print_message $GREEN "Kubernetes cluster operation completed!"
    print_message $GREEN "Mode: $mode"
    print_message $GREEN "Completion time: $(date)"
    echo
    
    print_message $BLUE "Next steps:"
    
    case "$mode" in
        cluster-only*|deploy-circleci)
            print_message $BLUE "1. Check cluster status:"
            print_message $YELLOW "   kubectl get nodes -o wide"
            print_message $BLUE "2. Check all pods:"
            print_message $YELLOW "   kubectl get pods -A"
            if [[ "$CIRCLECI_ENABLED" == "true" || "$mode" == "deploy-circleci" ]]; then
                print_message $BLUE "3. Check CircleCI runner:"
                print_message $YELLOW "   kubectl get pods -n circleci"
                print_message $BLUE "4. Check runner logs:"
                print_message $YELLOW "   kubectl logs -n circleci -l app.kubernetes.io/name=container-agent"
            else
                print_message $BLUE "3. Verify cluster info:"
                print_message $YELLOW "   kubectl cluster-info"
            fi
            ;;
        add-node*|remove-node)
            print_message $BLUE "1. Verify cluster state:"
            print_message $YELLOW "   kubectl get nodes -o wide"
            print_message $BLUE "2. Check node labels:"
            print_message $YELLOW "   kubectl get nodes --show-labels"
            if [[ "$CIRCLECI_ENABLED" == "true" ]]; then
                print_message $BLUE "3. Check CircleCI runner:"
                print_message $YELLOW "   kubectl get pods -n circleci"
            fi
            ;;
    esac
    
    echo
    print_message $BLUE "Useful commands:"
    print_message $YELLOW "   kubectl get componentstatuses"
    print_message $YELLOW "   kubectl get events --all-namespaces"
    
    echo
    print_message $BLUE "For troubleshooting, check:"
    print_message $YELLOW "   - journalctl -u kubelet"
    print_message $YELLOW "   - kubectl get events --all-namespaces"
}

# Function to show usage
show_usage() {
    cat << EOF
Kubernetes Cluster Management Script (Kubespray-based)
========================================================

USAGE:
    $0 <MODE> [OPTIONS]

MODES:
    cluster-only        Deploy Kubernetes cluster using kubespray (default)
    deploy-circleci     Deploy CircleCI agent to existing cluster
    add-node           Add node to existing cluster (uses kubespray scale.yml)
    remove-node        Remove node from cluster (uses kubespray remove-node.yml)
    upgrade-cluster    Upgrade cluster to new version (uses kubespray upgrade-cluster.yml)
    reset-cluster      Reset/destroy entire cluster (uses kubespray reset.yml)

OPTIONS:
    -i, --inventory FILE        Inventory file (default: inventory/production/hosts.ini)
    -v, --vault-password FILE   Vault password file for encrypted variables
    -d, --dry-run              Check only without actual execution
    -vv, --verbose             Verbose ansible output (-vv)
    -vvv                       Very verbose ansible output (-vvv)
    --tags TAGS               Run only tasks with specified tags
    --enable-circleci         Enable CircleCI runner deployment (optional)
    --extra-vars VARS         Additional ansible variables (key=value,key2=value2)
    
    -h, --help                 Show this help message

EXAMPLES:
    # Deploy basic Kubernetes cluster (default)
    $0 cluster-only
    
    # Deploy cluster with CircleCI support
    $0 cluster-only --enable-circleci --vault-password .vault-password
    
    # Deploy CircleCI to existing cluster
    $0 deploy-circleci --enable-circleci --vault-password .vault-password
    
    # Add nodes with CircleCI support (update inventory first)
    $0 add-node --enable-circleci --vault-password .vault-password
    
    # Add nodes only (update inventory first)
    $0 add-node
    
    # Remove nodes (specify with extra vars)
    $0 remove-node --extra-vars "node=worker-1,worker-2"
    
    # Dry run with verbose output
    $0 cluster-only --dry-run -vv
    
    # Use staging environment
    $0 cluster-only -i inventory/staging/hosts.ini
    
    # Deploy only specific components
    $0 cluster-only --tags "etcd,kubernetes/master"

KUBESPRAY INTEGRATION:
    This script wraps kubespray playbooks with the following features:
    - cluster-only -> Uses kubespray/cluster.yml
    - add-node -> Uses kubespray/scale.yml  
    - remove-node -> Uses kubespray/remove-node.yml
    - upgrade-cluster -> Uses kubespray/upgrade-cluster.yml
    - reset-cluster -> Uses kubespray/reset.yml
    - deploy-circleci -> Uses custom CircleCI deployment
    
    Combined operations with --enable-circleci:
    - cluster-only + CircleCI -> cluster-only.yml + deploy-circleci.yml
    - add-node + CircleCI -> add-node.yml + deploy-circleci.yml
    
    Follow kubespray documentation for inventory management:
    - Add nodes: Update inventory, then run add-node
    - Remove nodes: Use --extra-vars "node=hostname1,hostname2"

REQUIREMENTS:
    - Ansible 9.13+ with Python 3.10+
    - Target nodes: Rocky Linux 8+, CentOS 8+, Ubuntu 20.04+
    - SSH access to target nodes (root or sudo user)
    - Internet connection for package downloads
    - Initialized kubespray submodule: 3rdparty/kubespray

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
        -vvv)
            VERBOSE="-vvv"
            shift
            ;;
        --tags)
            TAGS="$2"
            shift 2
            ;;
        --enable-circleci)
            CIRCLECI_ENABLED=true
            shift
            ;;
        --extra-vars)
            EXTRA_VARS="$2"
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
    cluster-only|add-node|deploy-circleci|remove-node|upgrade-cluster|reset-cluster)
        ;;
    *)
        print_message $RED "Invalid mode: $MODE"
        show_usage
        exit 1
        ;;
esac

# Auto-enable CircleCI for specific modes
case "$MODE" in
    deploy-circleci)
        CIRCLECI_ENABLED=true
        ;;
esac

# Change to project directory
cd "$PROJECT_DIR"

# Main execution
print_header "Kubernetes Cluster Management (Kubespray-based)"
print_message $BLUE "Mode: $MODE"
print_message $BLUE "Inventory: $INVENTORY"
print_message $BLUE "CircleCI enabled: $CIRCLECI_ENABLED"
print_message $BLUE "Dry run: $DRY_RUN"
if [[ -n "$VAULT_PASSWORD_FILE" ]]; then
    print_message $BLUE "Vault file: $VAULT_PASSWORD_FILE"
fi

# Execute based on mode
case "$MODE" in
    reset-cluster)
        print_message $YELLOW "Reset cluster mode - delegating to rollback script..."
        exec "$SCRIPT_DIR/rollback.sh" -i "$INVENTORY" ${VAULT_PASSWORD_FILE:+--vault-password "$VAULT_PASSWORD_FILE"} ${DRY_RUN:+--dry-run} --force
        ;;
    *)
        # Run all checks
        check_prerequisites
        detect_versions
        validate_inventory
        
        # Execute main playbook
        case "$MODE" in
            cluster-only)
                run_ansible_playbook "cluster-only.yml" "$TAGS" "" "$EXTRA_VARS"
                if [[ "$CIRCLECI_ENABLED" == "true" ]]; then
                    print_message $BLUE "Deploying CircleCI runner..."
                    run_ansible_playbook "deploy-circleci.yml" "" "" "$EXTRA_VARS"
                fi
                ;;
            add-node)
                run_ansible_playbook "add-node.yml" "$TAGS" "" "$EXTRA_VARS"
                if [[ "$CIRCLECI_ENABLED" == "true" ]]; then
                    print_message $BLUE "Deploying CircleCI runner to new nodes..."
                    run_ansible_playbook "deploy-circleci.yml" "" "" "$EXTRA_VARS"
                fi
                ;;
            deploy-circleci)
                run_ansible_playbook "deploy-circleci.yml" "$TAGS" "" "$EXTRA_VARS"
                ;;
            remove-node)
                run_ansible_playbook "remove-node.yml" "$TAGS" "" "$EXTRA_VARS"
                ;;
            upgrade-cluster)
                run_ansible_playbook "upgrade-cluster.yml" "$TAGS" "" "$EXTRA_VARS"
                ;;
        esac
        
        # Show post-deployment info
        show_post_deployment_info "$MODE"
        ;;
esac

print_header "Task Completed Successfully!"
print_message $GREEN "All operations completed at: $(date)" 