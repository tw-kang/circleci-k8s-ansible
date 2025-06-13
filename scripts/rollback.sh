#!/bin/bash

# Kubernetes Cluster Rollback Script
# This script helps rollback failed Kubernetes installations

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="$PROJECT_DIR"

# Default values
ROLLBACK_LEVEL="full"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/production/hosts.yml"
VAULT_PASSWORD_FILE=""
DRY_RUN=false
FORCE=false
INTERACTIVE=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to display help
show_help() {
    cat << EOF
Kubernetes Cluster Rollback Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -l, --level LEVEL           Rollback level (full, partial, services-only)
                               Default: full
    -i, --inventory FILE        Ansible inventory file
                               Default: inventory/production/hosts.yml
    -v, --vault-password FILE   Vault password file
    -d, --dry-run              Show what would be done without executing
    -f, --force                Skip confirmation prompts
    -q, --quiet                Non-interactive mode
    -h, --help                 Show this help message

ROLLBACK LEVELS:
    full            Complete rollback - removes all packages, configs, and data
    partial         Remove cluster configs but keep packages
    services-only   Stop services only, keep everything else

EXAMPLES:
    # Full rollback with confirmation
    $0

    # Partial rollback without confirmation
    $0 --level partial --force

    # Dry run to see what would be done
    $0 --dry-run

    # Use specific inventory and vault file
    $0 -i inventory/production/hosts.yml -v ~/.ansible-vault-pass

EOF
}

# Function to validate rollback level
validate_rollback_level() {
    local level="$1"
    case "$level" in
        full|partial|services-only)
            return 0
            ;;
        *)
            print_error "Invalid rollback level: $level"
            print_error "Valid levels: full, partial, services-only"
            exit 1
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if ansible is installed
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "ansible-playbook not found. Please install Ansible."
        exit 1
    fi
    
    # Check if inventory file exists
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        print_error "Inventory file not found: $INVENTORY_FILE"
        exit 1
    fi
    
    # Check if rollback playbook exists
    local rollback_playbook="$ANSIBLE_DIR/playbooks/rollback.yml"
    if [[ ! -f "$rollback_playbook" ]]; then
        print_error "Rollback playbook not found: $rollback_playbook"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to display current system status
show_system_status() {
    print_status "Current System Status:"
    
    # Check Kubernetes services
    print_status "Checking Kubernetes services..."
    ansible all -i "$INVENTORY_FILE" -m shell -a "systemctl is-active kubelet containerd 2>/dev/null || echo 'Services not found'" --become 2>/dev/null | grep -E "(SUCCESS|FAILED)" || true
    
    # Check Kubernetes packages
    print_status "Checking Kubernetes packages..."
    ansible all -i "$INVENTORY_FILE" -m shell -a "rpm -qa | grep -E '(kubelet|kubeadm|kubectl|containerd)' | head -5 || echo 'No K8s packages found'" --become 2>/dev/null | grep -E "(SUCCESS|FAILED)" || true
    
    # Check cluster status (if accessible)
    print_status "Checking cluster status..."
    ansible k8s_masters -i "$INVENTORY_FILE" -m shell -a "kubectl get nodes 2>/dev/null || echo 'Cluster not accessible'" --become 2>/dev/null | grep -E "(SUCCESS|FAILED)" || true
}

# Function to confirm rollback
confirm_rollback() {
    if [[ "$INTERACTIVE" == "true" && "$FORCE" == "false" ]]; then
        echo
        print_warning "⚠️  DANGER: This will rollback your Kubernetes installation!"
        print_warning "Rollback Level: $ROLLBACK_LEVEL"
        echo
        
        case "$ROLLBACK_LEVEL" in
            full)
                print_warning "This will:"
                print_warning "- Stop all Kubernetes services"
                print_warning "- Remove all Kubernetes packages"
                print_warning "- Delete all cluster data and configurations"
                print_warning "- Reset network configurations"
                print_warning "- Remove containerd (if installed via script)"
                ;;
            partial)
                print_warning "This will:"
                print_warning "- Stop Kubernetes services"
                print_warning "- Reset cluster configurations"
                print_warning "- Keep packages installed"
                ;;
            services-only)
                print_warning "This will:"
                print_warning "- Stop Kubernetes services only"
                print_warning "- Keep packages and configurations"
                ;;
        esac
        
        echo
        read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
        if [[ "$confirm" != "yes" ]]; then
            print_status "Rollback cancelled by user."
            exit 0
        fi
    fi
}

# Function to execute rollback
execute_rollback() {
    print_status "Starting rollback process..."
    
    # Build ansible-playbook command
    local cmd="ansible-playbook"
    cmd+=" -i $INVENTORY_FILE"
    cmd+=" $ANSIBLE_DIR/playbooks/rollback.yml"
    cmd+=" -e rollback_level=$ROLLBACK_LEVEL"
    
    # Add vault password file if specified
    if [[ -n "$VAULT_PASSWORD_FILE" ]]; then
        cmd+=" --vault-password-file $VAULT_PASSWORD_FILE"
    fi
    
    # Add extra options
    cmd+=" --become"
    
    # Execute dry run if requested
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "DRY RUN - Command that would be executed:"
        echo "$cmd --check --diff"
        echo
        print_status "Executing dry run..."
        $cmd --check --diff
        print_status "Dry run completed. No changes were made."
        return 0
    fi
    
    # Execute actual rollback
    print_status "Executing rollback command:"
    echo "$cmd"
    echo
    
    if $cmd; then
        print_success "Rollback completed successfully!"
        
        # Show post-rollback status
        echo
        print_status "Post-rollback system status:"
        show_system_status
        
        echo
        print_status "Rollback Summary:"
        print_status "- Level: $ROLLBACK_LEVEL"
        print_status "- Timestamp: $(date)"
        print_status "- Log location: Check /tmp/rollback-*.log on target hosts"
        
        echo
        print_warning "Recommended next steps:"
        print_warning "1. Reboot all nodes for complete cleanup"
        print_warning "2. Verify no remaining processes: ps aux | grep -E '(kube|contain)'"
        print_warning "3. Check for remaining config files: ls -la /etc/ | grep -E '(kube|contain)'"
        
    else
        print_error "Rollback failed! Check the error output above."
        exit 1
    fi
}

# Function to save rollback state
save_rollback_state() {
    local state_file="/tmp/rollback-state-$(date +%s).json"
    
    cat > "$state_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "rollback_level": "$ROLLBACK_LEVEL",
    "inventory_file": "$INVENTORY_FILE",
    "dry_run": $DRY_RUN,
    "user": "$(whoami)",
    "host": "$(hostname)",
    "pwd": "$(pwd)"
}
EOF
    
    print_status "Rollback state saved to: $state_file"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--level)
            ROLLBACK_LEVEL="$2"
            validate_rollback_level "$ROLLBACK_LEVEL"
            shift 2
            ;;
        -i|--inventory)
            INVENTORY_FILE="$2"
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
            shift
            ;;
        -q|--quiet)
            INTERACTIVE=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "======================================"
    echo "  Kubernetes Cluster Rollback Tool"
    echo "======================================"
    echo
    
    # Validate and show configuration
    print_status "Configuration:"
    print_status "- Rollback Level: $ROLLBACK_LEVEL"
    print_status "- Inventory File: $INVENTORY_FILE"
    print_status "- Vault Password File: ${VAULT_PASSWORD_FILE:-'(not specified)'}"
    print_status "- Dry Run: $DRY_RUN"
    print_status "- Force: $FORCE"
    print_status "- Interactive: $INTERACTIVE"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Show current system status
    if [[ "$DRY_RUN" == "false" ]]; then
        show_system_status
    fi
    
    # Confirm rollback
    confirm_rollback
    
    # Save rollback state
    save_rollback_state
    
    # Execute rollback
    execute_rollback
    
    print_success "Rollback process completed!"
}

# Run main function
main 