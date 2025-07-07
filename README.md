# CircleCI Kubernetes Self-Hosted Runner Automation

Deploy a production-ready Kubernetes cluster with automatic monitoring stack and optional CircleCI self-hosted container runners using Kubespray as the underlying infrastructure management tool.

This project provides automated deployment and management of Kubernetes clusters with integrated monitoring and optional CircleCI integration for CI/CD workflows.

## Quick Start

Below are several ways to deploy and manage a Kubernetes cluster using this automation.

### Prerequisites

- Python 3.10+ and Ansible 9.13+
- SSH access to target nodes (root or sudo user)
- Internet connectivity for package downloads
- Initialized kubespray submodule: `git submodule update --init --recursive`

### Deploy Basic Kubernetes Cluster with Monitoring

```bash
# 1. Install dependencies
python -m pip install -U -r requirements.txt

# 2. Configure inventory
cp inventory/production/hosts.ini.sample inventory/production/hosts.ini
# Edit inventory/production/hosts.ini with your node IPs

# 3. Deploy cluster with automatic monitoring stack
./scripts/setup-cluster.sh cluster-only
```

### Deploy Cluster with CircleCI and Monitoring

```bash
# 1. Configure CircleCI settings
ansible-vault create inventory/production/group_vars/all/vault.yml
# Add CircleCI configuration (see Configuration section)

# 2. Deploy cluster with monitoring and CircleCI
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password
```

### Deploy CircleCI to Existing Cluster

```bash
# Deploy CircleCI runner to existing cluster
./scripts/setup-cluster.sh deploy-circleci --enable-circleci --vault-password .vault-password
```

### Monitoring Stack

The monitoring stack (Prometheus, Grafana, AlertManager) is automatically deployed with all cluster operations for observability:

#### Automatic Deployment (Default)

Monitoring is automatically deployed when running:

```bash
# Deploy cluster with automatic monitoring
./scripts/setup-cluster.sh cluster-only

# Add nodes with automatic monitoring update
./scripts/setup-cluster.sh add-node
```

#### Manual Deployment

```bash
# Deploy monitoring stack separately
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# Access via NodePort (default ports):
# Grafana: http://NODE_IP:32000 (admin/admin123!@#)
# Prometheus: http://NODE_IP:32001
# AlertManager: http://NODE_IP:32002
```

## Documentation

- [Installation Guide](docs/INSTALLATION.md) - Installation and basic deployment
- [Configuration Guide](docs/CONFIGURATION.md) - Advanced configuration and settings
- [Operations Guide](docs/OPERATIONS.md) - Security, maintenance, and troubleshooting

### Key Features

- **Kubernetes cluster deployment** using proven Kubespray automation
- **Integrated monitoring stack** with Prometheus, Grafana, and AlertManager (automatic)
- **CircleCI self-hosted runners** for CI/CD workflows (optional)
- **Multi-environment support** (staging, production)
- **Node management** operations (add, remove, upgrade)
- **Security hardening** with kubespray best practices
- **Kubespray artifacts integration** for kubectl access

## Supported Operating Systems

- **Rocky Linux** 8, 9
- **CentOS** 8, 9
- **RHEL** 8, 9
- **AlmaLinux** 8, 9
- **Ubuntu** 20.04, 22.04

## Supported Architectures

- **x86_64** (full support)
- **ARM64/aarch64** (full support)

Note: Mixed architectures in the same cluster are not recommended.

## Deployment Architecture

This project is designed with clear role separation and automatic monitoring integration:

1. **Basic Kubernetes deployment** using Kubespray (default)
2. **Automatic monitoring stack** deployment with all cluster operations
3. **Optional CircleCI integration** deployed separately
4. **All playbooks** are wrappers around standard Kubespray playbooks

## Deployment Modes

| Mode | Script Command | Underlying Playbook | Description |
|------|----------------|-------------------|-------------|
| **cluster-only** | `./scripts/setup-cluster.sh cluster-only` | `cluster-only.yml` (wraps `3rdparty/kubespray/cluster.yml`) + `deploy-monitoring.yml` | Deploy Kubernetes cluster with automatic monitoring |
| **cluster-only + CircleCI** | `./scripts/setup-cluster.sh cluster-only --enable-circleci` | `cluster-only.yml` + `deploy-monitoring.yml` + `deploy-circleci.yml` | Deploy K8s + monitoring + CircleCI |
| **deploy-circleci** | `./scripts/setup-cluster.sh deploy-circleci` | `deploy-circleci.yml` only | Add CircleCI to existing cluster |
| **deploy-monitoring** | `ansible-playbook -i inventory/ENV/hosts.ini playbooks/deploy-monitoring.yml` | `deploy-monitoring.yml` only | Add monitoring stack to existing cluster (manual) |
| **add-node** | `./scripts/setup-cluster.sh add-node` | `add-node.yml` (wraps `3rdparty/kubespray/scale.yml`) + `deploy-monitoring.yml` | Add nodes with automatic monitoring update |
| **add-node + CircleCI** | `./scripts/setup-cluster.sh add-node --enable-circleci` | `add-node.yml` + `deploy-monitoring.yml` + `deploy-circleci.yml` | Add nodes + monitoring + CircleCI |
| **remove-node** | `./scripts/setup-cluster.sh remove-node` | `remove-node.yml` (wraps `3rdparty/kubespray/remove-node.yml`) | Remove nodes |
| **upgrade-cluster** | `./scripts/setup-cluster.sh upgrade-cluster` | `upgrade-cluster.yml` (wraps `3rdparty/kubespray/upgrade-cluster.yml`) | Upgrade cluster |
| **reset-cluster** | `./scripts/setup-cluster.sh reset-cluster` | `reset-cluster.yml` (wraps `3rdparty/kubespray/reset.yml`) | Complete cluster removal |

**Note**: Monitoring stack is automatically deployed with `cluster-only` and `add-node` operations for observability.

## Inventory Structure (Kubespray Standard)

This project uses standard Kubespray inventory structure. Follow [Kubespray documentation](3rdparty/kubespray/docs/getting_started/getting-started.md) for inventory management:

```yaml
all:
  children:
    kube_control_plane:  # Control plane nodes
      hosts:
        k8s-master-01:
          ansible_host: 192.168.1.49
          ansible_user: root
    
    kube_node:          # All cluster nodes (masters + workers)
      hosts:
        k8s-master-01:
          ansible_host: 192.168.1.49
          ansible_user: root
        k8s-worker-01:
          ansible_host: 192.168.2.8
          ansible_user: root
        k8s-worker-02:
          ansible_host: 192.168.1.48
          ansible_user: root
    
    etcd:               # etcd cluster nodes
      children:
        kube_control_plane:
    
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    
    circleci:           # CircleCI management group
      children:
        kube_control_plane:
```

## Node Management (Kubespray Way)

### Adding Nodes

```bash
# 1. Add new node to inventory file
vim inventory/production/hosts.ini

# 2. Run scale playbook (includes automatic monitoring update)
./scripts/setup-cluster.sh add-node

# With CircleCI:
./scripts/setup-cluster.sh add-node --enable-circleci
```

### Removing Nodes

```bash
# 1. Specify nodes to remove
./scripts/setup-cluster.sh remove-node --extra-vars "node=worker-1,worker-2"

# 2. Remove from inventory file after successful removal
vim inventory/production/hosts.ini
```

## Architecture

### Node Scheduling Strategy

This deployment implements a strict master/worker node separation strategy:

#### Master Nodes (Control Plane)
- **Purpose**: System components and monitoring infrastructure only
- **Taints**: `node-role.kubernetes.io/control-plane:NoSchedule` (kubespray default)
- **Scheduled Components**:
  - Kubernetes control plane (etcd, kube-apiserver, kube-controller-manager, kube-scheduler)
  - System pods (CoreDNS, Calico controllers, etc.)
  - Monitoring stack (Prometheus, Grafana, Alertmanager, kube-state-metrics)
  - System addons and operators
- **Excluded Components**:
  - CircleCI runners and job pods
  - User workloads
  - Heavy compute tasks

#### Worker Nodes  
- **Purpose**: Application workloads and CI/CD jobs
- **Labels**: `node-role.kubernetes.io/worker`
- **Scheduled Components**:
  - CircleCI runner agents
  - CircleCI job pods (heavy compute workloads)
  - Application deployments
  - User workloads
- **Resource Allocation**:
  - Optimized for compute-intensive CI jobs
  - Isolated from control plane interference

#### Benefits
- **Stability**: Control plane protected from resource-heavy CI jobs
- **Performance**: Monitoring components get dedicated master node resources
- **Predictability**: Clear separation of system vs user workloads
- **Scalability**: Workers can be scaled independently for CI capacity

### Component Distribution

```
Master Nodes:
├── Control Plane
│   ├── etcd
│   ├── kube-apiserver
│   ├── kube-controller-manager
│   └── kube-scheduler
├── Monitoring Stack (Automatic)
│   ├── Prometheus
│   ├── Grafana  
│   ├── Alertmanager
│   └── kube-state-metrics
└── System Components
    ├── CoreDNS
    ├── Calico Policy Controller
    └── CNI components

Worker Nodes:
├── CircleCI Infrastructure (Optional)
│   ├── Runner Agents
│   └── Job Pods
├── Node Exporters (DaemonSet)
└── User Applications
```

## Configuration Files Structure

This project integrates with Kubespray through configuration files in `inventory/{env}/group_vars/`:

```
inventory/
├── staging/
│   ├── hosts.ini                      # Inventory file
│   ├── artifacts/                     # kubectl artifacts (created post-deployment)
│   └── group_vars/
│       ├── all/
│       │   ├── kubespray.yml          # Kubespray configuration
│       │   ├── vars.yml               # Project-specific variables
│       │   └── vault.yml              # Encrypted variables
│       ├── k8s_cluster/
│       │   ├── k8s-cluster.yml        # Cluster configuration
│       │   ├── addons.yml             # Addon configuration (monitoring enabled)
│       │   ├── kube_control_plane.yml # Control plane settings
│       │   └── kube_node.yml          # Node settings
│       └── circleci/
│           └── runner.yml             # CircleCI runner config
└── production/
    ├── hosts.ini                      # Inventory file
    ├── artifacts/                     # kubectl artifacts (created post-deployment)
    └── group_vars/                    # Same structure as staging
```

## Usage Examples

```bash
# Most common: Full cluster + monitoring + CircleCI
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password

# Kubernetes + monitoring only (default)
./scripts/setup-cluster.sh cluster-only

# Add nodes (after updating inventory) - includes monitoring update
./scripts/setup-cluster.sh add-node

# Upgrade cluster (after updating kube_version in kubespray.yml)
./scripts/setup-cluster.sh upgrade-cluster
```

## kubectl Access

After deployment, kubespray automatically creates kubectl artifacts in `inventory/{env}/artifacts/`:
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