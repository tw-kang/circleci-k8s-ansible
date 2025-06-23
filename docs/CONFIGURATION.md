# Configuration Guide

This guide covers the kubespray configuration files copied from the submodule and the specific modifications made for this project.

## Kubespray Configuration Files

This project uses kubespray configuration files copied from `3rdparty/kubespray/inventory/sample/group_vars/` with specific modifications.

### Files Copied from Kubespray

The following files were copied from kubespray sample inventory and modified:

1. `inventory/{env}/group_vars/all/kubespray.yml` ← `3rdparty/kubespray/inventory/sample/group_vars/all/all.yml`
2. `inventory/{env}/group_vars/k8s_cluster/k8s-cluster.yml` ← `3rdparty/kubespray/inventory/sample/group_vars/k8s_cluster/k8s-cluster.yml`
3. `inventory/{env}/group_vars/k8s_cluster/addons.yml` ← `3rdparty/kubespray/inventory/sample/group_vars/k8s_cluster/addons.yml`
4. `inventory/{env}/group_vars/k8s_cluster/kube_control_plane.yml` ← `3rdparty/kubespray/inventory/sample/group_vars/k8s_cluster/kube_control_plane.yml`

Where `{env}` is `staging` or `production`.

### Project-Specific Modifications

#### 1. `inventory/{env}/group_vars/all/kubespray.yml`
**Added:**
```yaml
# Kubernetes version
kube_version: "1.31.9"
```
**Reason:** Pin Kubernetes version to ensure consistent deployments across environments.

#### 2. `inventory/{env}/group_vars/k8s_cluster/addons.yml`  
**Changed:**
```yaml
helm_enabled: true          # Default: false
metrics_server_enabled: true   # Default: false
```
**Reasons:**
- `helm_enabled: true` - Required for CircleCI runner deployment via Helm charts
- `metrics_server_enabled: true` - Enable cluster resource monitoring

#### 3. `inventory/{env}/group_vars/k8s_cluster/k8s-cluster.yml`
**Changed:**
```yaml
resolvconf_mode: none       # Default: host_resolvconf
```
**Added:**
```yaml
# Allow scheduling on control plane nodes
kube_control_plane_schedulable: true
```
**Reasons:**
- `resolvconf_mode: none` - Prevent kubespray from managing DNS, allowing manual DNS configuration via NetworkManager
- `kube_control_plane_schedulable: true` - Allow workloads to run on control plane nodes for resource efficiency

#### 4. `inventory/{env}/group_vars/k8s_cluster/kube_control_plane.yml`
**Changed (High-spec server optimization for 64 vCPU, 128GB RAM):**
```yaml
# Kubernetes component reservations (20% of total resources)
kube_memory_reserved: 26214Mi      # Default: 512Mi
kube_cpu_reserved: 12800m          # Default: 200m
kube_ephemeral_storage_reserved: 50Gi
kube_pid_reserved: "4000"          # Default: "1000"

# System reservations (10% of total resources)  
system_memory_reserved: 13107Mi    # Default: 256Mi
system_cpu_reserved: 6400m         # Default: 250m
system_ephemeral_storage_reserved: 20Gi
system_pid_reserved: "2000"        # Default: "1000"
```
**Reason:** Optimize resource allocation for high-performance servers with 64 vCPU and 128GB RAM, reserving appropriate resources for Kubernetes components and system processes.

## DNS Configuration

Since `resolvconf_mode: none` is set, DNS must be configured manually on all nodes:

```bash
# Configure DNS via NetworkManager
nmcli connection modify "Wired connection 2" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes
nmcli connection up "Wired connection 2"

# Verify configuration
cat /etc/resolv.conf
```

## CircleCI Configuration

Create `inventory/production/group_vars/circleci/runner.yml` for CircleCI runner deployment:

```yaml
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
```

Store the CircleCI token in vault:
```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml
# Add: vault_circleci_token: "YOUR_CIRCLECI_RUNNER_TOKEN"
```

## Environment-Specific Overrides

Override settings per environment in `inventory/{env}/group_vars/` without modifying the base kubespray files.

Example additional configuration in `inventory/production/group_vars/all/vars.yml`:
```yaml
# Production-specific settings
cluster_name: "production-cluster"
ntp_servers:
  - "pool.ntp.org"
``` 