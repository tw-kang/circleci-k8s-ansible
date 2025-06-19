#!/bin/bash

# Kubernetes Tools Verification Script
# This script verifies kubeadm and kubectl installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_message $BLUE "========================================="
print_message $BLUE "Kubernetes Tools Installation Verification Script"
print_message $BLUE "========================================="

# Default values
INVENTORY="inventory/production/hosts.yml"
TARGET_HOST=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -t|--target)
            TARGET_HOST="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -i, --inventory FILE   inventory file (default: inventory/production/hosts.yml)"
            echo "  -t, --target HOST      target host (default: all hosts)"
            echo "  -h, --help            show help"
            exit 0
            ;;
        *)
            print_message $RED "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if inventory file exists
if [[ ! -f "$INVENTORY" ]]; then
    print_message $RED "Error: inventory file not found: $INVENTORY"
    exit 1
fi

# Build ansible command
ANSIBLE_CMD="ansible"
if [[ -n "$TARGET_HOST" ]]; then
    ANSIBLE_CMD="$ANSIBLE_CMD $TARGET_HOST"
else
    ANSIBLE_CMD="$ANSIBLE_CMD all"
fi
ANSIBLE_CMD="$ANSIBLE_CMD -i $INVENTORY"

print_message $GREEN "🔍 Checking Kubernetes tools installation status..."
echo

# Check kubeadm installation
print_message $BLUE "=== kubeadm Installation Check ==="
$ANSIBLE_CMD -m shell -a "
export PATH=\"/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:\$PATH\"
if command -v kubeadm >/dev/null 2>&1; then
    echo \"✅ kubeadm installed: \$(kubeadm version --output=short 2>/dev/null || kubeadm version 2>/dev/null | head -1)\"
    echo \"📍 Location: \$(which kubeadm)\"
else
    echo \"❌ kubeadm is not installed\"
fi
" --one-line 2>/dev/null || print_message $RED "kubeadm check failed"

echo

# Check kubectl installation
print_message $BLUE "=== kubectl Installation Check ==="
$ANSIBLE_CMD -m shell -a "
export PATH=\"/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:\$PATH\"
if command -v kubectl >/dev/null 2>&1; then
    echo \"✅ kubectl installed: \$(kubectl version --client 2>/dev/null | head -1 || echo 'kubectl available')\"
    echo \"📍 Location: \$(which kubectl)\"
else
    echo \"❌ kubectl is not installed\"
fi
" --one-line || print_message $RED "kubectl check failed"

echo

# Check kubelet installation and status
print_message $BLUE "=== kubelet Installation and Status Check ==="
$ANSIBLE_CMD -m shell -a "
export PATH=\"/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:\$PATH\"
if command -v kubelet >/dev/null 2>&1; then
    echo \"✅ kubelet installed: \$(kubelet --version 2>/dev/null)\"
    echo \"📍 Location: \$(which kubelet)\"
    echo \"🔄 Service status: \$(systemctl is-active kubelet 2>/dev/null || echo 'inactive')\"
    echo \"📋 Service enabled: \$(systemctl is-enabled kubelet 2>/dev/null || echo 'disabled')\"
else
    echo \"❌ kubelet is not installed\"
fi
" --one-line 2>/dev/null || print_message $RED "kubelet check failed"

echo

# Check PATH and binary locations
print_message $BLUE "=== Binary Locations and PATH Check ==="
$ANSIBLE_CMD -m shell -a "
echo \"PATH=\$PATH\"
echo \"---\"
for binary in kubeadm kubectl kubelet; do
    echo -n \"\$binary: \"
    if [ -f \"/usr/bin/\$binary\" ]; then
        echo \"/usr/bin/\$binary (package installation)\"
    elif [ -f \"/usr/local/bin/\$binary\" ]; then
        echo \"/usr/local/bin/\$binary (manual installation)\"
    else
        echo \"not found\"
    fi
done
" --one-line 2>/dev/null || print_message $RED "PATH check failed"

echo

print_message $GREEN "========================================="
print_message $GREEN "Verification completed!"
print_message $GREEN "========================================="

# Summary and recommendations
print_message $YELLOW "💡 Troubleshooting methods:"
print_message $YELLOW "1. If kubeadm/kubectl is not installed:"
print_message $YELLOW "   ./scripts/setup-cluster.sh cluster-only --tags k8s-packages"
print_message $YELLOW ""
print_message $YELLOW "2. If PATH issue:"
print_message $YELLOW "   export PATH=\"/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:\$PATH\""
print_message $YELLOW ""
print_message $YELLOW "3. Re-run verification only:"
print_message $YELLOW "   ansible all -i $INVENTORY -m include_role -a name=kubernetes-common --tags verification" 