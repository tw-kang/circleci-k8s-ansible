#!/bin/bash

# Kubernetes Cluster Management Script (Kubespray-based)
# This script provides comprehensive Kubernetes cluster management using Kubespray
# with optional CircleCI support

set -e

#===============================================================================
# CONSTANTS AND CONFIGURATION
#===============================================================================

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly KUBESPRAY_DIR="$PROJECT_DIR/3rdparty/kubespray"

# Default values
MODE=""
INVENTORY="inventory/production/hosts.ini"
VAULT_PASSWORD_FILE=""
DRY_RUN=false
VERBOSE=""
TAGS=""
CIRCLECI_ENABLED=false
MONITORING_ENABLED=false
EXTRA_VARS=""

# Monitoring NodePorts (will be detected from cluster)
GRAFANA_NODEPORT=""
PROMETHEUS_NODEPORT=""
ALERTMANAGER_NODEPORT=""

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# Print colored messages
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

print_error() {
    local message=$1
    print_message $RED "ERROR: $message"
}

print_warning() {
    local message=$1
    print_message $YELLOW "WARNING: $message"
}

print_success() {
    local message=$1
    print_message $GREEN "SUCCESS: $message"
}

# Exit with error message
exit_with_error() {
    local message=$1
    print_error "$message"
    exit 1
}

# Get kubectl command path (using kubespray-generated kubectl.sh)
get_kubectl_cmd() {
    local inventory_dir=$(dirname "$INVENTORY")
    local kubectl_path="$inventory_dir/artifacts/kubectl.sh"
    
    if [[ -f "$kubectl_path" ]]; then
        echo "$kubectl_path"
    else
        # Fallback to system kubectl if artifacts not found
        echo "kubectl"
    fi
}

# Execute kubectl command locally using artifacts kubectl.sh
exec_kubectl() {
    local kubectl_cmd=$(get_kubectl_cmd)
    $kubectl_cmd "$@" 2>/dev/null
}

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================

# Check if command exists
check_command() {
    local cmd=$1
    local name=${2:-$cmd}
    
    if ! command -v "$cmd" &> /dev/null; then
        print_error "$name not found. Please install $name."
        return 1
    fi
    return 0
}

# Check if file/directory exists
check_path() {
    local path=$1
    local description=$2
    local type=${3:-"file"}
    
    if [[ "$type" == "dir" ]]; then
        if [[ ! -d "$path" ]]; then
            print_error "$description not found: $path"
            return 1
        fi
    else
        if [[ ! -f "$path" ]]; then
            print_error "$description not found: $path"
            return 1
        fi
    fi
    
    print_substep "$description found"
    return 0
}

# Check system prerequisites
check_prerequisites() {
    print_step "1" "Checking system prerequisites..."
    
    local errors=0
    
    # Check required commands (simplified)
    if command -v ansible-playbook >/dev/null 2>&1; then
        print_substep "Ansible found"
    else
        print_error "ansible-playbook not found"
        ((errors++))
    fi
    
    if command -v python3 >/dev/null 2>&1; then
        print_substep "Python 3 found"
    else
        print_error "python3 not found"
        ((errors++))
    fi
    
    # Check required paths
    if [[ -d "$KUBESPRAY_DIR" ]]; then
        print_substep "Kubespray found"
    else
        print_error "Kubespray not found: $KUBESPRAY_DIR"
        print_message $YELLOW "Please initialize kubespray submodule:"
        print_message $YELLOW "  git submodule update --init --recursive"
        ((errors++))
    fi
    
    if [[ -f "$INVENTORY" ]]; then
        print_substep "Inventory file found"
    else
        print_error "Inventory file not found: $INVENTORY"
        ((errors++))
    fi
    
    # Check required directory structure
    local inventory_dir=$(dirname "$INVENTORY")
    for dir in "$inventory_dir/group_vars/all" "$inventory_dir/group_vars/k8s_cluster"; do
        if [[ -d "$dir" ]]; then
            print_substep "Directory found: $dir"
        else
            print_error "Directory not found: $dir"
            ((errors++))
        fi
    done
    
    # Check CircleCI configuration if enabled
    if [[ "$CIRCLECI_ENABLED" == "true" ]]; then
        if [[ -d "inventory/production/group_vars/circleci" ]] || [[ -d "inventory/staging/group_vars/circleci" ]]; then
            print_substep "CircleCI configuration found"
        else
            print_error "CircleCI configuration missing: group_vars/circleci"
            ((errors++))
        fi
    fi
    
    if [[ $errors -gt 0 ]]; then
        exit_with_error "Prerequisites check failed with $errors error(s)"
    fi
    
    print_success "All prerequisites satisfied"
}

# Detect version information
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

# Validate inventory structure
validate_inventory() {
    print_step "3" "Validating inventory structure..."
    
    # Check if inventory can be parsed
    if ! ansible-inventory -i "$INVENTORY" --list >/dev/null 2>&1; then
        exit_with_error "Inventory parsing failed"
    fi
    
    # Check required groups
    local required_groups=("kube_control_plane" "kube_node" "etcd" "k8s_cluster")
    for group in "${required_groups[@]}"; do
        if ansible-inventory -i "$INVENTORY" --list 2>/dev/null | grep -q "\"$group\""; then
            print_substep "Group found: $group"
        else
            exit_with_error "Required group missing: $group"
        fi
    done
    
    # Count and validate nodes
    local control_plane_count=$(ansible kube_control_plane -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | wc -l)
    local worker_count=$(ansible kube_node -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | wc -l)
    local etcd_count=$(ansible etcd -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | wc -l)
    
    print_substep "Control plane nodes: $control_plane_count"
    print_substep "Total nodes: $worker_count" 
    print_substep "Etcd nodes: $etcd_count"
    
    [[ $control_plane_count -eq 0 ]] && exit_with_error "No control plane nodes found"
    [[ $etcd_count -eq 0 ]] && exit_with_error "No etcd nodes found"
    
    if [[ $etcd_count -gt 1 && $((etcd_count % 2)) -eq 0 ]]; then
        print_warning "Even number of etcd nodes ($etcd_count) - consider odd numbers for quorum"
    fi
}

#===============================================================================
# CLUSTER OPERATIONS
#===============================================================================

# Check if cluster exists
check_cluster_exists() {
    print_step "CLUSTER" "Checking if Kubernetes cluster exists..."
    
    print_substep "Testing cluster connectivity using kubectl..."
    
    if exec_kubectl cluster-info >/dev/null 2>&1; then
        print_substep "Kubernetes cluster is running and accessible"
        return 0
    else
        print_error "Kubernetes cluster is not running or not accessible"
        print_error "Please deploy cluster first using: $0 cluster-only"
        print_error "Make sure kubespray has created the kubectl.sh file in inventory artifacts"
        exit 1
    fi
}

# Check monitoring configuration and get actual NodePorts
check_monitoring_config() {
    # Check if monitoring namespace exists
    if exec_kubectl get namespace monitoring >/dev/null 2>&1; then
        print_substep "Monitoring namespace found - getting service information"
        
        # Get actual NodePort values from services
        GRAFANA_NODEPORT=$(exec_kubectl get service -n monitoring -o jsonpath='{.items[?(@.metadata.name=="kube-prometheus-stack-grafana")].spec.ports[0].nodePort}' 2>/dev/null | grep -o '[0-9]*' || echo "32000")
        PROMETHEUS_NODEPORT=$(exec_kubectl get service -n monitoring -o jsonpath='{.items[?(@.metadata.name=="kube-prometheus-stack-prometheus")].spec.ports[0].nodePort}' 2>/dev/null | grep -o '[0-9]*' || echo "32001")
        ALERTMANAGER_NODEPORT=$(exec_kubectl get service -n monitoring -o jsonpath='{.items[?(@.metadata.name=="kube-prometheus-stack-alertmanager")].spec.ports[0].nodePort}' 2>/dev/null | grep -o '[0-9]*' || echo "32002")
        
        print_substep "Grafana NodePort: ${GRAFANA_NODEPORT:-32000} (actual)"
        print_substep "Prometheus NodePort: ${PROMETHEUS_NODEPORT:-32001} (actual)"
        print_substep "AlertManager NodePort: ${ALERTMANAGER_NODEPORT:-32002} (actual)"
    else
        # Monitoring not deployed, use default values
        print_substep "Monitoring namespace not found - using default port values"
        GRAFANA_NODEPORT="32000"
        PROMETHEUS_NODEPORT="32001"
        ALERTMANAGER_NODEPORT="32002"
        
        print_substep "Grafana NodePort: ${GRAFANA_NODEPORT} (default)"
        print_substep "Prometheus NodePort: ${PROMETHEUS_NODEPORT} (default)"
        print_substep "AlertManager NodePort: ${ALERTMANAGER_NODEPORT} (default)"
    fi
}

# Deploy monitoring stack if enabled
deploy_monitoring_if_enabled() {
    if [[ "$MONITORING_ENABLED" == "true" ]]; then
        print_message $BLUE "Deploying monitoring stack..."
        run_ansible_playbook "deploy-monitoring.yml" "" "" "$EXTRA_VARS"
    fi
}

# Deploy CircleCI if enabled
deploy_circleci_if_enabled() {
    if [[ "$CIRCLECI_ENABLED" == "true" ]]; then
        print_message $BLUE "Deploying CircleCI runner..."
        run_ansible_playbook "deploy-circleci.yml" "" "" "$EXTRA_VARS"
    fi
}

# Execute deployment based on mode
execute_deployment_mode() {
    local mode="$1"
    
    case "$mode" in
        cluster-only)
            # Deploy cluster → monitoring → CircleCI (in order)
            run_ansible_playbook "cluster-only.yml" "$TAGS" "" "$EXTRA_VARS"
            deploy_monitoring_if_enabled
            deploy_circleci_if_enabled
            ;;
        add-node)
            # Add nodes → update monitoring → update CircleCI
            run_ansible_playbook "add-node.yml" "$TAGS" "" "$EXTRA_VARS"
            
            if [[ "$MONITORING_ENABLED" == "true" ]]; then
                print_message $BLUE "Updating monitoring stack for new nodes..."
                run_ansible_playbook "deploy-monitoring.yml" "" "" "$EXTRA_VARS"
            fi
            
            if [[ "$CIRCLECI_ENABLED" == "true" ]]; then
                print_message $BLUE "Deploying CircleCI runner to new nodes..."
                run_ansible_playbook "deploy-circleci.yml" "" "" "$EXTRA_VARS"
            fi
            ;;
        deploy-circleci)
            # Check cluster exists before deploying CircleCI
            check_cluster_exists
            run_ansible_playbook "deploy-circleci.yml" "$TAGS" "" "$EXTRA_VARS"
            ;;
        remove-node)
            run_ansible_playbook "remove-node.yml" "$TAGS" "" "$EXTRA_VARS"
            ;;
        upgrade-cluster)
            run_ansible_playbook "upgrade-cluster.yml" "$TAGS" "" "$EXTRA_VARS"
            ;;
        *)
            exit_with_error "Unknown deployment mode: $mode"
            ;;
    esac
}

# Build and execute ansible command
run_ansible_playbook() {
    local playbook="$1"
    local tags="$2"
    local limit="$3"
    local extra_vars="$4"
    
    print_step "4" "Running Ansible playbook: $playbook"
    
    # Build base command
    local cmd="ansible-playbook -i \"$INVENTORY\""
    
    # Add optional parameters
    # Only add vault-password-file if explicitly provided (ansible.cfg handles default)
    if [[ -n "$VAULT_PASSWORD_FILE" ]]; then
        cmd="$cmd --vault-password-file=\"$VAULT_PASSWORD_FILE\""
        print_substep "Using explicit vault password file: $VAULT_PASSWORD_FILE"
    else
        print_substep "Using ansible.cfg vault configuration (if any)"
    fi
    [[ -n "$VERBOSE" ]] && cmd="$cmd $VERBOSE"
    [[ -n "$tags" ]] && cmd="$cmd --tags=\"$tags\""
    [[ -n "$limit" ]] && cmd="$cmd --limit=\"$limit\""
    
    # Prepare extra vars
    local all_extra_vars="circleci_enabled=$CIRCLECI_ENABLED"
    [[ -n "$extra_vars" ]] && all_extra_vars="$all_extra_vars $extra_vars"
    cmd="$cmd --extra-vars \"$all_extra_vars\""
    
    # Add playbook path
    cmd="$cmd playbooks/$playbook"
    
    print_substep "Command: $cmd"
    
    # Execute or dry run
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Command would be executed but not actually run"
        return 0
    fi
    
    print_substep "Executing playbook..."
    if eval "$cmd"; then
        print_success "Playbook execution completed successfully!"
        return 0
    else
        print_error "Playbook execution failed!"
        return 1
    fi
}

#===============================================================================
# COMPLETION AND USAGE FUNCTIONS
#===============================================================================

# Show basic cluster status checks
show_basic_cluster_checks() {
    local mode="$1"
    local kubectl_cmd=$(get_kubectl_cmd)
    
    case "$mode" in
        cluster-only*|deploy-circleci)
            print_message $BLUE "1. Check cluster status:"
            print_message $YELLOW "   $kubectl_cmd get nodes -o wide"
            print_message $BLUE "2. Check all pods:"
            print_message $YELLOW "   $kubectl_cmd get pods -A"
            ;;
        add-node*|remove-node)
            print_message $BLUE "1. Verify cluster state:"
            print_message $YELLOW "   $kubectl_cmd get nodes -o wide"
            print_message $BLUE "2. Check node labels:"
            print_message $YELLOW "   $kubectl_cmd get nodes --show-labels"
            ;;
    esac
}

# Show CircleCI-specific checks
show_circleci_checks() {
    local mode="$1"
    local kubectl_cmd=$(get_kubectl_cmd)
    
    if [[ "$CIRCLECI_ENABLED" == "true" || "$mode" == "deploy-circleci" ]]; then
        print_message $BLUE "3. Check CircleCI runner (if deployed):"
        print_message $YELLOW "   $kubectl_cmd get namespaces | grep circleci  # Check if namespace exists"
        print_message $YELLOW "   $kubectl_cmd get pods -n cubrid  # Default CircleCI namespace"
        print_message $BLUE "4. Check runner logs (if deployed):"
        print_message $YELLOW "   $kubectl_cmd logs -n cubrid -l app=container-agent"
    fi
}

# Show monitoring-specific checks
show_monitoring_checks() {
    local mode="$1"
    local kubectl_cmd=$(get_kubectl_cmd)
    
    if [[ "$MONITORING_ENABLED" == "true" ]]; then
        print_message $BLUE "5. Check monitoring stack (if deployed):"
        print_message $YELLOW "   $kubectl_cmd get namespaces | grep monitoring  # Check if namespace exists"
        print_message $YELLOW "   $kubectl_cmd get pods -n monitoring  # If monitoring namespace exists"
        
        case "$mode" in
            cluster-only*|deploy-circleci)
                print_message $BLUE "6. Access monitoring services (if deployed):"
                print_message $YELLOW "   # First verify services exist:"
                print_message $YELLOW "   $kubectl_cmd get services -n monitoring"
                print_message $YELLOW "   # NodePort access (replace NODE_IP with actual node IP):"
                print_message $YELLOW "   # Grafana: http://NODE_IP:${GRAFANA_NODEPORT:-32000}"
                print_message $YELLOW "   # Prometheus: http://NODE_IP:${PROMETHEUS_NODEPORT:-32001}"
                print_message $YELLOW "   # AlertManager: http://NODE_IP:${ALERTMANAGER_NODEPORT:-32002}"
                print_message $YELLOW "   # Port-forward access (run locally):"
                print_message $YELLOW "   $kubectl_cmd port-forward -n monitoring service/kube-prometheus-stack-grafana 3000:80"
                ;;
        esac
    fi
}

# Show completion summary with post-deployment instructions
show_completion_summary() {
    local mode="$1"
    local kubectl_cmd=$(get_kubectl_cmd)
    echo
    print_header "DEPLOYMENT COMPLETED SUCCESSFULLY"
    
    print_message $GREEN "Mode: $mode"
    print_message $GREEN "Completion time: $(date)"
    echo
    
    # Check monitoring configuration if monitoring is enabled
    if [[ "$MONITORING_ENABLED" == "true" ]]; then
        check_monitoring_config
    fi
    
    print_message $BLUE "Next steps (run kubectl commands locally or on any node):"
    
    # Common cluster checks
    show_basic_cluster_checks "$mode"
    
    # Component-specific checks
    show_circleci_checks "$mode"
    show_monitoring_checks "$mode"
    
    # Final cluster info for basic deployments
    if [[ "$CIRCLECI_ENABLED" != "true" && "$mode" != "deploy-circleci" && "$MONITORING_ENABLED" != "true" ]]; then
        print_message $BLUE "7. Verify cluster info:"
        print_message $YELLOW "   $kubectl_cmd cluster-info"
    fi
    
    echo
    print_message $BLUE "Useful commands (run locally using kubectl.sh):"
    print_message $YELLOW "   $kubectl_cmd get componentstatuses"
    print_message $YELLOW "   $kubectl_cmd get events --all-namespaces"
    print_message $YELLOW "   $kubectl_cmd get namespaces  # List all namespaces"
    
    echo
    print_message $BLUE "For troubleshooting, check:"
    print_message $YELLOW "   - journalctl -u kubelet (on all nodes)"
    print_message $YELLOW "   - $kubectl_cmd get events --all-namespaces (locally)"
    print_message $YELLOW "   - $kubectl_cmd describe nodes (locally)"
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
    # Deploy Kubernetes cluster with monitoring stack (default) 
    $0 cluster-only
    
    # Deploy cluster + monitoring + CircleCI (full deployment)
    $0 cluster-only --enable-circleci --vault-password .vault-password
    
    # Deploy CircleCI to existing cluster (checks cluster exists first)
    $0 deploy-circleci --vault-password .vault-password
    
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
    
    Combined operations:
    - cluster-only: cluster-only.yml + deploy-monitoring.yml (always) + deploy-circleci.yml (if --enable-circleci)
    - cluster-only --enable-circleci: cluster-only.yml + deploy-monitoring.yml + deploy-circleci.yml (in order)
    - add-node: add-node.yml + deploy-monitoring.yml (if needed) + deploy-circleci.yml (if --enable-circleci)
    - deploy-circleci: Requires existing cluster (cluster check performed first)
    
    Note: Monitoring stack is always deployed with cluster operations for observability
    
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

#===============================================================================
# MAIN EXECUTION
#===============================================================================

# Configure monitoring based on mode
configure_monitoring_for_mode() {
    case "$MODE" in
        cluster-only|add-node|deploy-circleci)
            MONITORING_ENABLED=true
            print_message $BLUE "Monitoring stack enabled by default"
            ;;
        remove-node|upgrade-cluster|reset-cluster)
            MONITORING_ENABLED=false
            ;;
    esac
}

# Display execution configuration
show_execution_config() {
    print_header "Kubernetes Cluster Management (Kubespray-based)"
    print_message $BLUE "Mode: $MODE"
    print_message $BLUE "Inventory: $INVENTORY"
    print_message $BLUE "CircleCI enabled: $CIRCLECI_ENABLED"
    print_message $BLUE "Monitoring enabled: $MONITORING_ENABLED"
    print_message $BLUE "Dry run: $DRY_RUN"
    if [[ -n "$VAULT_PASSWORD_FILE" ]]; then
        print_message $BLUE "Vault file: $VAULT_PASSWORD_FILE"
    fi
}

# Execute main workflow
main() {
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Configure components
    configure_monitoring_for_mode
    
    # Show configuration
    show_execution_config
    
    # Handle special modes
    if [[ "$MODE" == "reset-cluster" ]]; then
        print_message $YELLOW "Reset cluster mode - delegating to rollback script..."
        exec "$SCRIPT_DIR/rollback.sh" -i "$INVENTORY" \
            ${VAULT_PASSWORD_FILE:+--vault-password "$VAULT_PASSWORD_FILE"} \
            ${DRY_RUN:+--dry-run} \
            ${VERBOSE:+$VERBOSE} --force
    fi
    
    # Standard workflow: validate → execute → summarize
    check_prerequisites
    detect_versions
    validate_inventory
    execute_deployment_mode "$MODE"
    show_completion_summary "$MODE"
    
    # Success message
    print_header "Task Completed Successfully!"
    print_message $GREEN "All operations completed at: $(date)"
}

# Run main function
main 