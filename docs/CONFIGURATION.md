# Configuration Guide

This guide covers the kubespray configuration files and the specific modifications made for this project.

## Project Configuration Structure

This project integrates with Kubespray through configuration files located in `inventory/{env}/group_vars/`. Each environment (staging/production) has its own configuration set:

```
inventory/
├── staging/
│   ├── hosts.ini                      # Ansible inventory
│   └── group_vars/
│       ├── all/
│       │   ├── kubespray.yml          # Kubespray core configuration
│       │   ├── vars.yml               # Project-specific variables
│       │   └── vault.yml              # Encrypted secrets
│       ├── k8s_cluster/
│       │   ├── k8s-cluster.yml        # Cluster configuration
│       │   ├── addons.yml             # Addon configuration
│       │   ├── kube_control_plane.yml # Control plane settings
│       │   └── kube_node.yml          # Node settings
│       └── circleci/
│           └── runner.yml             # CircleCI runner config
└── production/
    ├── hosts.ini                      # Ansible inventory  
    └── group_vars/                    # Same structure as staging
```

## Configuration File Categories

### 1. Files Based on Kubespray Samples (Modified)

These files are copied from `3rdparty/kubespray/inventory/sample/group_vars/` with project-specific modifications:

1. `inventory/{env}/group_vars/all/kubespray.yml` ← Based on `3rdparty/kubespray/inventory/sample/group_vars/all/all.yml`
2. `inventory/{env}/group_vars/k8s_cluster/k8s-cluster.yml` ← Based on `3rdparty/kubespray/inventory/sample/group_vars/k8s_cluster/k8s-cluster.yml`
3. `inventory/{env}/group_vars/k8s_cluster/addons.yml` ← Based on `3rdparty/kubespray/inventory/sample/group_vars/k8s_cluster/addons.yml`
4. `inventory/{env}/group_vars/k8s_cluster/kube_control_plane.yml` ← Based on `3rdparty/kubespray/inventory/sample/group_vars/k8s_cluster/kube_control_plane.yml`

### 2. Project-Specific Files (New)

These files are created specifically for this project and are not present in kubespray:

1. `inventory/{env}/group_vars/all/vars.yml` - Project-specific variables
2. `inventory/{env}/group_vars/all/vault.yml` - Encrypted secrets  
3. `inventory/{env}/group_vars/circleci/runner.yml` - CircleCI runner configuration
4. `inventory/{env}/group_vars/k8s_cluster/kube_node.yml` - Node-specific settings
5. `inventory/{env}/hosts.ini` - Ansible inventory file

## Kubespray-Based File Modifications

### 1. `inventory/{env}/group_vars/all/kubespray.yml`
**Added at the top of the file:**
```yaml
# Kubernetes version
kube_version: "1.31.9"
```
**Purpose:** Pin specific Kubernetes version for consistent deployments across environments.

**All other content:** Identical to kubespray original (`all.yml`)

### 2. `inventory/{env}/group_vars/k8s_cluster/k8s-cluster.yml`
**Modified line 208:**
```yaml
# Original: resolvconf_mode: host_resolvconf
resolvconf_mode: none
```
**Purpose:** Prevent kubespray from managing DNS, allowing manual DNS configuration via NetworkManager.

**All other content:** Identical to kubespray original

### 3. `inventory/{env}/group_vars/k8s_cluster/addons.yml`
**Modified default values:**
```yaml
# Lines 6-7: Helm deployment
# Original: helm_enabled: false
helm_enabled: true

# Lines 14-15: Metrics Server deployment  
# Original: metrics_server_enabled: false
metrics_server_enabled: true

# Lines 22-24: Rancher Local Path Provisioner
# Original: local_path_provisioner_enabled: false
local_path_provisioner_enabled: true
local_path_provisioner_namespace: "local-path-storage"
local_path_provisioner_storage_class: "local-path"
```

**Added at end of file (lines 251-405):**
```yaml
# kube-prometheus-stack monitoring deployment
# Based on https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
kube_prometheus_stack_enabled: true
kube_prometheus_stack_namespace: monitoring
kube_prometheus_stack_chart_version: "61.3.2"

# kube-prometheus-stack configuration values
# Full configuration reference: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack#configuration
kube_prometheus_stack_values:
  # [Extensive monitoring configuration - 155 lines]
  # Including Grafana, Prometheus, Alertmanager, and component settings
  # All components scheduled on master nodes with specific resource limits
```

**Purpose:** 
- `helm_enabled: true` - Required for CircleCI runner deployment via Helm charts
- `metrics_server_enabled: true` - Enable cluster resource monitoring and HPA
- `local_path_provisioner_enabled: true` - Provide dynamic storage provisioning
- Monitoring stack - Complete Prometheus/Grafana/Alertmanager deployment with NodePort access

### 4. `inventory/{env}/group_vars/k8s_cluster/kube_control_plane.yml`
**Completely replaced content:**

**Original (lines 1-12):**
```yaml
# Reservation for control plane kubernetes components
# kube_memory_reserved: 512Mi
# kube_cpu_reserved: 200m
# kube_ephemeral_storage_reserved: 2Gi
# kube_pid_reserved: "1000"

# Reservation for control plane host system
# system_memory_reserved: 256Mi
# system_cpu_reserved: 250m
# system_ephemeral_storage_reserved: 2Gi
# system_pid_reserved: "1000"
```

**Modified (lines 1-24):**
```yaml
# Reservation for control plane kubernetes components
# Master node (32 vCPU, 64GiB RAM, 4T SSD) - Reserve 10% for k8s components
kube_memory_reserved: 6554Mi     # ~6.4GB (10% of 64GB)
kube_cpu_reserved: 3200m         # 3.2 vCPU (10% of 32 vCPU)
kube_ephemeral_storage_reserved: 25Gi  # Sufficient for k8s logs, tmp files
kube_pid_reserved: "2000"        # Higher PID limit for k8s processes

# Reservation for control plane host system  
# Reserve 5% for system processes (OS, SSH, monitoring, etc.)
system_memory_reserved: 3277Mi   # ~3.2GB (5% of 64GB)
system_cpu_reserved: 1600m       # 1.6 vCPU (5% of 32 vCPU)
system_ephemeral_storage_reserved: 10Gi  # System logs, cache, tmp
system_pid_reserved: "1000"      # System process PID reservation

# Summary for 192.168.1.49 (32 vCPU, 64GiB RAM, 4T SSD):
# - System reserved: 1.6 vCPU, 3.2GB, 10GB storage, 1000 PIDs (5%)
# - Kubernetes reserved: 3.2 vCPU, 6.4GB, 25GB storage, 2000 PIDs (10%) 
# - Available for workloads: 27.2 vCPU, 54.4GB, remaining storage (85%)

# Master node scheduling configuration
# Taint master node to prevent regular workloads from being scheduled
# Only monitoring stack and other critical components should run on master
kube_control_plane_taint: "node-role.kubernetes.io/control-plane:NoSchedule"
```

**Purpose:** Optimized resource allocation for high-spec servers (32 vCPU, 64GB RAM), providing 85% of resources for workloads while ensuring system stability.

## Project-Specific Files (New)

### 1. `inventory/{env}/group_vars/all/vars.yml`
**Completely new file with project-specific variables:**
```yaml
# Project-specific variables (non-kubespray settings)
---
# SSH Configuration (project-specific)
ansible_ssh_private_key_file: "~/.ssh/id_ed25519"
# SSH connection arguments, retries, and timeout are configured in ansible.cfg

# Project-specific paths
# Note: CircleCI configuration is now in group_vars/circleci/
# Note: Kubernetes manifests are managed by kubespray at /etc/kubernetes/manifests 
```
**Purpose:** Store project-specific Ansible variables separate from kubespray configuration.

### 2. `inventory/{env}/group_vars/all/vault.yml`
**Encrypted file for sensitive data:**
```bash
# Create/edit with ansible-vault
ansible-vault create inventory/production/group_vars/all/vault.yml
ansible-vault edit inventory/production/group_vars/all/vault.yml
```
**Purpose:** Store encrypted secrets like CircleCI tokens, passwords, and API keys.

### 3. `inventory/{env}/group_vars/circleci/runner.yml`
**CircleCI-specific configuration (131 lines):**
```yaml
# CircleCI runner configuration
runner:
  namespace: "circleci"
  resource_class: "your-org/medium"
  token: "{{ vault_circleci_token }}"
  image: "cimg/base:stable"
  replicas: 2
  
  # Resource limits
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"
  
  # Node selector to run on worker nodes only
  nodeSelector:
    node-role.kubernetes.io/worker: ""
  
  # Tolerations (if needed)
  tolerations: []
```
**Purpose:** Complete CircleCI runner configuration for deployment via Helm charts.

### 4. `inventory/{env}/hosts.ini`
**Ansible inventory file based on kubespray format:**
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
**Purpose:** Define cluster nodes and their roles using kubespray-compatible inventory format.

## DNS Configuration

Since `resolvconf_mode: none` is set, DNS must be configured manually on all nodes before deployment:

```bash
# Configure DNS via NetworkManager
nmcli connection modify "Wired connection 1" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes
nmcli connection up "Wired connection 1"

# Verify configuration
cat /etc/resolv.conf
nslookup google.com
```

## CircleCI Configuration

Store the CircleCI token securely in `inventory/{env}/group_vars/all/vault.yml`:
```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml
# Add: vault_circleci_token: "YOUR_CIRCLECI_RUNNER_TOKEN"
```

## Monitoring Configuration

The monitoring stack uses kube-prometheus-stack, which includes Prometheus, Grafana, and AlertManager.

### Deployment Modes

#### Automatic Deployment
When `kube_prometheus_stack_enabled: true` is set, monitoring is automatically deployed during:
- `./scripts/setup-cluster.sh cluster-only`
- `./scripts/setup-cluster.sh add-node`

#### Manual Deployment
```bash
# Deploy monitoring stack to existing cluster
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml
```

### Accessing Monitoring Services

**Via NodePort:**
- **Grafana**: `http://NODE_IP:32000` (admin/admin123!@#)
- **Prometheus**: `http://NODE_IP:32001`
- **AlertManager**: `http://NODE_IP:32002`

**Via Port Forward:**
```bash
# Grafana
kubectl port-forward -n monitoring service/kube-prometheus-stack-grafana 3000:80

# Prometheus  
kubectl port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090

# AlertManager
kubectl port-forward -n monitoring service/kube-prometheus-stack-alertmanager 9093:9093
```

## Environment-Specific Configuration

### Staging vs Production

Configure different settings for each environment by modifying files in:
- `inventory/staging/group_vars/`
- `inventory/production/group_vars/`

Example differences:

**Staging (`inventory/staging/group_vars/all/vars.yml`):**
```yaml
cluster_name: "staging-k8s"
environment: "staging"
```

**Production (`inventory/production/group_vars/all/vars.yml`):**
```yaml
cluster_name: "production-k8s"
environment: "production"
```

## Variable Precedence

Ansible variable precedence (highest to lowest):
1. **Command line extra vars** (`--extra-vars`)
2. **Inventory host/group vars** (`inventory/{env}/group_vars/`)
3. **Playbook vars**
4. **Role defaults**

This allows environment-specific overrides while maintaining default configurations.

## Advanced Configuration Options

### Network Configuration
```yaml
# In k8s-cluster.yml
kube_service_addresses: "10.233.0.0/18"
kube_pods_subnet: "10.233.64.0/18"
kube_network_node_prefix: 24
```

### Security Settings
```yaml
# In k8s-cluster.yml
kube_encrypt_secret_data: true
kube_api_secure_port: 6443
```

### Performance Tuning
```yaml
# In kube_control_plane.yml
kubelet_max_pods: 110
kube_apiserver_request_timeout: "60s"
```

For complete configuration options, refer to the kubespray documentation and sample files in `3rdparty/kubespray/inventory/sample/group_vars/`. 