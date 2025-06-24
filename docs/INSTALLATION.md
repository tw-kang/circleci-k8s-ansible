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
- Python 3.10+ installed globally (via Miniconda recommended)
- Firewall disabled on all nodes
- Ansible control machine's public key copied to all target nodes

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

### 2. Prepare Target Nodes

#### Install Python 3.10 (via Miniconda) - REQUIRED

**CRITICAL:** Python 3.10+ must be installed on ALL target nodes before running Ansible playbooks. Ansible will fail without Python available on each node.

Install Python 3.10 globally on all target nodes using Miniconda:

```bash
# On each target node

# 1. Create Miniconda installation directory
sudo mkdir -p /opt/miniconda3
sudo chown root:root /opt/miniconda3
sudo chmod 755 /opt/miniconda3

# 2. Download and install Miniconda
cd /tmp
sudo dnf install -y wget
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
sudo bash Miniconda3-latest-Linux-x86_64.sh -b -p /opt/miniconda3

# 3. Create system-wide conda initialization script
sudo tee /etc/profile.d/miniconda.sh <<'EOF'
# >>> conda initialize >>>
__conda_setup="$('/opt/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    export PATH="/opt/miniconda3/bin:$PATH"
fi
unset __conda_setup
# <<< conda initialize <<<
EOF

sudo chmod +x /etc/profile.d/miniconda.sh

# 4. Load conda environment and upgrade to Python 3.10
source /etc/profile.d/miniconda.sh
conda install -n base python=3.10 -y

# 5. Verify installation
python --version       # Should show Python 3.10.x
which python           # Should show /opt/miniconda3/bin/python

# IMPORTANT: Repeat this installation on EVERY target node
# All nodes (control plane and worker nodes) require Python 3.10+
```

#### Disable Firewall

Disable firewall on all target nodes to prevent network connectivity issues:

**Rocky Linux/CentOS/RHEL/AlmaLinux:**
```bash
# On each target node
sudo systemctl stop firewalld
sudo systemctl disable firewalld
sudo systemctl status firewalld  # Verify it's disabled
```

**Ubuntu:**
```bash
# On each target node
sudo ufw disable
sudo ufw status  # Verify it's inactive
```

#### Copy SSH Public Key

Copy your Ansible control machine's SSH public key to all target nodes:

```bash
# Generate SSH key pair if not exists
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# Copy public key to each target node
ssh-copy-id root@192.168.1.10  # master node
ssh-copy-id root@192.168.1.20  # worker node

# Or copy to specific user with sudo privileges
ssh-copy-id username@192.168.1.10

# Verify SSH access without password
ssh root@192.168.1.10 "echo 'SSH connection successful'"
```

### 3. Configure DNS (REQUIRED)

**CRITICAL:** DNS must be configured manually on all nodes before deployment due to `resolvconf_mode: none` setting.

```bash
# On each target node, configure DNS
nmcli connection show  # Find connection name

# Configure DNS (replace "Wired connection 2" with actual name)
nmcli connection modify "Wired connection 1" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes

# Apply configuration
nmcli connection up "Wired connection 1"

# Verify DNS
cat /etc/resolv.conf
nslookup google.com
```

### 4. Configure Inventory

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

### 5. Deploy Cluster

```bash
# FIRST: Verify Python 3.10+ is installed on ALL nodes
ansible all -i inventory/production/hosts.ini -m setup -a "filter=ansible_python_version"

# Test connectivity
ansible all -i inventory/production/hosts.ini -m ping

# Deploy Kubernetes only
./scripts/setup-cluster.sh cluster-only

# Deploy with CircleCI (optional)
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password
```

### 6. Configure Monitoring (Optional)

The monitoring stack (Prometheus, Grafana, AlertManager) can be deployed automatically or manually.

#### Automatic Monitoring Deployment (Recommended)

Enable automatic monitoring by configuring `inventory/production/group_vars/k8s_cluster/addons.yml`:

```yaml
# Enable automatic monitoring deployment
kube_prometheus_stack_enabled: true
kube_prometheus_stack_namespace: monitoring
kube_prometheus_stack_chart_version: "61.3.2"

# Configure NodePort access with custom ports
kube_prometheus_stack_values:
  grafana:
    adminPassword: "admin123!@#"
    service:
      type: NodePort
      nodePort: 32000
  
  prometheus:
    service:
      type: NodePort
      nodePort: 32001
  
  alertmanager:
    service:
      type: NodePort
      nodePort: 32002
```

**Deploy with Automatic Monitoring:**
```bash
# Deploy cluster with automatic monitoring (if enabled in addons.yml)
./scripts/setup-cluster.sh cluster-only

# Or with CircleCI + automatic monitoring
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password
```

#### Manual Monitoring Deployment

```bash
# Deploy monitoring stack separately
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# Verify monitoring deployment
kubectl get pods -n monitoring
kubectl get services -n monitoring | grep NodePort
```

**Access Monitoring Services:**

After deployment, monitoring services are accessible via NodePort on any cluster node (ports configured in `addons.yml`):

- **Grafana**: `http://NODE_IP:GRAFANA_PORT` (default: 32000)
  - Default username: `admin`
  - Default password: `admin123!@#` (configurable in `addons.yml`)
- **Prometheus**: `http://NODE_IP:PROMETHEUS_PORT` (default: 32001)
- **AlertManager**: `http://NODE_IP:ALERTMANAGER_PORT` (default: 32002)

**Port-Forward Access:**
```bash
# Grafana
kubectl port-forward -n monitoring service/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090

# AlertManager
kubectl port-forward -n monitoring service/kube-prometheus-stack-alertmanager 9093:9093
```

### 7. CircleCI Configuration (Optional)

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

### 8. Verify Installation

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check CircleCI runners (if deployed)
kubectl get pods -n circleci

# Check monitoring stack (if deployed)
kubectl get pods -n monitoring
kubectl get services -n monitoring
```

## Troubleshooting

**Python Issues:**
- **Error: "No such file or directory" for Python**: Install Python 3.10+ on ALL target nodes
- **Module execution failed**: Verify Python path with `which python` on each node
- **Check Python version**: `ansible all -i inventory/production/hosts.ini -m setup -a "filter=ansible_python_version"`
- **Force Python interpreter**: Add `ansible_python_interpreter=/opt/miniconda3/bin/python` to inventory

**DNS Issues:**
- Verify `/etc/resolv.conf` contains correct nameservers
- Test DNS resolution: `nslookup google.com`
- Check NetworkManager: `nmcli device show | grep DNS`

**SSH Issues:**
- Verify SSH key access: `ssh root@node-ip`
- Check inventory file syntax
- Test ansible connectivity: `ansible all -i inventory/production/hosts.ini -m ping`

For detailed configuration options, see [Configuration Guide](CONFIGURATION.md). 