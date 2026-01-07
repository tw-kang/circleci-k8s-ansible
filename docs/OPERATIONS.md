# Operations Guide

Comprehensive cluster operations, maintenance, and troubleshooting for Kubernetes clusters with integrated monitoring stack and optional CircleCI runners.

## Cluster Management Commands

All cluster operations are performed using ansible playbooks directly. The playbooks provide comprehensive cluster lifecycle management with kubespray integration and automatic monitoring deployment.

### Basic Command Structure

```bash
# General syntax
ansible-playbook -i INVENTORY PLAYBOOK [OPTIONS]

# Common options:
# -i FILE                 Specify inventory file
# --vault-password-file   Vault password file for encrypted variables
# --extra-vars VARS       Additional variables (use circleci_enabled=true for CircleCI)
# --check                 Show what would be done without executing (dry run)
# -v                      Enable verbose output
# --tags TAGS             Run only tasks with specified tags
```

### Available Modes

| Playbook | Description | Underlying Playbook |
|----------|-------------|-------------------|
| `cluster-only.yml` | Deploy Kubernetes cluster only | `cluster-only.yml` (wraps `3rdparty/kubespray/cluster.yml`) |
| `deploy-monitoring.yml` | Deploy monitoring stack to existing cluster | `deploy-monitoring.yml` |
| `deploy-circleci.yml` | Add CircleCI to existing cluster | `deploy-circleci.yml` |
| `add-node.yml` | Add nodes to existing cluster | `add-node.yml` (wraps `3rdparty/kubespray/scale.yml`) |
| `remove-node.yml` | Remove nodes from cluster | `remove-node.yml` (wraps `3rdparty/kubespray/remove-node.yml`) |
| `upgrade-cluster.yml` | Upgrade cluster version | `upgrade-cluster.yml` (wraps `3rdparty/kubespray/upgrade-cluster.yml`) |
| `reset-cluster.yml` | Completely destroy cluster | `reset-cluster.yml` (wraps `3rdparty/kubespray/reset.yml`) |

## Node Management

### Adding Nodes

**Prerequisites**: Prepare new nodes according to [Installation Guide](../docs/INSTALLATION.md) before adding to cluster.

```bash
# 1. Prepare new node (execute on target node)
# Follow "Part 2: Target Nodes Preparation" in Installation Guide:
# - Python 3.10+ installation
# - Firewall disable  
# - Storage configuration
# - DNS configuration

# 2. Add node to inventory
vim inventory/production/hosts.ini

# 3. Deploy to new node
ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml

# 4. Update monitoring for new node
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# 5. Add node with CircleCI
ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml --vault-password-file .vault-password --extra-vars "circleci_enabled=true"

# 6. Verify node joined
inventory/production/artifacts/kubectl.sh get nodes

# 7. Check monitoring pods
inventory/production/artifacts/kubectl.sh get pods -n monitoring
```

### Removing Nodes

```bash
# 1. Drain node gracefully
inventory/production/artifacts/kubectl.sh drain node-name --ignore-daemonsets --delete-emptydir-data

# 2. Remove from cluster
ansible-playbook -i inventory/production/hosts.ini playbooks/remove-node.yml --extra-vars "node=node-name"

# 3. Remove multiple nodes
ansible-playbook -i inventory/production/hosts.ini playbooks/remove-node.yml --extra-vars "node=worker-1,worker-2"

# 4. Remove from inventory after successful removal
vim inventory/production/hosts.ini
```

### Upgrading Cluster

```bash
# 1. Update Kubernetes version in configuration
vim inventory/production/group_vars/all/kubespray.yml
# Change: kube_version: "v1.31.10"

# 2. Run upgrade playbook
ansible-playbook -i inventory/production/hosts.ini playbooks/upgrade-cluster.yml

# 3. Verify upgrade
inventory/production/artifacts/kubectl.sh version
inventory/production/artifacts/kubectl.sh get nodes
```

### Complete Cluster Reset

```bash
# WARNING: This will destroy the entire cluster and all data
ansible-playbook -i inventory/production/hosts.ini playbooks/reset-cluster.yml

# Confirm destruction when prompted
# All data will be permanently lost
```

## kubectl Access and Management

### Using Kubespray Artifacts

After deployment, kubespray creates kubectl artifacts in `inventory/{environment}/artifacts/`:

```bash
# Direct usage via kubectl.sh helper script
inventory/production/artifacts/kubectl.sh get nodes
inventory/production/artifacts/kubectl.sh get pods -A
inventory/production/artifacts/kubectl.sh cluster-info

# Check cluster status
inventory/production/artifacts/kubectl.sh get nodes -o wide
inventory/production/artifacts/kubectl.sh top nodes
```

### Standard kubectl Setup

```bash
# Copy kubectl to standard location
cp inventory/production/artifacts/kubectl /usr/local/bin/kubectl
cp inventory/production/artifacts/admin.conf ~/.kube/config

# Verify standard kubectl works
kubectl get nodes
kubectl get pods -A
```

## DNS Troubleshooting

### Current DNS Configuration

This project uses `resolvconf_mode: none` in `inventory/{env}/group_vars/k8s_cluster/k8s-cluster.yml`, requiring manual DNS management via NetworkManager.

### Common DNS Issues

**1. External DNS resolution fails:**
```bash
# Check system DNS configuration
cat /etc/resolv.conf

# Test external DNS resolution
nslookup google.com
ping 8.8.8.8

# Reconfigure DNS if needed (execute on each node)
nmcli connection modify "Wired connection 1" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes
nmcli connection up "Wired connection 1"
```

**2. Kubernetes service DNS fails:**
```bash
# Check cluster DNS services
inventory/production/artifacts/kubectl.sh get svc -n kube-system coredns
inventory/production/artifacts/kubectl.sh get pods -n kube-system -l k8s-app=kube-dns
inventory/production/artifacts/kubectl.sh logs -n kube-system -l k8s-app=kube-dns

# Test DNS from within cluster
inventory/production/artifacts/kubectl.sh run dns-test --image=busybox --rm -it -- \
  nslookup kubernetes.default.svc.cluster.local
```

**3. NodeLocal DNS cache issues:**
```bash
# Check NodeLocal DNS pods
inventory/production/artifacts/kubectl.sh get pods -n kube-system -l k8s-app=node-local-dns
inventory/production/artifacts/kubectl.sh logs -n kube-system -l k8s-app=node-local-dns

# Test NodeLocal DNS directly (from node)
dig @169.254.25.10 kubernetes.default.svc.cluster.local
```

**4. NetworkManager conflicts:**
```bash
# Check NetworkManager status (execute on each node)
systemctl status NetworkManager
nmcli device show | grep DNS

# Force static DNS configuration
nmcli connection modify "Wired connection 1" ipv4.ignore-auto-dns yes
```

### DNS Diagnostic Commands

```bash
# System-level DNS checks (execute on nodes)
cat /etc/resolv.conf
systemctl status NetworkManager
nmcli connection show

# Network connectivity tests
ping 164.124.101.2
telnet 164.124.101.2 53

# Kubernetes DNS checks
inventory/production/artifacts/kubectl.sh get configmap -n kube-system coredns -o yaml
inventory/production/artifacts/kubectl.sh describe pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution from pod
inventory/production/artifacts/kubectl.sh run dns-debug --image=busybox --rm -it -- sh
# Inside pod: nslookup kubernetes.default.svc.cluster.local
```

## CircleCI Operations

### Managing CircleCI Runners

```bash
# Check runner deployment status
inventory/production/artifacts/kubectl.sh get pods -n circleci
inventory/production/artifacts/kubectl.sh logs -n circleci -l app.kubernetes.io/name=container-agent

# Scale runners
inventory/production/artifacts/kubectl.sh scale deployment container-agent -n circleci --replicas=5

# Restart runners
inventory/production/artifacts/kubectl.sh rollout restart deployment/container-agent -n circleci

# Check runner resource usage
inventory/production/artifacts/kubectl.sh top pods -n circleci

# View runner configuration
inventory/production/artifacts/kubectl.sh get deployment container-agent -n circleci -o yaml
```

### CircleCI Deployment and Updates

```bash
# Initial CircleCI deployment
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-circleci.yml --vault-password-file .vault-password

# Update CircleCI configuration
ansible-vault edit inventory/production/group_vars/all/vault.yml
vim inventory/production/group_vars/circleci/runner.yml

# Redeploy CircleCI with changes
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-circleci.yml --vault-password-file .vault-password

# Deploy CircleCI to staging environment
ansible-playbook -i inventory/staging/hosts.ini playbooks/deploy-circleci.yml --vault-password-file .vault-password
```

### CircleCI Troubleshooting

```bash
# Check runner pod logs
inventory/production/artifacts/kubectl.sh logs -n circleci deployment/container-agent

# Check events in CircleCI namespace
inventory/production/artifacts/kubectl.sh get events -n circleci

# Verify runner configuration
inventory/production/artifacts/kubectl.sh describe deployment -n circleci container-agent

# Check resource constraints
inventory/production/artifacts/kubectl.sh describe nodes | grep -A 5 "Allocated resources"
```

## Monitoring Operations

### Managing Monitoring Stack

#### Separate Deployment (Required)

Monitoring must be deployed separately after cluster operations:

```bash
# Deploy cluster first
ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml

# Then deploy monitoring
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# For node additions, update monitoring after adding nodes
ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# Verify monitoring deployment
inventory/production/artifacts/kubectl.sh get pods -n monitoring
```

#### Manual Deployment

```bash
# Deploy monitoring stack to existing cluster (required after cluster installation)
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# Deploy to staging environment
ansible-playbook -i inventory/staging/hosts.ini playbooks/deploy-monitoring.yml

# Check deployment status
inventory/production/artifacts/kubectl.sh get pods -n monitoring
inventory/production/artifacts/kubectl.sh get services -n monitoring
inventory/production/artifacts/kubectl.sh get pvc -n monitoring
```

#### Accessing Monitoring Services

**Via NodePort (default configuration)**:

```bash
# Get node IPs
inventory/production/artifacts/kubectl.sh get nodes -o wide

# Check configured NodePort values
grep -A 10 "nodePort" inventory/production/group_vars/k8s_cluster/addons.yml

# Access services (default ports from configuration):
# Grafana: http://NODE_IP:32000 (admin/admin123!@#)
# Prometheus: http://NODE_IP:32001
# AlertManager: http://NODE_IP:32002
```

**Via Port Forward**:

```bash
# Grafana
inventory/production/artifacts/kubectl.sh port-forward -n monitoring service/kube-prometheus-stack-grafana 3000:80

# Prometheus
inventory/production/artifacts/kubectl.sh port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090

# AlertManager
inventory/production/artifacts/kubectl.sh port-forward -n monitoring service/kube-prometheus-stack-alertmanager 9093:9093
```

### Monitoring Configuration Updates

```bash
# Update monitoring configuration
vim inventory/production/group_vars/k8s_cluster/addons.yml

# Apply monitoring changes
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# Restart monitoring components
inventory/production/artifacts/kubectl.sh rollout restart deployment -n monitoring kube-prometheus-stack-grafana
inventory/production/artifacts/kubectl.sh rollout restart statefulset -n monitoring prometheus-kube-prometheus-stack-prometheus
```

### Monitoring Troubleshooting

**1. Monitoring pods not starting:**
```bash
# Check pod status and events
inventory/production/artifacts/kubectl.sh get pods -n monitoring
inventory/production/artifacts/kubectl.sh describe pods -n monitoring

# Check resource availability on master nodes
inventory/production/artifacts/kubectl.sh top nodes
inventory/production/artifacts/kubectl.sh describe nodes | grep -A 10 "master"

# Check persistent volume claims
inventory/production/artifacts/kubectl.sh get pvc -n monitoring
inventory/production/artifacts/kubectl.sh describe pvc -n monitoring
```

**2. Grafana login issues:**
```bash
# Check admin password configuration
inventory/production/artifacts/kubectl.sh get secret -n monitoring kube-prometheus-stack-grafana -o yaml

# Reset admin password
inventory/production/artifacts/kubectl.sh patch secret -n monitoring kube-prometheus-stack-grafana \
  -p '{"data":{"admin-password":"'$(echo -n "newpassword" | base64)'"}}'
inventory/production/artifacts/kubectl.sh rollout restart deployment -n monitoring kube-prometheus-stack-grafana
```

**3. Prometheus data collection issues:**
```bash
# Check Prometheus targets via port-forward
inventory/production/artifacts/kubectl.sh port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090 &
# Access http://localhost:9090/targets

# Check ServiceMonitor resources
inventory/production/artifacts/kubectl.sh get servicemonitor -n monitoring
inventory/production/artifacts/kubectl.sh describe servicemonitor -n monitoring

# Check Prometheus logs
inventory/production/artifacts/kubectl.sh logs -n monitoring statefulset/prometheus-kube-prometheus-stack-prometheus
```

**4. Resource management:**
```bash
# Monitor resource usage
inventory/production/artifacts/kubectl.sh top nodes
inventory/production/artifacts/kubectl.sh top pods -n monitoring

# Check resource requests/limits
inventory/production/artifacts/kubectl.sh describe deployment -n monitoring kube-prometheus-stack-grafana

# Adjust resource limits in configuration
vim inventory/production/group_vars/k8s_cluster/addons.yml
# Update kube_prometheus_stack_values.prometheus.prometheusSpec.resources
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml
```

## Security Operations

### Certificate Management

```bash
# Check certificate expiration (execute on master nodes)
kubeadm certs check-expiration

# Renew certificates
kubeadm certs renew all
systemctl restart kubelet

# Verify certificate renewal
kubeadm certs check-expiration
```

### Vault Operations

```bash
# Edit encrypted vault files
ansible-vault edit inventory/production/group_vars/all/vault.yml

# Create new vault file
ansible-vault create inventory/staging/group_vars/all/vault.yml

# Change vault password
ansible-vault rekey inventory/production/group_vars/all/vault.yml

# View vault content (decrypt)
ansible-vault view inventory/production/group_vars/all/vault.yml
```

### Backup Operations

**etcd backup (execute on master nodes):**
```bash
# Create etcd snapshot
ETCDCTL_API=3 etcdctl snapshot save snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key

# Verify snapshot
ETCDCTL_API=3 etcdctl snapshot status snapshot.db
```

**Configuration backup:**
```bash
# Backup important configuration files
tar -czf k8s-config-backup-$(date +%Y%m%d).tar.gz \
  /etc/kubernetes/ \
  inventory/production/group_vars/ \
  inventory/production/hosts.ini \
  inventory/production/artifacts/

# Backup inventory and artifacts
tar -czf inventory-backup-$(date +%Y%m%d).tar.gz \
  inventory/
```

## Log Management and Diagnostics

### System Logs

```bash
# View kubelet logs (execute on nodes)
journalctl -u kubelet -f

# View container runtime logs
journalctl -u containerd -f

# Check system logs
journalctl -xe

# View specific time range
journalctl -u kubelet --since "1 hour ago"
```

### Kubernetes Component Logs

```bash
# Control plane component logs
inventory/production/artifacts/kubectl.sh logs -n kube-system -l component=kube-apiserver
inventory/production/artifacts/kubectl.sh logs -n kube-system -l component=kube-controller-manager
inventory/production/artifacts/kubectl.sh logs -n kube-system -l component=kube-scheduler

# Check CNI logs
inventory/production/artifacts/kubectl.sh logs -n kube-system -l k8s-app=calico-node

# View recent events
inventory/production/artifacts/kubectl.sh get events --sort-by='.metadata.creationTimestamp'
```

### Application Logs

```bash
# CircleCI logs
inventory/production/artifacts/kubectl.sh logs -n circleci -l app.kubernetes.io/name=container-agent

# Monitoring stack logs
inventory/production/artifacts/kubectl.sh logs -n monitoring -l app.kubernetes.io/name=grafana
inventory/production/artifacts/kubectl.sh logs -n monitoring -l app.kubernetes.io/name=prometheus

# System addon logs
inventory/production/artifacts/kubectl.sh logs -n kube-system -l k8s-app=kube-dns
```

## Troubleshooting Common Issues

### Cluster Connectivity Issues

**1. Node not ready:**
```bash
# Check node status
inventory/production/artifacts/kubectl.sh get nodes
inventory/production/artifacts/kubectl.sh describe node NODE_NAME

# Check kubelet status (execute on the problematic node)
systemctl status kubelet
journalctl -u kubelet -f
```

**2. Pod networking issues:**
```bash
# Check CNI pods
inventory/production/artifacts/kubectl.sh get pods -n kube-system -l k8s-app=calico-node

# Test pod-to-pod connectivity
inventory/production/artifacts/kubectl.sh run test-pod --image=busybox --rm -it -- ping POD_IP

# Check network policies
inventory/production/artifacts/kubectl.sh get networkpolicies -A
```

**3. Service discovery problems:**
```bash
# Check DNS resolution within cluster
inventory/production/artifacts/kubectl.sh run dns-test --image=busybox --rm -it -- nslookup kubernetes.default

# Check kube-proxy status
inventory/production/artifacts/kubectl.sh get pods -n kube-system -l k8s-app=kube-proxy
inventory/production/artifacts/kubectl.sh logs -n kube-system -l k8s-app=kube-proxy
```

### Performance Issues

**1. High resource usage:**
```bash
# Check resource consumption
inventory/production/artifacts/kubectl.sh top nodes
inventory/production/artifacts/kubectl.sh top pods -A

# Identify resource-heavy pods
inventory/production/artifacts/kubectl.sh get pods -A --sort-by='.status.containerStatuses[0].restartCount'

# Check resource limits and requests
inventory/production/artifacts/kubectl.sh describe nodes | grep -A 10 "Allocated resources"
```

**2. Storage issues:**
```bash
# Check disk usage on nodes (execute on each node)
df -h

# Verify bind mounts for containerd and kubelet are active
mount | grep -E "(containerd|kubelet)"
df -h /var/lib/containerd /var/lib/kubelet

# If bind mounts are missing, reconfigure according to Installation Guide
# Refer to: Installation Guide -> Part 2: Target Nodes Preparation -> Storage Configuration

# Check Kubernetes persistent volumes
inventory/production/artifacts/kubectl.sh get pv,pvc -A

# Check storage class
inventory/production/artifacts/kubectl.sh get storageclass
```

### Recovery Procedures

**1. Restart cluster services:**
```bash
# Restart kubelet on all nodes
ansible all -i inventory/production/hosts.ini -m systemd -a "name=kubelet state=restarted"

# Restart containerd
ansible all -i inventory/production/hosts.ini -m systemd -a "name=containerd state=restarted"

# Restart specific deployments
inventory/production/artifacts/kubectl.sh rollout restart deployment -n kube-system coredns
```

**2. Rollback operations:**
```bash
# Use rollback playbook if available
ansible-playbook -i inventory/production/hosts.ini playbooks/reset-cluster.yml

# Manual version rollback
vim inventory/production/group_vars/all/kubespray.yml
# Change kube_version back to previous stable version
ansible-playbook -i inventory/production/hosts.ini playbooks/upgrade-cluster.yml
```

**3. Emergency cluster reset (DESTRUCTIVE):**
```bash
# WARNING: This will destroy the entire cluster and all data
ansible-playbook -i inventory/production/hosts.ini playbooks/reset-cluster.yml

# Confirm destruction when prompted
# All cluster data, configurations, and workloads will be permanently lost
```

## Script Advanced Usage

### Dry Run and Debugging

```bash
# Preview changes without executing (dry run)
ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml --check

# Verbose output for debugging
ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml -v

# Run specific tags only
ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml --tags verification

# Combine options
ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml --check -v --extra-vars "circleci_enabled=true"
```

### Environment Management

```bash
# Use different inventory environments
ansible-playbook -i inventory/staging/hosts.ini playbooks/cluster-only.yml

# Environment-specific CircleCI deployment
ansible-playbook -i inventory/staging/hosts.ini playbooks/deploy-circleci.yml --vault-password-file .vault-password

# Cross-environment operations
ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml -limit=NODE_NAME
```

### Custom Variables

```bash
# Pass additional variables
ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml --extra-vars "cluster_name=custom-cluster"

# Override specific settings
ansible-playbook -i inventory/production/hosts.ini playbooks/upgrade-cluster.yml --extra-vars "kube_version=v1.31.10"

# Multiple variables
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-circleci.yml --extra-vars "runner_replicas=3,runner_resource_class=large,circleci_enabled=true"
```

## Maintenance Schedule

### Regular Maintenance Tasks

**Daily:**
- Monitor cluster health via Grafana dashboards (automatically deployed)
- Check resource usage and capacity
- Review application logs

**Weekly:**
- Review security alerts
- Check certificate expiration status
- Update monitoring configurations if needed

**Monthly:**
- Plan Kubernetes version upgrades
- Review and update CircleCI runner configurations
- Backup etcd and configuration files

**Quarterly:**
- Major version upgrades
- Security audit and updates
- Disaster recovery testing

For additional troubleshooting and operational guidance, refer to:
- [Kubespray documentation](https://kubespray.io/)
- [Kubernetes troubleshooting guide](https://kubernetes.io/docs/tasks/debug-application-cluster/)