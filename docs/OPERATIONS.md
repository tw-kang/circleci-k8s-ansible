# Operations Guide

Essential cluster operations and troubleshooting for Kubernetes clusters with CircleCI runners.

## Node Management

### Adding Nodes

```bash
# 1. Configure DNS on new node first
nmcli connection modify "Wired connection 2" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes
nmcli connection up "Wired connection 2"

# 2. Add node to inventory
vim inventory/production/hosts.ini

# 3. Deploy to new node
./scripts/setup-cluster.sh add-node

# 4. Verify node joined
kubectl get nodes
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
# 1. Update Kubernetes version in group_vars/all/kubespray.yml
kube_version: "v1.31.10"

# 2. Run upgrade playbook
./scripts/setup-cluster.sh upgrade-cluster

# 3. Verify upgrade
kubectl version
kubectl get nodes
```

## DNS Troubleshooting

### Current DNS Configuration
This project uses `resolvconf_mode: none`, requiring manual DNS management via NetworkManager.

### Common DNS Issues

**1. External DNS resolution fails:**
```bash
# Check system DNS configuration
cat /etc/resolv.conf

# Test external DNS resolution
nslookup google.com
ping 8.8.8.8

# Reconfigure if needed
nmcli connection modify "Wired connection 2" \
  ipv4.dns "164.124.101.2 8.8.8.8 8.8.4.4" \
  ipv4.ignore-auto-dns yes
nmcli connection up "Wired connection 2"
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
nmcli connection modify "Wired connection 2" \
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

## Backup and Recovery

### etcd Backup

```bash
# Create etcd snapshot
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/ssl/etcd/ca.pem \
  --cert=/etc/kubernetes/ssl/etcd/member-$(hostname).pem \
  --key=/etc/kubernetes/ssl/etcd/member-$(hostname)-key.pem

# Verify backup
sudo ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db
```

### Restore from Backup

```bash
# Stop etcd
sudo systemctl stop etcd

# Restore from snapshot
sudo ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --data-dir /var/lib/etcd-backup

# Update etcd data directory
sudo mv /var/lib/etcd /var/lib/etcd-old
sudo mv /var/lib/etcd-backup /var/lib/etcd

# Start etcd
sudo systemctl start etcd
```

## Monitoring

### Basic Health Checks

```bash
# Check cluster health
kubectl cluster-info
kubectl get nodes
kubectl get pods --all-namespaces

# Check component status
kubectl get componentstatuses

# Check events
kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp
```

### Resource Usage

```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods --all-namespaces --sort-by=memory
kubectl top pods --all-namespaces --sort-by=cpu

# Check resource requests vs limits
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Log Collection

```bash
# Collect system logs
sudo journalctl -u kubelet --since "1 hour ago" > kubelet.log
sudo journalctl -u containerd --since "1 hour ago" > containerd.log

# Collect Kubernetes logs
kubectl logs --previous -n kube-system -l component=kube-apiserver
kubectl logs --previous -n kube-system -l component=kube-controller-manager
kubectl logs --previous -n kube-system -l component=kube-scheduler

# Collect cluster events
kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp > events.log
```

## Troubleshooting

### Common Issues

**1. Pod stuck in Pending:**
```bash
kubectl describe pod pod-name
kubectl get events --field-selector involvedObject.name=pod-name
```

**2. Node NotReady:**
```bash
kubectl describe node node-name
sudo systemctl status kubelet
sudo journalctl -u kubelet -f
```

**3. Service not accessible:**
```bash
kubectl get svc service-name -o wide
kubectl get endpoints service-name
kubectl describe svc service-name
```

### Emergency Recovery

```bash
# Reset cluster completely
./scripts/rollback.sh --force

# Redeploy from scratch
./scripts/setup-cluster.sh cluster-only
```

For configuration details, see [Configuration Guide](CONFIGURATION.md).