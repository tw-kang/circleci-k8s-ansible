#!/bin/bash

# Prepare Worker Node Script
# This script manually prepares a worker node for Kubernetes cluster joining
# Updated for Kubernetes v1.28.15 with ARM64 Rocky Linux 8 support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values - Updated for current project versions
TARGET_NODE=""
SSH_KEY=""
KUBERNETES_VERSION="1.28.15"
CONTAINERD_VERSION="1.7.27"
RUNC_VERSION="1.1.12"
CNI_VERSION="1.4.0"
ARCHITECTURE=""
SKIP_SSH_SETUP=false

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

# Function to detect architecture
detect_architecture() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY" ]]; then
        ssh_key_option="-i $SSH_KEY"
    fi
    
    print_message $BLUE "Detecting system architecture..."
    ARCHITECTURE=$(ssh $ssh_key_option root@$node_ip "uname -m" 2>/dev/null)
    
    case "$ARCHITECTURE" in
        "x86_64"|"amd64")
            ARCHITECTURE="amd64"
            print_message $GREEN "Detected architecture: x86_64 (amd64)"
            ;;
        "aarch64"|"arm64")
            ARCHITECTURE="arm64"
            print_message $GREEN "Detected architecture: ARM64 (aarch64)"
            ;;
        *)
            print_message $RED "Unsupported architecture: $ARCHITECTURE"
            print_message $RED "Supported architectures: x86_64, aarch64"
            exit 1
            ;;
    esac
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Prepare Worker Node Script for Kubernetes v${KUBERNETES_VERSION}
Supports: Rocky Linux 8, ARM64/x86_64 architectures
🔑 Automatically generates SSH keys (no manual ssh-keygen required!)

OPTIONS:
    --target-node IP           Target node IP address (required)
    --ssh-key PATH             SSH private key path (optional)
    --kubernetes-version VER   Kubernetes version (default: $KUBERNETES_VERSION)
    --containerd-version VER   containerd version (default: $CONTAINERD_VERSION)
    --skip-ssh-setup           Skip SSH key auto-generation
    -h, --help                 Show this help message

EXAMPLES:
    # Prepare worker node with auto-detected architecture
    $0 --target-node 192.168.1.20

    # Prepare with custom SSH key
    $0 --target-node 192.168.1.20 --ssh-key ~/.ssh/k8s-key

    # Use specific versions
    $0 --target-node 192.168.1.20 --kubernetes-version 1.28.15

DESCRIPTION:
    This script prepares a worker node for joining a Kubernetes cluster by:
    1. Detecting system architecture (ARM64/x86_64)
    2. Installing and configuring containerd (architecture-specific)
    3. Installing Kubernetes components (kubelet, kubeadm, kubectl)
    4. Setting up system configuration for Kubernetes
    5. Starting required services

ARCHITECTURE SUPPORT:
    - ARM64: Uses GitHub releases for containerd binary installation
    - x86_64: Uses package manager for containerd installation
    - Auto-detection and appropriate configuration

REQUIREMENTS:
    - Rocky Linux 8 or compatible system
    - SSH root access to target node
    - Internet connectivity on target node

EOF
}

# Function to test SSH connectivity
test_ssh_connectivity() {
    local node_ip=$1
    local ssh_key_option=""
    
    if [[ -n "$SSH_KEY" ]]; then
        ssh_key_option="-i $SSH_KEY"
    fi
    
    print_message $BLUE "Testing SSH connectivity to $node_ip..."
    
    if timeout 10 ssh $ssh_key_option -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "echo 'SSH connection successful'" >/dev/null 2>&1; then
        print_message $GREEN "✓ SSH connection successful"
        return 0
    else
        print_message $RED "✗ SSH connection failed"
        print_message $YELLOW "Troubleshooting:"
        print_message $YELLOW "1. Verify SSH service: systemctl status sshd"
        print_message $YELLOW "2. Check SSH key setup: ssh-copy-id root@$node_ip"
        print_message $YELLOW "3. Test manual connection: ssh root@$node_ip"
        return 1
    fi
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
        # Install containerd for ARM64 from GitHub releases (matches project setup)
        print_message $BLUE "Installing containerd from GitHub releases (ARM64)..."
        ssh $ssh_key_option root@$node_ip "
            cd /tmp
            
            # Download and extract containerd
            echo 'Downloading containerd ${CONTAINERD_VERSION} for ARM64...'
            curl -L https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz -o containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz
            tar -xzf containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz -C /usr/local
            
            # Download and install runc
            echo 'Downloading runc ${RUNC_VERSION} for ARM64...'
            curl -L https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.arm64 -o /usr/local/sbin/runc
            chmod +x /usr/local/sbin/runc
            
            # Download and install CNI plugins
            echo 'Downloading CNI plugins ${CNI_VERSION} for ARM64...'
            mkdir -p /opt/cni/bin
            curl -L https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-arm64-v${CNI_VERSION}.tgz -o cni-plugins-linux-arm64-v${CNI_VERSION}.tgz
            tar -xzf cni-plugins-linux-arm64-v${CNI_VERSION}.tgz -C /opt/cni/bin
            
            # Clean up
            rm -f containerd-*.tar.gz cni-plugins-*.tgz
            
            echo 'containerd binaries installed successfully'
        "
    else
        # Install containerd for x86_64 from Docker repository
        print_message $BLUE "Installing containerd from Docker repository (x86_64)..."
        ssh $ssh_key_option root@$node_ip "
            # Add Docker repository for containerd
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y containerd.io
        "
    fi
    
    # Create containerd systemd service (consistent with project setup)
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
        
        # Create containerd configuration directory
        mkdir -p /etc/containerd
        
        # Generate default configuration
        if [[ '$ARCHITECTURE' == 'arm64' ]]; then
            /usr/local/bin/containerd config default > /etc/containerd/config.toml
        else
            containerd config default > /etc/containerd/config.toml
        fi
        
        # Configure systemd cgroup driver (matches project setup)
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        
        # Reload systemd and start containerd
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
    
    print_message $BLUE "Installing Kubernetes components v${KUBERNETES_VERSION}..."
    
    ssh $ssh_key_option root@$node_ip "
        # Add Kubernetes repository (new official repo)
        cat > /etc/yum.repos.d/kubernetes.repo << 'EOF'
[kubernetes]
name=Kubernetes Repository
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
        
        # Install Kubernetes components
        echo 'Installing kubelet, kubeadm, kubectl v${KUBERNETES_VERSION}...'
        dnf install -y kubelet-${KUBERNETES_VERSION} kubeadm-${KUBERNETES_VERSION} kubectl-${KUBERNETES_VERSION} --disableexcludes=kubernetes
        
        # Install dnf versionlock plugin
        dnf install -y 'dnf-command(versionlock)'
        
        # Lock Kubernetes packages to prevent unwanted updates
        dnf versionlock kubelet kubeadm kubectl
        
        # Enable kubelet (will start after joining cluster)
        systemctl enable kubelet
        
        echo 'Kubernetes components installed and configured successfully'
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
    
    print_message $BLUE "Configuring system settings for Kubernetes..."
    
    ssh $ssh_key_option root@$node_ip "
        # Configure SELinux (if present)
        if command -v getenforce &> /dev/null; then
            echo 'Configuring SELinux...'
            setenforce 0 || true
            sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
        else
            echo 'SELinux not present, skipping...'
        fi
        
        # Disable swap permanently
        echo 'Disabling swap...'
        swapoff -a
        sed -i '/ swap / s/^\(.*\)$/\#\1/g' /etc/fstab
        
        # Load required kernel modules
        echo 'Loading kernel modules...'
        modprobe overlay
        modprobe br_netfilter
        
        # Set up modules to load at boot
        mkdir -p /etc/modules-load.d
        cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
        
        # Set up sysctl parameters for Kubernetes
        echo 'Configuring sysctl parameters...'
        mkdir -p /etc/sysctl.d
        cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
        
        # Apply sysctl settings
        sysctl --system >/dev/null 2>&1
        
        # Configure firewall (if enabled)
        if systemctl is-active --quiet firewalld; then
            echo 'Configuring firewall for Kubernetes...'
            
            # Worker node ports
            firewall-cmd --permanent --add-port=10250/tcp  # kubelet API
            firewall-cmd --permanent --add-port=30000-32767/tcp  # NodePort Services
            
            # Flannel (if using Flannel CNI)
            firewall-cmd --permanent --add-port=8285/udp   # Flannel UDP
            firewall-cmd --permanent --add-port=8472/udp   # Flannel VXLAN
            
            firewall-cmd --reload
            echo 'Firewall configured for Kubernetes'
        else
            echo 'Firewall not running, skipping firewall configuration'
        fi
        
        # Update package cache
        echo 'Updating package cache...'
        dnf makecache
        
        echo 'System configuration completed successfully'
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
        echo 'Checking containerd...'
        systemctl is-active containerd
        
        echo 'Checking Kubernetes packages...'
        rpm -qa | grep -E '^(kubelet|kubeadm|kubectl)' | sort
        
        echo 'Checking kernel modules...'
        lsmod | grep -E '(overlay|br_netfilter)'
        
        echo 'Checking sysctl parameters...'
        sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
        
        echo 'Checking if swap is disabled...'
        [ \$(swapon --show | wc -l) -eq 0 ] && echo 'Swap disabled' || echo 'Warning: Swap still enabled'
        
        echo 'Installation verification completed'
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
        --skip-ssh-setup)
            SKIP_SSH_SETUP=true
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
print_message $BLUE "Prepare Worker Node for Kubernetes"
print_message $BLUE "Kubernetes: v${KUBERNETES_VERSION}"
print_message $BLUE "containerd: v${CONTAINERD_VERSION}"
print_message $BLUE "🔑 SSH 키 자동 생성 포함"
print_message $BLUE "Target: $TARGET_NODE"
print_message $BLUE "========================================="

# Setup SSH keys automatically (unless skipped)
if [[ "$SKIP_SSH_SETUP" != true ]]; then
    if ! setup_ssh_keys; then
        print_message $RED "SSH 키 설정에 실패했습니다. --skip-ssh-setup 옵션을 사용하여 건너뛸 수 있습니다."
        exit 1
    fi
    echo
fi

# Test SSH connectivity
if ! test_ssh_connectivity "$TARGET_NODE"; then
    exit 1
fi

# Detect architecture
detect_architecture "$TARGET_NODE"

# Confirm before proceeding
echo
read -p "Proceed with worker node preparation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_message $YELLOW "Operation cancelled"
    exit 0
fi

# Execute preparation steps
print_message $BLUE "Starting worker node preparation..."

configure_system "$TARGET_NODE"
install_containerd "$TARGET_NODE"
install_kubernetes "$TARGET_NODE"
verify_installation "$TARGET_NODE"

print_message $GREEN "========================================="
print_message $GREEN "Worker node preparation completed!"
print_message $GREEN "========================================="

print_message $GREEN "Next steps:"
print_message $GREEN "1. Get the join command from master node:"
print_message $GREEN "   kubeadm token create --print-join-command"
print_message $GREEN "2. Run the join command on this worker node"
print_message $GREEN "3. Verify the node joined successfully:"
print_message $GREEN "   kubectl get nodes"
echo
print_message $GREEN "🔑 SSH 키 파일 위치:"
print_message $GREEN "  개인 키: ~/.ssh/id_ed25519"
print_message $GREEN "  공개 키: ~/.ssh/id_ed25519.pub"

print_message $BLUE "Node is ready to join Kubernetes cluster!" 