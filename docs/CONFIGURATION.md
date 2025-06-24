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
# Kubernetes component reservations (10% of total resources)
kube_memory_reserved: 13107Mi      # Default: 512Mi (~12.8GB)
kube_cpu_reserved: 6400m           # Default: 200m (6.4 vCPU)
kube_ephemeral_storage_reserved: 25Gi
kube_pid_reserved: "2000"          # Default: "1000"

# System reservations (5% of total resources)  
system_memory_reserved: 6554Mi     # Default: 256Mi (~6.4GB)
system_cpu_reserved: 3200m         # Default: 250m (3.2 vCPU)
system_ephemeral_storage_reserved: 10Gi
system_pid_reserved: "1000"        # Default: "1000"
```
**Reason:** Optimized resource allocation for 192.168.2.8 (64 vCPU, 128GB RAM, 3.6T SSD), providing 85% of resources for workloads while ensuring system stability.

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

## Monitoring Configuration

The monitoring stack uses kube-prometheus-stack, which includes Prometheus, Grafana, and AlertManager.

### Automatic Deployment

When `kube_prometheus_stack_enabled: true` is set, monitoring is automatically deployed during:
- `./scripts/setup-cluster.sh cluster-only`
- `./scripts/setup-cluster.sh add-node`

### Basic Configuration

Monitoring is configured in `inventory/{env}/group_vars/k8s_cluster/addons.yml`:

```yaml
# Enable automatic monitoring deployment
kube_prometheus_stack_enabled: true
kube_prometheus_stack_namespace: monitoring
kube_prometheus_stack_chart_version: "61.3.2"

# Basic configuration with NodePort access and resource limits
kube_prometheus_stack_values:
  grafana:
    adminPassword: "admin123!@#"
    persistence:
      enabled: false
      size: 5Gi
    service:
      type: NodePort
      nodePort: 32000
    resources:
      requests:
        cpu: 200m
        memory: 300Mi
      limits:
        cpu: 500m
        memory: 1Gi
  
  prometheus:
    service:
      type: NodePort
      nodePort: 32001
    prometheusSpec:
      resources:
        requests:
          cpu: 2
          memory: 4Gi
        limits:
          cpu: 4
          memory: 8Gi
  
  alertmanager:
    service:
      type: NodePort
      nodePort: 32002
    alertmanagerSpec:
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 1
          memory: 2Gi
  
  # Additional component resource settings
  kubeStateMetrics:
    resources:
      requests:
        cpu: 100m
        memory: 200Mi
      limits:
        cpu: 200m
        memory: 400Mi
  
  nodeExporter:
    resources:
      requests:
        cpu: 50m
        memory: 100Mi
      limits:
        cpu: 100m
        memory: 200Mi
```

**Important**: NodePort values and resource limits are dynamically read from this configuration by both `deploy-monitoring.yml` and `setup-cluster.sh`.

### Advanced Configuration

For production environments, customize storage, resources, and retention:

```yaml
kube_prometheus_stack_values:
  # Grafana with persistent storage
  grafana:
    adminPassword: "secure-password"
    persistence:
      enabled: true
      size: 10Gi
      storageClassName: "local-path"
    service:
      type: NodePort
      nodePort: 32000
  
  # Prometheus with custom retention and storage
  prometheus:
    service:
      type: NodePort
      nodePort: 32001
    prometheusSpec:
      retention: 30d
      storageSpec:
        volumeClaimTemplate:
          spec:
            accessModes: ["ReadWriteOnce"]
            storageClassName: "local-path"
            resources:
              requests:
                storage: 50Gi
      resources:
        requests:
          memory: 2Gi
          cpu: 500m
        limits:
          memory: 4Gi
          cpu: 2000m
  
  # AlertManager with persistent storage
  alertmanager:
    service:
      type: NodePort
      nodePort: 32002
    alertmanagerSpec:
      storage:
        volumeClaimTemplate:
          spec:
            accessModes: ["ReadWriteOnce"]
            storageClassName: "local-path"
            resources:
              requests:
                storage: 10Gi
```

### Access Methods

**NodePort Access:**
- Grafana: `http://NODE_IP:32000`
- Prometheus: `http://NODE_IP:32001`
- AlertManager: `http://NODE_IP:32002`

**Port-Forward Access:**
```bash
# Grafana
kubectl port-forward -n monitoring service/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090

# AlertManager
kubectl port-forward -n monitoring service/kube-prometheus-stack-alertmanager 9093:9093
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