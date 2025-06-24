# CircleCI Kubernetes Self-Hosted Runner Automation

Deploy a production-ready Kubernetes cluster with optional CircleCI self-hosted container runners using Kubespray as the underlying infrastructure management tool.

This project provides automated deployment and management of Kubernetes clusters with optional CircleCI integration for CI/CD workflows.

## Quick Start

Below are several ways to deploy and manage a Kubernetes cluster using this automation.

### Prerequisites

- Python 3.10+ and Ansible 9.13+
- SSH access to target nodes (root or sudo user)
- Internet connectivity for package downloads
- Initialized kubespray submodule: `git submodule update --init --recursive`

### Deploy Basic Kubernetes Cluster

```bash
# 1. Install dependencies
python -m pip install -U -r requirements.txt

# 2. Configure inventory
cp inventory/production/hosts.ini.sample inventory/production/hosts.ini
# Edit inventory/production/hosts.ini with your node IPs

# 3. Deploy basic cluster
./scripts/setup-cluster.sh cluster-only
```

### Deploy Cluster with CircleCI (Optional)

```bash
# 1. Configure CircleCI settings (optional)
ansible-vault create inventory/production/group_vars/circleci/runner.yml
# Add CircleCI configuration (see Configuration section)

# 2. Deploy cluster with CircleCI
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password
```

### Deploy CircleCI to Existing Cluster

```bash
# Deploy CircleCI runner to existing cluster
./scripts/setup-cluster.sh deploy-circleci --enable-circleci --vault-password .vault-password
```

### Deploy Monitoring Stack

The monitoring stack (Prometheus, Grafana, AlertManager) can be deployed automatically or manually:

#### Automatic Deployment (Recommended)

Monitoring is automatically deployed when `kube_prometheus_stack_enabled: true` is set in `addons.yml`:

```bash
# Deploy cluster with automatic monitoring (if enabled in addons.yml)
./scripts/setup-cluster.sh cluster-only

# Add nodes with automatic monitoring update (if enabled)
./scripts/setup-cluster.sh add-node
```

#### Manual Deployment

```bash
# Deploy monitoring stack separately
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# Access via NodePort (ports configured in addons.yml):
# Grafana: http://NODE_IP:GRAFANA_PORT (default: admin/admin123!@#)
# Prometheus: http://NODE_IP:PROMETHEUS_PORT
# AlertManager: http://NODE_IP:ALERTMANAGER_PORT
```

## Documentation

- [Installation Guide](docs/INSTALLATION.md) - Installation and basic deployment
- [Configuration Guide](docs/CONFIGURATION.md) - Advanced configuration and settings
- [Operations Guide](docs/OPERATIONS.md) - Security, maintenance, and troubleshooting

### Key Features

- **Kubernetes cluster deployment** using proven Kubespray automation
- **CircleCI self-hosted runners** for CI/CD workflows
- **Monitoring stack** with Prometheus, Grafana, and AlertManager
- **Multi-environment support** (staging, production)
- **Node management** operations (add, remove, upgrade)
- **Security hardening** with kubespray best practices

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

This project is designed with clear role separation:

1. **Basic Kubernetes deployment** using Kubespray (default)
2. **Optional CircleCI integration** deployed separately
3. **Optional monitoring stack** with Prometheus, Grafana, and AlertManager
4. **All playbooks** are wrappers around standard Kubespray playbooks

## Deployment Modes

| Mode | Script Command | Underlying Playbook | Description |
|------|----------------|-------------------|-------------|
| **cluster-only** | `./scripts/setup-cluster.sh cluster-only` | kubespray/cluster.yml [+ deploy-monitoring.yml] | Deploy Kubernetes cluster (+ monitoring if enabled) |
| **cluster-only + CircleCI** | `./scripts/setup-cluster.sh cluster-only --enable-circleci` | kubespray/cluster.yml + deploy-circleci.yml [+ deploy-monitoring.yml] | Deploy K8s + CircleCI (+ monitoring if enabled) |
| **deploy-circleci** | `./scripts/setup-cluster.sh deploy-circleci` | deploy-circleci.yml only | Add CircleCI to existing cluster |
| **deploy-monitoring** | `ansible-playbook -i inventory/ENV/hosts.ini playbooks/deploy-monitoring.yml` | deploy-monitoring.yml only | Add monitoring stack to existing cluster |
| **add-node** | `./scripts/setup-cluster.sh add-node` | kubespray/scale.yml [+ deploy-monitoring.yml] | Add nodes (+ monitoring update if enabled) |
| **add-node + CircleCI** | `./scripts/setup-cluster.sh add-node --enable-circleci` | kubespray/scale.yml + deploy-circleci.yml [+ deploy-monitoring.yml] | Add nodes + CircleCI (+ monitoring if enabled) |
| **remove-node** | `./scripts/setup-cluster.sh remove-node` | kubespray/remove-node.yml | Remove nodes |
| **upgrade-cluster** | `./scripts/setup-cluster.sh upgrade-cluster` | kubespray/upgrade-cluster.yml | Upgrade cluster |
| **reset-cluster** | `./scripts/setup-cluster.sh reset-cluster` | kubespray/reset.yml | Complete cluster removal |

**Note**: `[+ deploy-monitoring.yml]` indicates automatic monitoring deployment when `kube_prometheus_stack_enabled: true` in `addons.yml`

## Inventory Structure (Kubespray Standard)

This project uses standard Kubespray inventory structure. Follow [Kubespray documentation](3rdparty/kubespray/docs/getting_started/getting-started.md) for inventory management:

```yaml
all:
  children:
    kube_control_plane:  # Control plane nodes
      hosts:
        master-01:
          ansible_host: 192.168.1.10
    
    kube_node:          # All cluster nodes (masters + workers)
      hosts:
        master-01:
          ansible_host: 192.168.1.10
        worker-01:
          ansible_host: 192.168.1.11
    
    etcd:               # etcd cluster nodes
      hosts:
        master-01:
          ansible_host: 192.168.1.10
    
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
```

## Node Management (Kubespray Way)

### Adding Nodes

```bash
# 1. Add new node to inventory file
vim inventory/production/hosts.ini

# 2. Run scale playbook
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