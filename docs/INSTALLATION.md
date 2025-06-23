# Installation Guide

Quick installation guide for Kubernetes clusters with CircleCI runners.

## Prerequisites

**Control Machine:**
- Python 3.10+ and Ansible 9.13+ (installed via requirements.txt)
- Git for repository cloning
- SSH access to target nodes

**Target Nodes:**
- Rocky Linux 8/9, CentOS 8/9, RHEL 8/9, AlmaLinux 8/9, Ubuntu 20.04/22.04
- 2GB RAM minimum for control plane, 1GB for workers
- SSH access with root or sudo privileges

## Installation Steps

### 1. Clone Repository and Setup

```bash
# Clone repository
git clone https://github.com/your-org/circleci-k8s-ansible.git
cd circleci-k8s-ansible

# Initialize kubespray submodule
git submodule update --init --recursive

# Install dependencies
python -m pip install -U -r requirements.txt

# Make scripts executable
chmod +x scripts/*.sh
```

### 2. Configure DNS (REQUIRED)

**CRITICAL:** DNS must be configured manually on all nodes before deployment due to `resolvconf_mode: none` setting.

```bash
# On each target node, configure DNS
nmcli connection show  # Find connection name

# Configure DNS (replace "Wired connection 2" with actual name)
nmcli connection modify "Wired connection 2" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes

# Apply configuration
nmcli connection up "Wired connection 2"

# Verify DNS
cat /etc/resolv.conf
nslookup google.com
```

### 3. Configure Inventory

```bash
# Copy sample inventory
cp 3rdparty/kubespray/inventory/inventory.ini inventory/production/hosts.ini

# Edit inventory with your node IPs
vim inventory/production/hosts.ini
```

Example inventory:
```ini
[all]
master-01 ansible_host=192.168.1.10 ansible_user=root
worker-01 ansible_host=192.168.1.20 ansible_user=root

[kube_control_plane]
master-01

[etcd]
master-01

[kube_node]
master-01
worker-01

[k8s_cluster:children]
kube_control_plane
kube_node
```

### 4. Deploy Cluster

```bash
# Test connectivity
ansible all -i inventory/production/hosts.ini -m ping

# Deploy Kubernetes only
./scripts/setup-cluster.sh cluster-only

# Deploy with CircleCI (optional)
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password
```

### 5. CircleCI Configuration (Optional)

Create CircleCI runner configuration:

```bash
# Create CircleCI configuration
mkdir -p inventory/production/group_vars/circleci
cat > inventory/production/group_vars/circleci/runner.yml << EOF
runner:
  namespace: "circleci"
  resource_class: "your-org/medium"
  token: "{{ vault_circleci_token }}"
  image: "cimg/base:stable"
  replicas: 2
  
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"
EOF

# Store CircleCI token in vault
ansible-vault create inventory/production/group_vars/all/vault.yml
# Add: vault_circleci_token: "YOUR_CIRCLECI_RUNNER_TOKEN"
```

### 6. Verify Installation

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check CircleCI runners (if deployed)
kubectl get pods -n circleci
```

## Troubleshooting

**DNS Issues:**
- Verify `/etc/resolv.conf` contains correct nameservers
- Test DNS resolution: `nslookup google.com`
- Check NetworkManager: `nmcli device show | grep DNS`

**SSH Issues:**
- Verify SSH key access: `ssh root@node-ip`
- Check inventory file syntax
- Test ansible connectivity: `ansible all -i inventory/production/hosts.ini -m ping`

For detailed configuration options, see [Configuration Guide](CONFIGURATION.md). 