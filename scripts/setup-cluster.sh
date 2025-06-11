#!/bin/bash

# CircleCI Kubernetes Cluster Setup Script
# This script sets up a complete Kubernetes cluster with CircleCI container runners
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
PLAYBOOK="site.yml"
INVENTORY="inventory/hosts.yml"
TAGS=""
SKIP_TAGS=""
VAULT_PASSWORD_FILE=""
DRY_RUN=false
VERBOSE=""

# Current supported versions
KUBERNETES_VERSION="1.28.15"
CONTAINERD_VERSION="1.7.27"

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

CircleCI Kubernetes Cluster Setup Script
Supports: Kubernetes v${KUBERNETES_VERSION}, containerd v${CONTAINERD_VERSION}, ARM64/x86_64

OPTIONS:
    -p, --playbook PLAYBOOK     Specify playbook to run (default: site.yml)
    -i, --inventory INVENTORY   Specify inventory file (default: inventory/hosts.yml)
    -t, --tags TAGS            Run only tasks with specific tags
    -s, --skip-tags TAGS       Skip tasks with specific tags
    -v, --vault-password FILE  Vault password file
    -d, --dry-run              Perform a dry run (check mode)
    -vv, --verbose             Verbose output
    -h, --help                 Show this help message

AVAILABLE PLAYBOOKS:
    site.yml                   Full setup (Kubernetes + CircleCI)
    k8s-cluster.yml           Kubernetes cluster only
    circleci-runner.yml       CircleCI runner only
    site-with-rollback.yml    Full setup with rollback capability

EXAMPLES:
    # Full cluster setup (recommended)
    $0

    # Only Kubernetes cluster (no CircleCI)
    $0 -p k8s-cluster.yml

    # Only CircleCI runner deployment
    $0 -p circleci-runner.yml

    # Dry run to check what would be changed
    $0 --dry-run

    # Run with specific tags
    $0 --tags "kubernetes,common"

    # Skip CircleCI deployment
    $0 --skip-tags "circleci"

    # Use vault password file
    $0 --vault-password ~/.ansible-vault-pass

ARCHITECTURE SUPPORT:
    - x86_64: Full support with Calico CNI
    - ARM64: Full support with Flannel CNI
    - Auto-detection and configuration based on target architecture

REQUIREMENTS:
    - Ansible 2.9+
    - Target nodes: Rocky Linux 8 or compatible
    - SSH access to target nodes
    - Internet connectivity for package downloads

EOF
}

# Function to detect system architecture
detect_target_architecture() {
    if [[ -f "$INVENTORY" ]]; then
        print_message $BLUE "Detecting target system architecture..."
        local arch=$(ansible all -i "$INVENTORY" -m setup -a "filter=ansible_architecture" --one-line 2>/dev/null | head -1 | grep -o 'aarch64\|x86_64' || echo "unknown")
        
        case "$arch" in
            "aarch64")
                print_message $GREEN "Target architecture: ARM64 (aarch64)"
                print_message $YELLOW "Will use Flannel CNI for ARM64 compatibility"
                ;;
            "x86_64")
                print_message $GREEN "Target architecture: x86_64"
                print_message $YELLOW "Will use Calico CNI for x86_64 performance"
                ;;
            *)
                print_message $YELLOW "Could not detect target architecture or mixed architectures"
                print_message $YELLOW "Please ensure all nodes have the same architecture"
                ;;
        esac
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--playbook)
            PLAYBOOK="$2"
            shift 2
            ;;
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -t|--tags)
            TAGS="$2"
            shift 2
            ;;
        -s|--skip-tags)
            SKIP_TAGS="$2"
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

# Change to project directory
cd "$PROJECT_DIR"

print_message $BLUE "========================================="
print_message $BLUE "CircleCI Kubernetes Cluster Setup"
print_message $BLUE "Kubernetes: v${KUBERNETES_VERSION}"
print_message $BLUE "containerd: v${CONTAINERD_VERSION}"
print_message $BLUE "========================================="

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    print_message $RED "Error: ansible-playbook is not installed"
    print_message $YELLOW "Please install Ansible first:"
    print_message $YELLOW "  dnf install ansible"
    exit 1
fi

# Check Ansible version
ANSIBLE_VERSION=$(ansible-playbook --version | head -1 | grep -o '[0-9]\+\.[0-9]\+' | head -1)
print_message $GREEN "Ansible version: $ANSIBLE_VERSION"

# Check if kubernetes collection is installed
print_message $BLUE "Checking Ansible collections..."
if ! ansible-galaxy collection list | grep -q kubernetes.core; then
    print_message $YELLOW "Installing Kubernetes Ansible collection..."
    ansible-galaxy collection install kubernetes.core
fi

# Install requirements if file exists
if [[ -f "requirements.yml" ]]; then
    print_message $BLUE "Installing Ansible requirements..."
    ansible-galaxy collection install -r requirements.yml
fi

# Verify inventory file exists
if [[ ! -f "$INVENTORY" ]]; then
    print_message $RED "Error: Inventory file '$INVENTORY' not found"
    print_message $YELLOW "Please create an inventory file with your target nodes"
    exit 1
fi

# Verify playbook exists
if [[ ! -f "playbooks/$PLAYBOOK" && ! -f "$PLAYBOOK" ]]; then
    print_message $RED "Error: Playbook '$PLAYBOOK' not found"
    print_message $YELLOW "Available playbooks:"
    ls -1 playbooks/*.yml 2>/dev/null | sed 's/playbooks\//  /' || echo "  No playbooks found"
    exit 1
fi

# Set full path for playbook if not already set
if [[ ! -f "$PLAYBOOK" ]]; then
    PLAYBOOK="playbooks/$PLAYBOOK"
fi

# Test connectivity to target nodes
print_message $BLUE "Testing connectivity to target nodes..."
if ansible all -i "$INVENTORY" -m ping --one-line 2>/dev/null | grep -q SUCCESS; then
    print_message $GREEN "✓ All nodes are reachable"
else
    print_message $YELLOW "⚠ Some nodes may not be reachable, continuing anyway..."
fi

# Detect target architecture
detect_target_architecture

print_message $GREEN "Configuration:"
print_message $GREEN "  Playbook: $PLAYBOOK"
print_message $GREEN "  Inventory: $INVENTORY"
[[ -n "$TAGS" ]] && print_message $GREEN "  Tags: $TAGS"
[[ -n "$SKIP_TAGS" ]] && print_message $GREEN "  Skip Tags: $SKIP_TAGS"
[[ "$DRY_RUN" == true ]] && print_message $YELLOW "  Mode: DRY RUN"
echo

# Build ansible-playbook command
ANSIBLE_CMD="ansible-playbook -i $INVENTORY $PLAYBOOK"

# Add options
[[ -n "$TAGS" ]] && ANSIBLE_CMD="$ANSIBLE_CMD --tags $TAGS"
[[ -n "$SKIP_TAGS" ]] && ANSIBLE_CMD="$ANSIBLE_CMD --skip-tags $SKIP_TAGS"
[[ -n "$VAULT_PASSWORD_FILE" ]] && ANSIBLE_CMD="$ANSIBLE_CMD --vault-password-file $VAULT_PASSWORD_FILE"
[[ "$DRY_RUN" == true ]] && ANSIBLE_CMD="$ANSIBLE_CMD --check --diff"
[[ -n "$VERBOSE" ]] && ANSIBLE_CMD="$ANSIBLE_CMD $VERBOSE"

print_message $BLUE "Executing: $ANSIBLE_CMD"
echo

# Ask for confirmation if not dry run
if [[ "$DRY_RUN" != true ]]; then
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message $YELLOW "Operation cancelled"
        exit 0
    fi
fi

# Execute the playbook
print_message $BLUE "Starting execution at $(date)"
if eval "$ANSIBLE_CMD"; then
    print_message $GREEN "========================================="
    print_message $GREEN "Setup completed successfully!"
    print_message $GREEN "Completed at: $(date)"
    print_message $GREEN "========================================="
    
    if [[ "$PLAYBOOK" == *"site.yml"* || "$PLAYBOOK" == *"k8s-cluster.yml"* ]]; then
        print_message $GREEN "Next steps:"
        print_message $GREEN "1. Check cluster status:"
        print_message $GREEN "   export KUBECONFIG=/etc/kubernetes/admin.conf"
        print_message $GREEN "   kubectl get nodes"
        print_message $GREEN "2. Check all pods:"
        print_message $GREEN "   kubectl get pods -A"
        print_message $GREEN "3. Check cluster info:"
        print_message $GREEN "   kubectl cluster-info"
        if [[ "$PLAYBOOK" == *"site.yml"* ]]; then
            print_message $GREEN "4. Check CircleCI runners:"
            print_message $GREEN "   kubectl get pods -n circleci"
        fi
        echo
        print_message $BLUE "Cluster access information saved to:"
        print_message $BLUE "  /tmp/k8s-cluster-info.md (on master node)"
    fi
else
    print_message $RED "Setup failed!"
    print_message $RED "Check the error output above for details"
    exit 1
fi 