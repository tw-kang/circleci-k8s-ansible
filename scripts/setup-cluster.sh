#!/bin/bash

# CircleCI Kubernetes Cluster Setup Script
# This script sets up a complete Kubernetes cluster with CircleCI container runners

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

OPTIONS:
    -p, --playbook PLAYBOOK     Specify playbook to run (default: site.yml)
    -i, --inventory INVENTORY   Specify inventory file (default: inventory/hosts.yml)
    -t, --tags TAGS            Run only tasks with specific tags
    -s, --skip-tags TAGS       Skip tasks with specific tags
    -v, --vault-password FILE  Vault password file
    -d, --dry-run              Perform a dry run (check mode)
    -vv, --verbose             Verbose output
    -h, --help                 Show this help message

EXAMPLES:
    # Full cluster setup
    $0

    # Only Kubernetes cluster (no CircleCI)
    $0 -p playbooks/k8s-cluster.yml

    # Only CircleCI runner deployment
    $0 -p playbooks/circleci-runner.yml

    # Dry run to check what would be changed
    $0 --dry-run

    # Run with specific tags
    $0 --tags "kubernetes,common"

    # Skip CircleCI deployment
    $0 --skip-tags "circleci"

    # Use vault password file
    $0 --vault-password ~/.ansible-vault-pass

EOF
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
print_message $BLUE "========================================="

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    print_message $RED "Error: ansible-playbook is not installed"
    print_message $YELLOW "Please install Ansible first:"
    print_message $YELLOW "  pip install ansible"
    exit 1
fi

# Check if kubernetes collection is installed
if ! ansible-galaxy collection list | grep -q kubernetes.core; then
    print_message $YELLOW "Installing Kubernetes Ansible collection..."
    ansible-galaxy collection install kubernetes.core
fi

# Verify inventory file exists
if [[ ! -f "$INVENTORY" ]]; then
    print_message $RED "Error: Inventory file '$INVENTORY' not found"
    exit 1
fi

# Verify playbook exists
if [[ ! -f "playbooks/$PLAYBOOK" && ! -f "$PLAYBOOK" ]]; then
    print_message $RED "Error: Playbook '$PLAYBOOK' not found"
    exit 1
fi

# Set full path for playbook if not already set
if [[ ! -f "$PLAYBOOK" ]]; then
    PLAYBOOK="playbooks/$PLAYBOOK"
fi

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
if eval "$ANSIBLE_CMD"; then
    print_message $GREEN "========================================="
    print_message $GREEN "Setup completed successfully!"
    print_message $GREEN "========================================="
    
    if [[ "$PLAYBOOK" == *"site.yml"* || "$PLAYBOOK" == *"k8s-cluster.yml"* ]]; then
        print_message $GREEN "Next steps:"
        print_message $GREEN "1. Check cluster status: kubectl get nodes"
        print_message $GREEN "2. Check pods: kubectl get pods -A"
        if [[ "$PLAYBOOK" == *"site.yml"* ]]; then
            print_message $GREEN "3. Check CircleCI runners: kubectl get pods -n circleci"
        fi
    fi
else
    print_message $RED "Setup failed!"
    exit 1
fi 