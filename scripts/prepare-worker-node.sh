#!/bin/bash

# Prepare Worker Node Script
# This script manually prepares a worker node for Kubernetes cluster joining
# Based on real-world testing experience with ARM64 Rocky Linux 8

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
TARGET_NODE=""
SSH_KEY=""
KUBERNETES_VERSION="1.28.15"
CONTAINERD_VERSION="1.7.27"
RUNC_VERSION="1.1.12"
CNI_VERSION="1.4.0"
ARCHITECTURE=""

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to detect architecture
detect_architecture() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY" ]]; then
        ssh_key_option="-i $SSH_KEY"
    fi
    
    ARCHITECTURE=$(ssh $ssh_key_option root@$node_ip "uname -m" 2>/dev/null)
    
    case "$ARCHITECTURE" in
        "x86_64"|"amd64")
            ARCHITECTURE="amd64"
            ;;
        "aarch64"|"arm64")
            ARCHITECTURE="arm64"
            ;;
        *)
            print_message $RED "Unsupported architecture: $ARCHITECTURE"
            exit 1
            ;;
    esac
    
    print_message $GREEN "Detected architecture: $ARCHITECTURE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --target-node IP           Target node IP address (required)
    --ssh-key PATH             SSH private key path (optional)
    --kubernetes-version VER   Kubernetes version (default: $KUBERNETES_VERSION)
    --containerd-version VER   containerd version (default: $CONTAINERD_VERSION)
    -h, --help                 Show this help message

EXAMPLES:
    # Prepare worker node
    $0 --target-node 192.168.1.20

    # Prepare with custom SSH key
    $0 --target-node 192.168.1.20 --ssh-key ~/.ssh/k8s-key

DESCRIPTION:
    This script prepares a worker node for joining a Kubernetes cluster by:
    1. Installing and configuring containerd
    2. Installing Kubernetes components (kubelet, kubeadm, kubectl)
    3. Setting up system configuration
    4. Starting required services

EOF
}

# Function to install containerd
install_containerd() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY" ]]; then
        ssh_key_option="-i $SSH_KEY"
    fi
    
    print_message $BLUE "Installing containerd $CONTAINERD_VERSION for $ARCHITECTURE..."
    
    if [[ "$ARCHITECTURE" == "arm64" ]]; then
        # Install containerd for ARM64 from GitHub releases
        ssh $ssh_key_option root@$node_ip "
            cd /tmp
            
            # Download and extract containerd
            echo 'Downloading containerd...'
            wget -q https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz
            tar -xzf containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz -C /usr/local
            
            # Download and install runc
            echo 'Downloading runc...'
            wget -q https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.arm64 -O /usr/local/sbin/runc
            chmod +x /usr/local/sbin/runc
            
            # Download and install CNI plugins
            echo 'Downloading CNI plugins...'
            mkdir -p /opt/cni/bin
            wget -q https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-arm64-v${CNI_VERSION}.tgz
            tar -xzf cni-plugins-linux-arm64-v${CNI_VERSION}.tgz -C /opt/cni/bin
            
            echo 'containerd binaries installed successfully'
        "
    else
        # Install containerd for x86_64 from package manager
        ssh $ssh_key_option root@$node_ip "
            # Add Docker repository for containerd
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y containerd.io-${CONTAINERD_VERSION}
        "
    fi
    
    # Create containerd systemd service
    print_message $BLUE "Setting up containerd service..."
    ssh $ssh_key_option root@$node_ip "
        # Create containerd service file
        cat > /etc/systemd/system/containerd.service << 'EOF'
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
        
        # Create containerd configuration
        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
        
        # Start and enable containerd
        systemctl daemon-reload
        systemctl enable containerd
        systemctl start containerd
        
        echo 'containerd service configured and started'
    "
    
    print_message $GREEN "✓ containerd installation completed"
}

# Function to install Kubernetes components
install_kubernetes() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY" ]]; then
        ssh_key_option="-i $SSH_KEY"
    fi
    
    print_message $BLUE "Installing Kubernetes components..."
    
    ssh $ssh_key_option root@$node_ip "
        # Add Kubernetes repository
        cat > /etc/yum.repos.d/kubernetes.repo << 'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
        
        # Install Kubernetes components
        echo 'Installing kubelet, kubeadm, kubectl...'
        yum install -y kubelet-${KUBERNETES_VERSION} kubeadm-${KUBERNETES_VERSION} kubectl-${KUBERNETES_VERSION} --disableexcludes=kubernetes
        
        # Enable kubelet
        systemctl enable kubelet
        
        echo 'Kubernetes components installed successfully'
    "
    
    print_message $GREEN "✓ Kubernetes components installation completed"
}

# Function to configure system
configure_system() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY" ]]; then
        ssh_key_option="-i $SSH_KEY"
    fi
    
    print_message $BLUE "Configuring system settings..."
    
    ssh $ssh_key_option root@$node_ip "
        # Ensure SELinux config exists and is disabled
        mkdir -p /etc/selinux
        if [[ ! -f /etc/selinux/config ]]; then
            echo 'SELINUX=disabled' > /etc/selinux/config
        else
            sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        fi
        
        # Disable swap
        swapoff -a
        sed -i '/ swap / s/^\(.*\)$/\#\1/g' /etc/fstab
        
        # Load kernel modules
        modprobe overlay
        modprobe br_netfilter
        
        # Set up modules to load at boot
        mkdir -p /etc/modules-load.d
        cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
        
        # Set up sysctl parameters
        mkdir -p /etc/sysctl.d
        cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
        sysctl --system
        
        # Disable firewall (for lab environment)
        systemctl stop firewalld 2>/dev/null || true
        systemctl disable firewalld 2>/dev/null || true
        
        echo 'System configuration completed'
    "
    
    print_message $GREEN "✓ System configuration completed"
}

# Function to verify installation
verify_installation() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY" ]]; then
        ssh_key_option="-i $SSH_KEY"
    fi
    
    print_message $BLUE "Verifying installation..."
    
    ssh $ssh_key_option root@$node_ip "
        # Check containerd
        echo 'Checking containerd status:'
        systemctl status containerd --no-pager -l
        
        # Check kubelet
        echo 'Checking kubelet status:'
        systemctl status kubelet --no-pager -l || echo 'kubelet not started yet (normal)'
        
        # Check installed versions
        echo 'Installed versions:'
        containerd --version
        kubeadm version
        kubelet --version
        kubectl version --client
        
        echo 'Node preparation verification completed'
    "
    
    print_message $GREEN "✓ Installation verification completed"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --target-node)
            TARGET_NODE="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        --kubernetes-version)
            KUBERNETES_VERSION="$2"
            shift 2
            ;;
        --containerd-version)
            CONTAINERD_VERSION="$2"
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

# Validate required parameters
if [[ -z "$TARGET_NODE" ]]; then
    print_message $RED "Error: --target-node is required"
    show_usage
    exit 1
fi

# Validate SSH key path if provided
if [[ -n "$SSH_KEY" && ! -f "$SSH_KEY" ]]; then
    print_message $RED "Error: SSH key file '$SSH_KEY' not found"
    exit 1
fi

print_message $BLUE "========================================="
print_message $BLUE "Preparing Worker Node for Kubernetes"
print_message $BLUE "========================================="

print_message $GREEN "Configuration:"
print_message $GREEN "  Target Node: $TARGET_NODE"
print_message $GREEN "  Kubernetes Version: $KUBERNETES_VERSION"
print_message $GREEN "  containerd Version: $CONTAINERD_VERSION"
[[ -n "$SSH_KEY" ]] && print_message $GREEN "  SSH Key: $SSH_KEY"
echo

# Test SSH connection
print_message $BLUE "Testing SSH connection..."
ssh_key_option=""
if [[ -n "$SSH_KEY" ]]; then
    ssh_key_option="-i $SSH_KEY"
fi

if ! timeout 10 ssh $ssh_key_option -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$TARGET_NODE "echo 'SSH connection successful'" >/dev/null 2>&1; then
    print_message $RED "SSH connection failed"
    print_message $YELLOW "Please ensure:"
    print_message $YELLOW "1. SSH service is running on target node"
    print_message $YELLOW "2. SSH key is properly configured"
    print_message $YELLOW "3. Root access is available"
    exit 1
fi

print_message $GREEN "✓ SSH connection successful"

# Detect architecture
detect_architecture "$TARGET_NODE"

# Ask for confirmation
read -p "Do you want to continue with node preparation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_message $YELLOW "Operation cancelled"
    exit 0
fi

# Execute preparation steps
configure_system "$TARGET_NODE"
install_containerd "$TARGET_NODE"
install_kubernetes "$TARGET_NODE"
verify_installation "$TARGET_NODE"

print_message $GREEN "========================================="
print_message $GREEN "Worker Node Preparation Completed!"
print_message $GREEN "========================================="

print_message $GREEN "Next steps:"
print_message $GREEN "1. Get join command from master: sudo kubeadm token create --print-join-command"
print_message $GREEN "2. Join the cluster: kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>"
print_message $GREEN "3. Verify node joined: kubectl get nodes"

print_message $BLUE "The worker node is now ready to join the Kubernetes cluster!" 