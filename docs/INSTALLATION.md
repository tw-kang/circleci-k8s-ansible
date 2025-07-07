# Installation Guide

Comprehensive installation guide for Kubernetes clusters with integrated monitoring stack and optional CircleCI runners.

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

The installation process follows this structure:

1. **Control Machine Setup** - Configure Ansible environment
2. **Target Nodes Preparation** - Pre-configure each cluster node
3. **Cluster Deployment** - Deploy cluster with integrated monitoring using the setup script

---

## Part 1: Control Machine Setup

**Execute on the Control Machine that will run Ansible**

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

# Verify SSH access without password
ssh root@192.168.1.49 "echo 'SSH connection successful'"
```

### 3. Inventory Configuration

```bash
# Copy sample inventory to production environment
cp inventory/production/hosts.ini.sample inventory/production/hosts.ini

# Edit inventory with your node IPs
vim inventory/production/hosts.ini
```

Example inventory configuration:
```ini
[kube_control_plane]
k8s-master-01 ansible_host=192.168.1.49 ansible_user=root node_role=master

[etcd:children]
kube_control_plane

[kube_node]
k8s-master-01 ansible_host=192.168.1.49 ansible_user=root node_role=master
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

**Execute individually on each Target Node (cluster node)**

### 1. Python 3.10 Installation (Required on all nodes)

**CRITICAL:** Python 3.10+ must be installed on ALL target nodes before running Ansible playbooks.

**Execute on each Target Node:**

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

### 2. Firewall Disable (Required on all nodes)

```bash
# Rocky Linux/CentOS/RHEL/AlmaLinux
sudo systemctl stop firewalld
sudo systemctl disable firewalld
sudo systemctl status firewalld  # Verify it's disabled
```

### 3. DNS Configuration (Required on all nodes)

**CRITICAL:** DNS must be configured manually on all nodes due to `resolvconf_mode: none` setting.

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

**Important: Perform these tasks on ALL Target Nodes**

---

## Part 3: Cluster Deployment

**Execute on the Control Machine**

### 1. Target Nodes Connection Verification

```bash
# Verify Python 3.10+ is installed on ALL nodes
ansible all -i inventory/production/hosts.ini -m setup -a "filter=ansible_python_version"

# Test connectivity
ansible all -i inventory/production/hosts.ini -m ping
```

### 2. Configuration Setup

#### Basic Configuration

Edit `inventory/production/group_vars/all/vars.yml` for project-specific settings:
```yaml
# Project-specific variables
ansible_ssh_private_key_file: "~/.ssh/id_ed25519"
```

#### Monitoring Configuration (Enabled by Default)

Monitoring is automatically enabled and deployed with all cluster operations. No additional configuration required unless customization is needed in `inventory/production/group_vars/k8s_cluster/addons.yml`:
```yaml
# Monitoring stack is enabled by default
kube_prometheus_stack_enabled: true
kube_prometheus_stack_namespace: monitoring
kube_prometheus_stack_chart_version: "61.3.2"

# Basic configuration with NodePort access
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

#### CircleCI Configuration (Optional)

```bash
# Create vault file for sensitive data
ansible-vault create inventory/production/group_vars/all/vault.yml
# Add: vault_circleci_token: "YOUR_CIRCLECI_RUNNER_TOKEN"

# Configure CircleCI runner settings
vim inventory/production/group_vars/circleci/runner.yml
```

### 3. Cluster Deployment Commands

#### Basic Kubernetes Cluster with Monitoring

```bash
# Deploy Kubernetes cluster with automatic monitoring stack
./scripts/setup-cluster.sh cluster-only

# With specific inventory
./scripts/setup-cluster.sh cluster-only -i inventory/production/hosts.ini
```

#### Cluster with CircleCI and Monitoring

```bash
# Deploy cluster with monitoring and CircleCI runners
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password
```

#### Deploy Components Separately

```bash
# Deploy CircleCI to existing cluster
./scripts/setup-cluster.sh deploy-circleci --enable-circleci --vault-password .vault-password

# Deploy monitoring to existing cluster (manual - usually not needed)
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml
```

### 4. Available Deployment Modes

| Command | Description | Playbooks Used |
|---------|-------------|----------------|
| `cluster-only` | Deploy Kubernetes cluster with automatic monitoring | `cluster-only.yml` + `deploy-monitoring.yml` |
| `deploy-circleci` | Add CircleCI to existing cluster | `deploy-circleci.yml` |
| `add-node` | Add nodes to existing cluster | `add-node.yml` + `deploy-monitoring.yml` |
| `remove-node` | Remove nodes from cluster | `remove-node.yml` |
| `upgrade-cluster` | Upgrade cluster version | `upgrade-cluster.yml` |
| `reset-cluster` | Completely destroy cluster | `reset-cluster.yml` |

### 5. Installation Verification

```bash
# Check cluster status using kubespray artifacts
inventory/production/artifacts/kubectl.sh get nodes
inventory/production/artifacts/kubectl.sh get pods -A

# Copy kubectl to standard location (optional)
cp inventory/production/artifacts/kubectl /usr/local/bin/kubectl
cp inventory/production/artifacts/admin.conf ~/.kube/config

# Check cluster info
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# For monitoring (automatically deployed)
inventory/production/artifacts/kubectl.sh get pods -n monitoring

# Access monitoring services via NodePort:
# Grafana: http://NODE_IP:32000 (admin/admin123!@#)
# Prometheus: http://NODE_IP:32001
# AlertManager: http://NODE_IP:32002
```

### 6. Script Options and Parameters

```bash
# Full syntax
./scripts/setup-cluster.sh MODE [OPTIONS]

# Common options:
# -i, --inventory FILE    Specify inventory file (default: inventory/production/hosts.ini)
# --vault-password FILE   Vault password file for encrypted variables
# --enable-circleci       Enable CircleCI runner deployment
# --dry-run              Show what would be done without executing
# -v, --verbose          Enable verbose output
# --tags TAGS            Run only tasks with specified tags
# --extra-vars VARS      Additional variables

# Examples:
./scripts/setup-cluster.sh cluster-only -i inventory/staging/hosts.ini --dry-run
./scripts/setup-cluster.sh add-node --verbose --tags verification
./scripts/setup-cluster.sh remove-node --extra-vars "node=worker-1,worker-2"
```

---

## Post-Installation Tasks

### kubectl Access Setup

The kubespray deployment automatically creates kubectl artifacts in `inventory/{environment}/artifacts/`:
- `admin.conf` - Kubernetes configuration file
- `kubectl` - kubectl binary
- `kubectl.sh` - Ready-to-use helper script

Use kubectl via artifacts:
```bash
# Direct usage
inventory/production/artifacts/kubectl.sh get nodes

# Or copy to standard locations
cp inventory/production/artifacts/kubectl /usr/local/bin/kubectl
cp inventory/production/artifacts/admin.conf ~/.kube/config
```

### Monitoring Access (Automatically Deployed)

Monitoring stack is automatically deployed and accessible via:
- **Grafana**: `http://NODE_IP:32000` (admin/admin123!@#)
- **Prometheus**: `http://NODE_IP:32001`
- **AlertManager**: `http://NODE_IP:32002`

### CircleCI Verification

If CircleCI is deployed:
```bash
inventory/production/artifacts/kubectl.sh get pods -n circleci
inventory/production/artifacts/kubectl.sh logs -n circleci -l app.kubernetes.io/name=container-agent
```

---

## Task Summary by Location

| Task | Execution Location | Description |
|------|-------------------|-------------|
| Repository clone and setup | **Control Machine** | Configure Ansible environment |
| SSH key distribution | **Control Machine** | Copy SSH keys to target nodes |
| Inventory configuration | **Control Machine** | Configure cluster node information |
| Python installation | **Target Nodes** | Install on each node individually |
| Firewall disable | **Target Nodes** | Disable on each node individually |
| DNS configuration | **Target Nodes** | Configure on each node individually |
| Connection verification | **Control Machine** | Test node connectivity |
| Cluster deployment | **Control Machine** | Execute deployment scripts |
| Installation verification | **Control Machine** | Verify cluster status |

## Troubleshooting

### Common Issues

1. **Python not found error**: Ensure Python 3.10+ is installed on all target nodes
2. **DNS resolution fails**: Configure DNS manually on each target node
3. **SSH connection refused**: Verify SSH keys and firewall settings
4. **Kubespray submodule not found**: Run `git submodule update --init --recursive`
5. **Inventory file issues**: Check file format and node connectivity

### Verification Commands

```bash
# Check Python version on all nodes
ansible all -i inventory/production/hosts.ini -m shell -a "python --version"

# Test DNS resolution on all nodes
ansible all -i inventory/production/hosts.ini -m shell -a "nslookup google.com"

# Verify inventory syntax
ansible-inventory -i inventory/production/hosts.ini --list

# Check prerequisite with setup script
./scripts/setup-cluster.sh cluster-only --dry-run

# Verify monitoring deployment
inventory/production/artifacts/kubectl.sh get pods -n monitoring
inventory/production/artifacts/kubectl.sh get services -n monitoring
``` 