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
3. **Cluster Deployment** - Deploy cluster and monitoring separately using ansible playbooks

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

# Scripts are no longer used - direct ansible playbooks are used instead
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

### 3. Storage Configuration (Required on all nodes)

**CRITICAL:** Configure storage mounts to use larger home directory capacity for containerd and kubelet data.

**NOTE:** This configuration is automatically handled by `playbooks/cluster-only.yml` during cluster deployment. The manual steps below are provided for reference and troubleshooting purposes.

```bash
# Create mount point directories in /home
sudo mkdir -p /home/containerd-data
sudo mkdir -p /home/kubelet-data

# Create target directories if they don't exist
sudo mkdir -p /var/lib/containerd
sudo mkdir -p /var/lib/kubelet

# Add bind mounts to /etc/fstab
echo "/home/containerd-data /var/lib/containerd none bind 0 0" | sudo tee -a /etc/fstab
echo "/home/kubelet-data /var/lib/kubelet none bind 0 0" | sudo tee -a /etc/fstab

# Mount the filesystems
sudo mount -a

# Verify mounts are active
mount | grep -E "(containerd|kubelet)"
df -h | grep -E "(containerd|kubelet)"
```

**Important:** This configuration ensures that containerd and kubelet data use the larger home directory partition instead of the default system partition.

**Automated vs Manual Configuration:**
- **Automated**: The `playbooks/cluster-only.yml` playbook automatically configures these bind mounts during cluster deployment
- **Manual**: Use the above commands only if you need to configure storage manually or for troubleshooting mount issues

### 4. DNS Configuration (Required on all nodes)

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

### 5. SSD Performance Optimization (Recommended on all nodes with SSD storage)

**CRITICAL:** Disabling SSD write cache can significantly improve performance on Rocky Linux 8 systems.

```bash
# Disable write cache on all SSD drives
sudo hdparm -W0 /dev/sd*

# For systems with NVMe drives, use:
sudo hdparm -W0 /dev/nvme*
```

**Verification of write cache status:**
```bash
# Check write cache status for all drives
sudo hdparm -I /dev/sd*

# Look for the "Commands/features:" section
# Under "Enabled Supported:" check the Write cache line:
# - No asterisk (*) before "Write cache" = OFF (desired state)
# - Asterisk (*) before "Write cache" = ON
```

**Important Notes:**
- Write cache must be disabled on ALL drives in the same partition group for effectiveness
- This setting significantly improves I/O performance without affecting SSD lifespan
- Apply this configuration to all cluster nodes with SSD storage
- The setting may need to be reapplied after system reboots (consider adding to startup scripts)

### 6. Test Repository Pre-cloning (Required on worker nodes for test performance)

**CRITICAL:** Pre-clone test repository on worker nodes to reduce pod startup time during test execution.

**Execute on Worker Nodes only:**

```bash
# Create test repository directory
sudo mkdir -p /home/tc-repo
sudo chown root:root /home/tc-repo
sudo chmod 755 /home/tc-repo
cd /home/tc-repo

# Shallow clone with blob filtering and sparse checkout for optimal performance
git clone --depth=1 --filter=blob:none --sparse <REPO_URL> cubrid-testcases-private-ex
cd cubrid-testcases-private-ex

# Checkout only shell directory to minimize disk usage
git sparse-checkout set --cone shell
```

**Verification:**
```bash
# Verify repository structure
ls -la /home/tc-repo/cubrid-testcases-private-ex/
du -sh /home/tc-repo/cubrid-testcases-private-ex/

# Check sparse-checkout configuration
cd /home/tc-repo/cubrid-testcases-private-ex
git sparse-checkout list
```

**Important Notes:**
- This step is required ONLY on worker nodes, not on master nodes
- Shallow clone with blob filtering significantly reduces clone time and disk usage
- Sparse checkout ensures only necessary test directories are downloaded
- This pre-cloning reduces pod initialization time during test execution
- Replace `<REPO_URL>` with your actual test repository URL

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

#### Monitoring Configuration

Monitoring must be deployed separately after cluster installation. Configure monitoring settings in `inventory/production/group_vars/k8s_cluster/addons.yml`:
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

#### Basic Kubernetes Cluster

```bash
# Deploy Kubernetes cluster only
ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml

# With different inventory
ansible-playbook -i inventory/staging/hosts.ini playbooks/cluster-only.yml
```

#### Cluster with CircleCI

```bash
# Deploy cluster with CircleCI runners
ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml --vault-password-file .vault-password --extra-vars "circleci_enabled=true"
```

#### Deploy Components Separately

```bash
# Deploy CircleCI to existing cluster
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-circleci.yml --vault-password-file .vault-password

# Deploy monitoring to existing cluster (required after cluster installation)
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml
```

### 4. Available Deployment Modes

| Command | Description | Playbooks Used |
|---------|-------------|----------------|
| `ansible-playbook -i inventory/ENV/hosts.ini playbooks/cluster-only.yml` | Deploy Kubernetes cluster only | `cluster-only.yml` |
| `ansible-playbook -i inventory/ENV/hosts.ini playbooks/deploy-monitoring.yml` | Deploy monitoring stack to existing cluster | `deploy-monitoring.yml` |
| `ansible-playbook -i inventory/ENV/hosts.ini playbooks/deploy-circleci.yml` | Add CircleCI to existing cluster | `deploy-circleci.yml` |
| `ansible-playbook -i inventory/ENV/hosts.ini playbooks/add-node.yml` | Add nodes to existing cluster | `add-node.yml` |
| `ansible-playbook -i inventory/ENV/hosts.ini playbooks/remove-node.yml` | Remove nodes from cluster | `remove-node.yml` |
| `ansible-playbook -i inventory/ENV/hosts.ini playbooks/upgrade-cluster.yml` | Upgrade cluster version | `upgrade-cluster.yml` |
| `ansible-playbook -i inventory/ENV/hosts.ini playbooks/reset-cluster.yml` | Completely destroy cluster | `reset-cluster.yml` |

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

# Deploy monitoring stack after cluster installation
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# Verify monitoring deployment
inventory/production/artifacts/kubectl.sh get pods -n monitoring

# Access monitoring services via NodePort:
# Grafana: http://NODE_IP:32000 (admin/admin123!@#)
# Prometheus: http://NODE_IP:32001
# AlertManager: http://NODE_IP:32002
```

### 6. Ansible Playbook Options and Parameters

```bash
# Full syntax
ansible-playbook -i INVENTORY PLAYBOOK [OPTIONS]

# Common options:
# -i FILE                 Specify inventory file
# --vault-password-file   Vault password file for encrypted variables
# --extra-vars VARS       Additional variables (use circleci_enabled=true for CircleCI)
# --check                 Show what would be done without executing (dry run)
# -v                      Enable verbose output
# --tags TAGS             Run only tasks with specified tags

# Examples:
ansible-playbook -i inventory/staging/hosts.ini playbooks/cluster-only.yml --check
ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml -v --tags verification
ansible-playbook -i inventory/production/hosts.ini playbooks/remove-node.yml --extra-vars "node=worker-1,worker-2"
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

### Monitoring Access (Deploy After Cluster Installation)

Monitoring stack must be deployed separately and is accessible via:
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
| Storage configuration | **Target Nodes** | Configure bind mounts on each node individually |
| DNS configuration | **Target Nodes** | Configure on each node individually |
| SSD performance optimization | **Target Nodes** | Disable write cache on each node individually |
| Test repository pre-cloning | **Worker Nodes** | Clone test repository on worker nodes for performance |
| Connection verification | **Control Machine** | Test node connectivity |
| Cluster deployment | **Control Machine** | Execute deployment scripts |
| Installation verification | **Control Machine** | Verify cluster status |

## Troubleshooting

### Common Installation Issues

1. **Python not found error**: Ensure Python 3.10+ is installed on all target nodes
2. **Storage mount failures during preparation**: Verify fstab entries and mount commands on target nodes
3. **DNS resolution fails during deployment**: Configure DNS manually on each target node before deployment
4. **SSH connection refused**: Verify SSH keys and firewall settings
5. **Kubespray submodule not found**: Run `git submodule update --init --recursive`
6. **Inventory file issues**: Check file format and node connectivity
7. **Ansible prerequisite failures**: Use pre-deployment verification commands above

### Pre-Deployment Verification

**Execute on Control Machine before cluster deployment:**

```bash
# Check Python version on all nodes
ansible all -i inventory/production/hosts.ini -m shell -a "python --version"

# Verify storage mounts on all nodes
ansible all -i inventory/production/hosts.ini -m shell -a "mount | grep -E '(containerd|kubelet)'"
ansible all -i inventory/production/hosts.ini -m shell -a "df -h | grep -E '(containerd|kubelet)'"

# Test DNS resolution on all nodes
ansible all -i inventory/production/hosts.ini -m shell -a "nslookup google.com"

# Verify SSD write cache is disabled on all nodes (optional performance check)
ansible all -i inventory/production/hosts.ini -m shell -a "hdparm -I /dev/sd* | grep -A5 -B5 'Write cache'"

# Verify test repository pre-cloning on worker nodes (optional performance check)
ansible kube_node -i inventory/production/hosts.ini -m shell -a "ls -la /home/tc-repo/cubrid-testcases-private-ex/ && du -sh /home/tc-repo/"

# Verify inventory syntax
ansible-inventory -i inventory/production/hosts.ini --list

# Check prerequisites with dry run
ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml --check
```

### Post-Deployment Verification

**Execute on Control Machine after cluster deployment:**

```bash
# Verify cluster status
inventory/production/artifacts/kubectl.sh get nodes
inventory/production/artifacts/kubectl.sh get pods -A

# Verify monitoring deployment
inventory/production/artifacts/kubectl.sh get pods -n monitoring
inventory/production/artifacts/kubectl.sh get services -n monitoring
``` 