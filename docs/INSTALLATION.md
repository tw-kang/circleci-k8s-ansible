# Installation Guide

Quick installation guide for Kubernetes clusters with CircleCI runners.

## Prerequisites

**Control Machine (Ansible Execution Machine):**
- Python 3.10+ and Ansible 9.13+ (installed via requirements.txt)
- Git for repository cloning
- SSH access to target nodes

**Target Nodes (Kubernetes Cluster Nodes):**
- Rocky Linux 8/9, CentOS 8/9, RHEL 8/9, AlmaLinux 8/9, Ubuntu 20.04/22.04
- 2GB RAM minimum for control plane, 1GB for workers
- SSH access with root or sudo privileges
- Python 3.10+ installed globally (via Miniconda recommended)
- Firewall disabled on all nodes

## Installation Overview

The installation process is divided as follows:

1. **Control Machine Setup** - Configure Ansible environment
2. **Target Nodes Preparation** - Pre-configure each cluster node
3. **Cluster Deployment from Control Machine** - Deploy cluster via Ansible

---

## Part 1: Control Machine Setup

**The following tasks are performed on the Control Machine that will execute Ansible**

### 1. Repository Clone and Environment Setup

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

### 2. SSH Key Generation and Distribution

```bash
# Generate SSH key pair if not exists
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# Copy public key to each target node
ssh-copy-id root@192.168.1.49  # master node
ssh-copy-id root@192.168.2.8   # worker node 1
ssh-copy-id root@192.168.1.48  # worker node 2

# Or copy to specific user with sudo privileges
ssh-copy-id username@192.168.1.49

# Verify SSH access without password
ssh root@192.168.1.49 "echo 'SSH connection successful'"
```

### 3. Inventory Configuration

```bash
# Edit inventory with your node IPs
vim inventory/production/hosts.ini
```

Example inventory (based on actual project structure):
```ini
[kube_control_plane]
k8s-master-01 ansible_host=192.168.1.49 ansible_user=root node_role=master

[etcd:children]
kube_control_plane

[kube_node]
k8s-worker-01 ansible_host=192.168.2.8 ansible_user=root node_role=worker node_labels='{"node-role.kubernetes.io/worker":""}'
k8s-worker-02 ansible_host=192.168.1.48 ansible_user=root node_role=worker node_labels='{"node-role.kubernetes.io/worker":""}'

[k8s_cluster:children]
kube_control_plane
kube_node

[circleci:children]
kube_control_plane
```

---

## Part 2: Target Nodes Preparation

**The following tasks are performed individually on each Target Node (cluster node)**

### 1. Python 3.10 Installation (Required on all nodes)

**CRITICAL:** Python 3.10+ must be installed on ALL target nodes before running Ansible playbooks.

**Execute the following commands on each Target Node:**

```bash
# 1. Create Miniconda installation directory
sudo mkdir -p /opt/miniconda3
sudo chown root:root /opt/miniconda3
sudo chmod 755 /opt/miniconda3

# 2. Download and install Miniconda
cd /tmp
sudo dnf install -y wget
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
sudo bash Miniconda3-latest-Linux-x86_64.sh -b -p /opt/miniconda3 -u

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
```

**Important: Repeat this task on all Target Nodes (master + worker nodes)**

### 2. Firewall Disable (Required on all nodes)

**Disable firewall on each Target Node:**

**Rocky Linux/CentOS/RHEL/AlmaLinux:**
```bash
sudo systemctl stop firewalld
sudo systemctl disable firewalld
sudo systemctl status firewalld  # Verify it's disabled
```

### 3. DNS Configuration (Required on all nodes)

**CRITICAL:** DNS must be configured manually on all nodes due to `resolvconf_mode: none` setting.

**Configure DNS on each Target Node:**

```bash
# Find connection name
nmcli connection show

# Configure DNS (replace "Wired connection 1" with actual name)
nmcli connection modify "Wired connection 1" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes

# Apply configuration
nmcli connection up "Wired connection 1"

# Verify DNS
cat /etc/resolv.conf
nslookup google.com
```

**Important: Perform this task on all Target Nodes**

---

## Part 3: Cluster Deployment from Control Machine

**The following tasks are performed again on the Control Machine**

### 1. Target Nodes Connection Verification

```bash
# FIRST: Verify Python 3.10+ is installed on ALL nodes
ansible all -i inventory/production/hosts.ini -m setup -a "filter=ansible_python_version"

# Test connectivity
ansible all -i inventory/production/hosts.ini -m ping
```

### 2. Monitoring Configuration (Optional)

If you want monitoring, edit `inventory/production/group_vars/k8s_cluster/addons.yml`:

```yaml
# Enable automatic monitoring deployment
kube_prometheus_stack_enabled: true
kube_prometheus_stack_namespace: monitoring
kube_prometheus_stack_chart_version: "61.3.2"

# Basic configuration with NodePort access
kube_prometheus_stack_values:
  grafana:
    adminPassword: "{{ vault_grafana_admin_password }}"
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

### 3. Cluster Deployment

```bash
# Deploy Kubernetes only
./scripts/setup-cluster.sh cluster-only

# Deploy with CircleCI (optional)
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password
```

### 4. Installation Verification

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# For monitoring (if enabled)
kubectl get pods -n monitoring

# Access monitoring services via NodePort:
# Grafana: http://NODE_IP:32000 (admin/admin123!@#)
# Prometheus: http://NODE_IP:32001
# AlertManager: http://NODE_IP:32002
```

---

## Task Location Summary

| Task | Execution Location | Description |
|------|-------------------|-------------|
| Repository clone and environment setup | **Control Machine** | Configure Ansible environment |
| SSH key generation and distribution | **Control Machine** | Copy SSH keys to target nodes |
| Inventory configuration | **Control Machine** | Configure cluster node information |
| Python installation | **Target Nodes** | Perform individually on each node |
| Firewall disable | **Target Nodes** | Perform individually on each node |
| DNS configuration | **Target Nodes** | Perform individually on each node |
| Connection verification | **Control Machine** | Check node status with Ansible |
| Cluster deployment | **Control Machine** | Execute Ansible playbooks |
| Installation verification | **Control Machine** | Check cluster status with kubectl |

## Configuration File Locations

After installation, configuration files are located at:

- **Global settings**: `inventory/production/group_vars/all/kubespray.yml`
- **Project variables**: `inventory/production/group_vars/all/vars.yml`
- **Cluster settings**: `inventory/production/group_vars/k8s_cluster/k8s-cluster.yml`
- **Addon settings**: `inventory/production/group_vars/k8s_cluster/addons.yml`
- **CircleCI config**: `inventory/production/group_vars/circleci/runner.yml`

## Troubleshooting

### Common Issues

1. **Python not found error**: Ensure Python 3.10+ is installed on all target nodes
2. **DNS resolution fails**: Configure DNS manually on each target node
3. **SSH connection refused**: Verify SSH keys and firewall settings
4. **Kubespray submodule not found**: Run `git submodule update --init --recursive` on control machine

### Verification Commands (Execute on Control Machine)

```bash
# Check Python version on all nodes
ansible all -i inventory/production/hosts.ini -m shell -a "python --version"

# Test DNS resolution on all nodes  
ansible all -i inventory/production/hosts.ini -m shell -a "nslookup google.com"

# Check kubespray submodule
ls -la 3rdparty/kubespray/

# Verify inventory syntax
ansible-inventory -i inventory/production/hosts.ini --list
``` 