# Configuration Guide

Comprehensive configuration guide for kubespray-based Kubernetes clusters with integrated monitoring and optional CircleCI integration.

## Project Configuration Structure

This project integrates with Kubespray through configuration files located in `inventory/{env}/group_vars/`. Each environment (staging/production) has its own configuration set:

```
inventory/
├── staging/
│   ├── hosts.ini                      # Ansible inventory
│   ├── artifacts/                     # kubectl artifacts (created post-deployment)
│   ├── credentials/                   # Environment-specific credentials
│   ├── host_vars/                     # Host-specific variables
│   └── group_vars/
│       ├── all/
│       │   ├── kubespray.yml          # Kubespray core configuration
│       │   ├── vars.yml               # Project-specific variables
│       │   └── vault.yml              # Encrypted secrets
│       ├── k8s_cluster/
│       │   ├── k8s-cluster.yml        # Cluster configuration
│       │   ├── addons.yml             # Addon configuration (monitoring enabled by default)
│       │   ├── kube_control_plane.yml # Control plane settings
│       │   └── kube_node.yml          # Node settings
│       └── circleci/
│           └── runner.yml             # CircleCI runner config
└── production/
    ├── hosts.ini                      # Ansible inventory
    ├── artifacts/                     # kubectl artifacts (created post-deployment)
    ├── credentials/                   # Environment-specific credentials
    ├── host_vars/                     # Host-specific variables
    └── group_vars/                    # Same structure as staging
```

## Deployment Artifacts

After successful deployment, kubespray automatically creates kubectl artifacts in `inventory/{env}/artifacts/`:
- `admin.conf` - Kubernetes configuration file
- `kubectl` - kubectl binary
- `kubectl.sh` - Ready-to-use helper script

## Configuration File Categories

### 1. Kubespray Integration Files

These files maintain compatibility with kubespray while providing project-specific configurations:

1. `inventory/{env}/group_vars/all/kubespray.yml` - Core kubespray settings
2. `inventory/{env}/group_vars/k8s_cluster/k8s-cluster.yml` - Cluster configuration
3. `inventory/{env}/group_vars/k8s_cluster/addons.yml` - Addon configuration (monitoring enabled by default)
4. `inventory/{env}/group_vars/k8s_cluster/kube_control_plane.yml` - Control plane settings

### 2. Project-Specific Files

These files are created specifically for this project:

1. `inventory/{env}/group_vars/all/vars.yml` - Project-specific variables
2. `inventory/{env}/group_vars/all/vault.yml` - Encrypted secrets
3. `inventory/{env}/group_vars/circleci/runner.yml` - CircleCI runner configuration
4. `inventory/{env}/group_vars/k8s_cluster/kube_node.yml` - Node-specific settings
5. `inventory/{env}/hosts.ini` - Ansible inventory file

## Key Configuration Modifications

### 1. `inventory/{env}/group_vars/all/kubespray.yml`

**Purpose**: Core kubespray configuration with project-specific Kubernetes version

**Key modification**:
```yaml
# Kubernetes version pinning
kube_version: "v1.31.9"
```

All other settings remain compatible with kubespray defaults, ensuring safe upgrades.

### 2. `inventory/{env}/group_vars/k8s_cluster/k8s-cluster.yml`

**Purpose**: Cluster configuration with DNS management override

**Key modification**:
```yaml
# Line 208: DNS management override
# Original: resolvconf_mode: host_resolvconf
resolvconf_mode: none
```

**Reason**: Prevents kubespray from managing DNS, allowing manual DNS configuration via NetworkManager for better control in enterprise environments.

### 3. `inventory/{env}/group_vars/k8s_cluster/addons.yml`

**Purpose**: Addon configuration with monitoring stack enabled by default

**Key modifications**:
```yaml
# Essential addons for project functionality
helm_enabled: true                          # Required for monitoring and CircleCI deployment
metrics_server_enabled: true                # Required for resource monitoring
local_path_provisioner_enabled: true        # Dynamic storage provisioning
local_path_provisioner_namespace: "local-path-storage"
local_path_provisioner_storage_class: "local-path"

# Monitoring stack configuration (enabled by default)
kube_prometheus_stack_enabled: true
kube_prometheus_stack_namespace: monitoring
kube_prometheus_stack_chart_version: "61.3.2"

# Complete monitoring configuration with NodePort access
kube_prometheus_stack_values:
  grafana:
    adminPassword: "admin123!@#"
    service:
      type: NodePort
      nodePort: 32000
    # Scheduled on master nodes only
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
  
  prometheus:
    service:
      type: NodePort
      nodePort: 32001
    prometheusSpec:
      # Scheduled on master nodes only
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
  
  alertmanager:
    service:
      type: NodePort
      nodePort: 32002
    alertmanagerSpec:
      # Scheduled on master nodes only
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
```

**Note**: Monitoring stack is enabled by default and automatically deployed with all cluster operations.

### 4. `inventory/{env}/group_vars/k8s_cluster/kube_control_plane.yml`

**Purpose**: Optimized resource allocation for control plane nodes

**Key configuration**:
```yaml
# Resource reservations for master nodes (32 vCPU, 64GB RAM)
kube_memory_reserved: 6554Mi           # 10% for k8s components
kube_cpu_reserved: 3200m               # 10% for k8s components
kube_ephemeral_storage_reserved: 25Gi
kube_pid_reserved: "2000"

system_memory_reserved: 3277Mi          # 5% for system processes
system_cpu_reserved: 1600m             # 5% for system processes
system_ephemeral_storage_reserved: 10Gi
system_pid_reserved: "1000"

# Master node tainting for workload separation
kube_control_plane_taint: "node-role.kubernetes.io/control-plane:NoSchedule"
```

**Resource allocation summary**: 85% available for workloads, 15% reserved for system and Kubernetes components.

## Project-Specific Configuration Files

### 1. `inventory/{env}/group_vars/all/vars.yml`

**Purpose**: Project-specific Ansible variables

```yaml
# Project-specific variables (non-kubespray settings)
---
# SSH Configuration
ansible_ssh_private_key_file: "~/.ssh/id_ed25519"

# Project metadata
project_name: "circleci-k8s-ansible"
environment: "production"  # or "staging"

# Additional project-specific settings as needed
```

### 2. `inventory/{env}/group_vars/all/vault.yml`

**Purpose**: Encrypted sensitive data storage

```bash
# Create encrypted vault file
ansible-vault create inventory/production/group_vars/all/vault.yml

# Content example:
---
vault_circleci_token: "your-circleci-runner-token"
vault_grafana_admin_password: "secure-password"
vault_additional_secrets: "other-sensitive-data"
```

### 3. `inventory/{env}/group_vars/circleci/runner.yml`

**Purpose**: Complete CircleCI runner configuration

```yaml
# CircleCI runner configuration
---
runner:
  namespace: "circleci"
  resource_class: "your-org/medium"
  token: "{{ vault_circleci_token }}"
  image: "cimg/base:stable"
  replicas: 2
  
  # Resource allocation
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"
  
  # Worker node scheduling (master nodes are tainted)
  nodeSelector:
    node-role.kubernetes.io/worker: ""
  
  # Tolerations for specific workloads if needed
  tolerations: []
  
  # Additional runner configuration
  environment:
    CIRCLECI_RUNNER_API_URL: "https://runner.circleci.com"
  
  # Security context
  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
```

### 4. `inventory/{env}/hosts.ini`

**Purpose**: Ansible inventory defining cluster topology

```ini
# Kubespray-compatible inventory format
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

## Storage Configuration Requirements

This deployment utilizes storage bind mounts to optimize disk space usage across cluster nodes.

### Storage Mount Strategy

The cluster is configured to use bind mounts that redirect containerd and kubelet data from the default system partition to the home directory partition:

- `/var/lib/containerd` → `/home/containerd-data`
- `/var/lib/kubelet` → `/home/kubelet-data`

### Configuration Rationale

**Why bind mounts are required:**

1. **Capacity optimization**: Home directory partitions typically have significantly more storage capacity than root partitions
2. **Container storage**: Containerd stores all container images, layers, and runtime data which can consume substantial disk space
3. **Kubelet data**: Kubelet manages pod data, logs, and temporary files that grow over time
4. **Resource efficiency**: Prevents disk space exhaustion on the system partition during heavy container workloads

**Impact on cluster operations:**
- Container image pulls and builds utilize the larger home partition
- Pod ephemeral storage and logs are stored on the home partition  
- Kubernetes volume mounts for applications benefit from increased capacity
- Cluster scaling operations have more available storage for new workloads

For detailed installation procedures, refer to the [Installation Guide](INSTALLATION.md).

## DNS Configuration Requirements

Since `resolvconf_mode: none` is configured, DNS must be manually configured on all nodes:

```bash
# Configure DNS via NetworkManager on each node
nmcli connection modify "Wired connection 1" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes
nmcli connection up "Wired connection 1"

# Verify configuration
cat /etc/resolv.conf
nslookup google.com
```

## Monitoring Configuration

### Automatic Deployment (Default)

Monitoring is automatically deployed with all cluster operations:
- `./scripts/setup-cluster.sh cluster-only`
- `./scripts/setup-cluster.sh add-node`

### Manual Deployment

```bash
# Deploy monitoring stack to existing cluster
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml
```

### Accessing Monitoring Services

**Via NodePort (default configuration)**:
- **Grafana**: `http://NODE_IP:32000` (admin/admin123!@#)
- **Prometheus**: `http://NODE_IP:32001`
- **AlertManager**: `http://NODE_IP:32002`

**Via Port Forward using kubespray artifacts**:
```bash
# Grafana
inventory/production/artifacts/kubectl.sh port-forward -n monitoring service/kube-prometheus-stack-grafana 3000:80

# Prometheus
inventory/production/artifacts/kubectl.sh port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090

# AlertManager
inventory/production/artifacts/kubectl.sh port-forward -n monitoring service/kube-prometheus-stack-alertmanager 9093:9093
```

### Disabling Monitoring (Optional)

To disable automatic monitoring deployment, modify `inventory/{env}/group_vars/k8s_cluster/addons.yml`:
```yaml
# Disable monitoring stack
kube_prometheus_stack_enabled: false
```

## CircleCI Configuration

### Token Management

Store CircleCI tokens securely in the vault file:
```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml
# Add: vault_circleci_token: "YOUR_CIRCLECI_RUNNER_TOKEN"
```

### Runner Deployment

```bash
# Deploy CircleCI to existing cluster
./scripts/setup-cluster.sh deploy-circleci --enable-circleci --vault-password .vault-password

# Verify deployment using kubespray artifacts
inventory/production/artifacts/kubectl.sh get pods -n circleci
inventory/production/artifacts/kubectl.sh logs -n circleci -l app.kubernetes.io/name=container-agent
```

## Environment-Specific Configuration

### Staging vs Production Differences

Configure environment-specific settings by modifying files in respective directories:

**Staging configuration example**:
```yaml
# inventory/staging/group_vars/all/vars.yml
environment: "staging"
cluster_name: "staging-k8s"

# inventory/staging/group_vars/circleci/runner.yml
runner:
  resource_class: "your-org/small"
  replicas: 1
```

**Production configuration example**:
```yaml
# inventory/production/group_vars/all/vars.yml
environment: "production"
cluster_name: "production-k8s"

# inventory/production/group_vars/circleci/runner.yml
runner:
  resource_class: "your-org/large"
  replicas: 3
```

## Variable Precedence

Ansible variable precedence (highest to lowest):
1. **Command line extra vars** (`./scripts/setup-cluster.sh --extra-vars`)
2. **Inventory host/group vars** (`inventory/{env}/group_vars/`)
3. **Playbook vars**
4. **Role defaults**

This allows environment-specific overrides while maintaining default configurations.

## Node Scheduling Strategy

### Master Nodes (Control Plane)
- **Purpose**: System components and monitoring infrastructure only
- **Taint**: `node-role.kubernetes.io/control-plane:NoSchedule`
- **Scheduled Components**:
  - Kubernetes control plane components
  - Monitoring stack (Prometheus, Grafana, AlertManager)
  - System addons (CoreDNS, CNI controllers)

### Worker Nodes
- **Purpose**: Application workloads and CI/CD jobs
- **Label**: `node-role.kubernetes.io/worker`
- **Scheduled Components**:
  - CircleCI runner agents and job pods
  - Application deployments
  - User workloads

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

## Configuration Update Workflow

### 1. Environment Configuration Changes

```bash
# Edit configuration files
vim inventory/production/group_vars/k8s_cluster/addons.yml

# Apply changes (monitoring example)
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml
```

### 2. Kubernetes Version Updates

```bash
# Update version in kubespray.yml
vim inventory/production/group_vars/all/kubespray.yml
# Change: kube_version: "v1.31.10"

# Apply upgrade
./scripts/setup-cluster.sh upgrade-cluster
```

### 3. CircleCI Configuration Changes

```bash
# Update CircleCI settings
ansible-vault edit inventory/production/group_vars/all/vault.yml
vim inventory/production/group_vars/circleci/runner.yml

# Redeploy CircleCI
./scripts/setup-cluster.sh deploy-circleci --enable-circleci --vault-password .vault-password
```

### 4. Using kubectl with kubespray artifacts

```bash
# Direct usage with kubespray artifacts
inventory/production/artifacts/kubectl.sh get nodes
inventory/production/artifacts/kubectl.sh get pods -A

# Copy for standard usage
cp inventory/production/artifacts/kubectl /usr/local/bin/kubectl
cp inventory/production/artifacts/admin.conf ~/.kube/config
```

For complete configuration options, refer to the kubespray documentation and sample files in `3rdparty/kubespray/inventory/sample/group_vars/`. 