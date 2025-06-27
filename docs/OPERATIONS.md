# Operations Guide

Essential cluster operations and troubleshooting for Kubernetes clusters with CircleCI runners.

## Node Management

### Adding Nodes

```bash
# 1. Configure DNS on new node first
nmcli connection modify "Wired connection 1" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes
nmcli connection up "Wired connection 1"

# 2. Add node to inventory
vim inventory/production/hosts.ini

# 3. Deploy to new node (includes monitoring update if enabled)
./scripts/setup-cluster.sh add-node

# 4. Verify node joined
kubectl get nodes

# 5. Check monitoring pods if enabled
kubectl get pods -n monitoring
```

### Removing Nodes

```bash
# 1. Drain node
kubectl drain node-name --ignore-daemonsets --delete-emptydir-data

# 2. Remove from cluster
./scripts/setup-cluster.sh remove-node --extra-vars "node=node-name"

# 3. Remove from inventory
vim inventory/production/hosts.ini
```

### Upgrading Cluster

```bash
# 1. Update Kubernetes version in inventory/{env}/group_vars/all/kubespray.yml
kube_version: "v1.31.10"

# 2. Run upgrade playbook
./scripts/setup-cluster.sh upgrade-cluster

# 3. Verify upgrade
kubectl version
kubectl get nodes
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

# Reconfigure if needed
nmcli connection modify "Wired connection 1" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes
nmcli connection up "Wired connection 1"
```

**2. Kubernetes service DNS fails:**
```bash
# Check cluster DNS services
kubectl get svc -n kube-system coredns
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Test from within cluster
kubectl run dns-test --image=busybox --rm -it -- \
  nslookup kubernetes.default.svc.cluster.local
```

**3. NodeLocal DNS cache issues:**
```bash
# Check NodeLocal DNS pods
kubectl get pods -n kube-system -l k8s-app=node-local-dns
kubectl logs -n kube-system -l k8s-app=node-local-dns

# Test NodeLocal DNS directly
dig @169.254.25.10 kubernetes.default.svc.cluster.local
```

**4. NetworkManager conflicts:**
```bash
# Check NetworkManager status
systemctl status NetworkManager
nmcli device show | grep DNS

# Force static DNS configuration
nmcli connection modify "Wired connection 1" \
  ipv4.ignore-auto-dns yes
```

### DNS Diagnostic Commands

```bash
# System-level DNS checks
cat /etc/resolv.conf
systemctl status NetworkManager
nmcli connection show

# Network connectivity tests
ping 164.124.101.2
telnet 164.124.101.2 53

# Kubernetes DNS checks
kubectl get configmap -n kube-system coredns -o yaml
kubectl describe pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution from pod
kubectl run dns-debug --image=busybox --rm -it -- sh
# Inside pod: nslookup kubernetes.default.svc.cluster.local
```

## CircleCI Operations

### Managing CircleCI Runners

```bash
# Check runner status
kubectl get pods -n circleci
kubectl logs -n circleci -l app.kubernetes.io/name=container-agent

# Scale runners
kubectl scale deployment container-agent -n circleci --replicas=5

# Restart runners
kubectl rollout restart deployment/container-agent -n circleci

# Check runner resource usage
kubectl top pods -n circleci
```

### Updating CircleCI Configuration

```bash
# Edit runner configuration
ansible-vault edit inventory/production/group_vars/circleci/runner.yml

# Redeploy CircleCI with changes
./scripts/setup-cluster.sh deploy-circleci --enable-circleci --vault-password .vault-password
```

## Monitoring Operations

### Managing Monitoring Stack

#### Automatic Deployment

Monitoring is automatically deployed when `kube_prometheus_stack_enabled: true` in `inventory/{env}/group_vars/k8s_cluster/addons.yml`:

```bash
# Deploy cluster with automatic monitoring
./scripts/setup-cluster.sh cluster-only

# Add nodes with automatic monitoring update
./scripts/setup-cluster.sh add-node
```

#### Manual Deployment

```bash
# Deploy monitoring stack manually
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml

# Check deployment status
kubectl get pods -n monitoring
kubectl get services -n monitoring
kubectl get pvc -n monitoring
```

#### Accessing Monitoring Services

**Via NodePort (configured in `inventory/{env}/group_vars/k8s_cluster/addons.yml`):**
```bash
# Get node IPs
kubectl get nodes -o wide

# Check configured NodePort values from addons.yml
grep -A 50 "kube_prometheus_stack_values:" inventory/production/group_vars/k8s_cluster/addons.yml

# Access services (default ports from configuration):
# Grafana: http://NODE_IP:32000 (admin/admin123!@#)
# Prometheus: http://NODE_IP:32001  
# AlertManager: http://NODE_IP:32002
```

**Via Port Forward:**
```bash
# Grafana
kubectl port-forward -n monitoring service/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090

# AlertManager
kubectl port-forward -n monitoring service/kube-prometheus-stack-alertmanager 9093:9093
```

### Monitoring Troubleshooting

**1. Monitoring pods not starting:**
```bash
# Check pod status and events
kubectl get pods -n monitoring
kubectl describe pods -n monitoring

# Check resource availability
kubectl top nodes
kubectl describe nodes
```

**2. Grafana login issues:**
```bash
# Check admin password configuration
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o yaml

# Reset admin password if needed
kubectl patch secret -n monitoring kube-prometheus-stack-grafana \
  -p '{"data":{"admin-password":"'$(echo -n "newpassword" | base64)'"}}'
kubectl rollout restart deployment -n monitoring kube-prometheus-stack-grafana
```

**3. Prometheus data collection issues:**
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090
# Access http://localhost:9090/targets

# Check ServiceMonitor resources
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor -n monitoring
```

### Resource Management

**Monitor resource usage:**
```bash
# Cluster resource overview
kubectl top nodes
kubectl top pods -A

# Monitoring stack resource usage
kubectl top pods -n monitoring

# Check resource requests/limits
kubectl describe deployment -n monitoring kube-prometheus-stack-grafana
```

**Adjust resource limits:**
Edit `inventory/{env}/group_vars/k8s_cluster/addons.yml`:
```yaml
kube_prometheus_stack_values:
  prometheus:
    prometheusSpec:
      resources:
        requests:
          cpu: 4
          memory: 8Gi
        limits:
          cpu: 8
          memory: 16Gi
```

Then redeploy:
```bash
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml
```

## Security Operations

### Certificate Management

```bash
# Check certificate expiration
kubeadm certs check-expiration

# Renew certificates
kubeadm certs renew all
systemctl restart kubelet
```

### Backup Operations

**etcd backup:**
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
tar -czf k8s-config-backup.tar.gz \
  /etc/kubernetes/ \
  inventory/production/group_vars/ \
  inventory/production/hosts.ini
```

### Log Management

```bash
# View kubelet logs
journalctl -u kubelet -f

# View container runtime logs
journalctl -u containerd -f

# Check system logs
journalctl -xe

# Kubernetes component logs
kubectl logs -n kube-system -l component=kube-apiserver
kubectl logs -n kube-system -l component=kube-controller-manager
kubectl logs -n kube-system -l component=kube-scheduler
```

## Troubleshooting Common Issues

### Cluster Connectivity Issues

**1. Node not ready:**
```bash
# Check node status
kubectl get nodes
kubectl describe node NODE_NAME

# Check kubelet status
systemctl status kubelet
journalctl -u kubelet -f
```

**2. Pod networking issues:**
```bash
# Check CNI pods
kubectl get pods -n kube-system -l k8s-app=calico-node

# Test pod-to-pod connectivity
kubectl run test-pod --image=busybox --rm -it -- ping POD_IP
```

**3. Service discovery problems:**
```bash
# Check DNS resolution
kubectl run dns-test --image=busybox --rm -it -- nslookup kubernetes.default

# Check kube-proxy status
kubectl get pods -n kube-system -l k8s-app=kube-proxy
```

### Performance Issues

**1. High resource usage:**
```bash
# Check resource consumption
kubectl top nodes
kubectl top pods -A

# Identify resource-heavy pods
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount'
```

**2. Storage issues:**
```bash
# Check disk usage on nodes
df -h
kubectl get pv,pvc -A
```

### Recovery Procedures

**1. Complete cluster reset (DESTRUCTIVE):**
```bash
# WARNING: This will destroy the entire cluster
./scripts/setup-cluster.sh reset-cluster
```

**2. Restart cluster services:**
```bash
# Restart kubelet on all nodes
ansible all -i inventory/production/hosts.ini -m systemd -a "name=kubelet state=restarted"

# Restart containerd
ansible all -i inventory/production/hosts.ini -m systemd -a "name=containerd state=restarted"
```

**3. Rollback failed upgrades:**
```bash
# Use rollback script if available
./scripts/rollback.sh --target-version v1.31.9

# Or manually revert configuration
vim inventory/production/group_vars/all/kubespray.yml
# Change kube_version back to previous version
./scripts/setup-cluster.sh upgrade-cluster
```

For additional troubleshooting, refer to:
- [Kubespray documentation](https://kubespray.io/)
- [Kubernetes troubleshooting guide](https://kubernetes.io/docs/tasks/debug-application-cluster/)
- Project-specific logs in `validation-report.txt`