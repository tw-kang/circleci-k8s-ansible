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

## Documentation

- [Installation Guide](docs/INSTALLATION.md) - Installation and basic deployment
- [Configuration Guide](docs/CONFIGURATION.md) - Advanced configuration and settings
- [Operations Guide](docs/OPERATIONS.md) - Security, maintenance, and troubleshooting

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
3. **All playbooks** are wrappers around standard Kubespray playbooks

## Deployment Modes

| Mode | Script Command | Underlying Playbook | Description |
|------|----------------|-------------------|-------------|
| **cluster-only** | `./scripts/setup-cluster.sh cluster-only` | kubespray/cluster.yml | Deploy Kubernetes cluster only |
| **cluster-only + CircleCI** | `./scripts/setup-cluster.sh cluster-only --enable-circleci` | kubespray/cluster.yml + deploy-circleci.yml | Deploy K8s + CircleCI |
| **deploy-circleci** | `./scripts/setup-cluster.sh deploy-circleci` | deploy-circleci.yml only | Add CircleCI to existing cluster |
| **add-node** | `./scripts/setup-cluster.sh add-node` | kubespray/scale.yml | Add nodes (update inventory first) |
| **add-node + CircleCI** | `./scripts/setup-cluster.sh add-node --enable-circleci` | kubespray/scale.yml + deploy-circleci.yml | Add nodes + CircleCI |
| **remove-node** | `./scripts/setup-cluster.sh remove-node` | kubespray/remove-node.yml | Remove nodes |
| **upgrade-cluster** | `./scripts/setup-cluster.sh upgrade-cluster` | kubespray/upgrade-cluster.yml | Upgrade cluster |
| **reset-cluster** | `./scripts/setup-cluster.sh reset-cluster` | kubespray/reset.yml | Complete cluster removal |

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

### Upgrading Cluster

```bash
# 1. Update kube_version in group_vars/k8s_cluster/k8s-cluster.yml
# 2. Run upgrade playbook
./scripts/setup-cluster.sh upgrade-cluster
```

## Project Structure

```
circleci-k8s-ansible/
├── 3rdparty/kubespray/          # Kubespray submodule (DO NOT MODIFY)
├── playbooks/                   # Wrapper playbooks
│   ├── cluster-only.yml         # Kubernetes only (wraps kubespray/cluster.yml)
│   ├── deploy-circleci.yml      # CircleCI deployment only
│   ├── add-node.yml            # Node addition (wraps kubespray/scale.yml)
│   ├── remove-node.yml         # Node removal (wraps kubespray/remove-node.yml)
│   ├── upgrade-cluster.yml     # Cluster upgrade (wraps kubespray/upgrade-cluster.yml)
│   └── reset-cluster.yml       # Cluster reset (wraps kubespray/reset.yml)
├── inventory/                   # Inventory configurations
│   ├── production/hosts.ini     # Production inventory
│   └── staging/hosts.ini        # Staging inventory
├── group_vars/                  # Global variable configurations
│   ├── all/
│   │   └── kubespray.yml       # Kubespray bridge (DO NOT MODIFY)
│   └── k8s_cluster/            # Kubespray cluster config (DO NOT MODIFY)
├── roles/                      # Custom Ansible roles
│   └── circleci/               # CircleCI runner role
├── scripts/                    # Utility scripts
│   ├── setup-cluster.sh        # Main deployment script
│   └── rollback.sh             # Cluster reset script
└── docs/                       # Documentation
```

## Configuration

### CircleCI Runner Configuration (Optional)

Create and edit `inventory/production/group_vars/circleci/runner.yml`:

```yaml
runner:
  namespace: "circleci"
  resource_class: "namespace/resource-class"
  token: "{{ vault_circleci_token }}"
  image: "cimg/base:stable"
  replicas: 2
  
  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "1Gi"
```

Encrypt the token using ansible-vault:

```bash
# Add to inventory/production/group_vars/all/vault.yml
ansible-vault edit inventory/production/group_vars/all/vault.yml
# Add: vault_circleci_token: "YOUR_CIRCLECI_RUNNER_TOKEN"
```

### Kubernetes Configuration

Main Kubernetes settings in `group_vars/k8s_cluster/k8s-cluster.yml`:

```yaml
kube_version: "v1.31.9"
kube_network_plugin: calico
container_manager: containerd
loadbalancer_apiserver_port: 6443
```

## Script Usage Examples

### Basic Operations

```bash
# Deploy basic cluster
./scripts/setup-cluster.sh cluster-only

# Deploy with CircleCI
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password

# Use staging environment
./scripts/setup-cluster.sh cluster-only -i inventory/staging/hosts.ini

# Dry run with verbose output
./scripts/setup-cluster.sh cluster-only --dry-run -vv

# Deploy specific components only
./scripts/setup-cluster.sh cluster-only --tags "etcd,kubernetes/master"
```

### Node Management

```bash
# Add nodes (update inventory first)
./scripts/setup-cluster.sh add-node

# Remove specific nodes
./scripts/setup-cluster.sh remove-node --extra-vars "node=worker-1,worker-2"

# Upgrade cluster (update kube_version first)
./scripts/setup-cluster.sh upgrade-cluster
```

### CircleCI Operations

```bash
# Deploy CircleCI to existing cluster
./scripts/setup-cluster.sh deploy-circleci --enable-circleci --vault-password .vault-password

# Deploy cluster with CircleCI in one command
./scripts/setup-cluster.sh cluster-only --enable-circleci --vault-password .vault-password
```

### Cluster Reset

```bash
# Safe reset with confirmations
./scripts/rollback.sh

# Force reset (dangerous)
./scripts/rollback.sh --force

# Reset with backup
./scripts/rollback.sh --backup /path/to/backup/dir

# Dry run reset
./scripts/rollback.sh --dry-run
```

## Environment Variables

Set these variables for your specific environment:

```bash
# Ansible configuration
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_STDOUT_CALLBACK=yaml

# SSH configuration (if needed)
export ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s"
```

## Security Considerations

1. **Use encrypted inventory variables** for sensitive data with ansible-vault
2. **Configure firewall rules** on target nodes for Kubernetes services
3. **Use SSH key authentication** instead of passwords
4. **Regularly update** kubespray submodule for security patches
5. **Review RBAC settings** for CircleCI service accounts

## Troubleshooting

### Common Issues

1. **SSH connectivity issues**: Verify SSH keys and target node accessibility
2. **Inventory parsing errors**: Check YAML syntax in inventory files
3. **Kubespray submodule missing**: Run `git submodule update --init --recursive`
4. **CircleCI deployment failures**: Verify token encryption and network policies

### Useful Commands

```bash
# Test Ansible connectivity
ansible all -i inventory/production/hosts.ini -m ping

# Check kubespray variables
ansible-inventory -i inventory/production/hosts.ini --list

# Verify cluster status
kubectl get nodes -o wide
kubectl get pods -A

# Check CircleCI runners
kubectl get pods -n circleci
kubectl logs -n circleci -l app.kubernetes.io/name=container-agent
```

## Contributing

1. Follow existing code style and structure
2. Test changes on staging environment first
3. Update documentation for any new features
4. Do not modify files in 3rdparty/kubespray/ directory
5. Use English for all code comments and documentation

## License

This project follows the same license as Kubespray. See [Kubespray License](3rdparty/kubespray/LICENSE) for details.