# Installation

## Prerequisites

**Control machine**

- Python 3.10+, Ansible 9.13+, git, ssh

**Target Kubernetes nodes**

- OS: Rocky 8/9, CentOS 8/9, AlmaLinux 8/9, RHEL 8/9, Ubuntu 20.04/22.04
- Minimum 2 GB RAM per node
- Root SSH access (public-key only)
- Python interpreter must be installed at `/opt/miniconda3/bin/python` — `ansible.cfg` sets `interpreter_python` to this path for all managed-node plays

**External hosts (production only)**

- CentOS 7 or Rocky 8 with sudo SSH access
- Port 9100 open for node_exporter scraping

---

## Control machine setup

```bash
git clone <repo-url> circleci-k8s-ansible
cd circleci-k8s-ansible
git submodule update --init --recursive
```

Install Python dependencies:

```bash
pip install -r requirements.txt
```

`requirements.txt` pins: `ansible==9.13.0`, `kubernetes>=31.0.0,<32.0.0`, `cryptography`, `jmespath`, `netaddr`, `PyYAML`.

Distribute the SSH public key to every node (K8s nodes and external hosts):

```bash
ssh-copy-id root@<node-ip>
```

**Vault password file (production only)**

`ansible.cfg` sets `vault_password_file = .vault-password`. Create the file before any vault-encrypted run:

```bash
echo '<your-vault-password>' > .vault-password
chmod 600 .vault-password
```

---

## K8s target node prep

These steps are performed once per node before running any playbook.

### Python 3.10+ (Miniconda)

`ansible.cfg` pins `interpreter_python = /opt/miniconda3/bin/python`. Install Miniconda at that path on every node:

```bash
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p /opt/miniconda3
```

### firewalld

```bash
systemctl disable --now firewalld
```

### DNS

`k8s-cluster.yml` sets `resolvconf_mode: none` — Kubespray will not manage `/etc/resolv.conf`. Configure DNS manually via NetworkManager or by editing `/etc/resolv.conf` before cluster deployment.

### SSD write cache (optional)

If nodes use SSDs, disable write cache to prevent data loss on power loss:

```bash
hdparm -W 0 /dev/sdX
```

### Test repo pre-clone (worker nodes, optional)

CircleCI worker nodes can pre-clone the sparse-checkout test repository to `/home/tc-repo/cubrid-testcases-private-ex`:

```bash
mkdir -p /home/tc-repo
git -C /home/tc-repo clone --filter=blob:none --no-checkout <repo-url> cubrid-testcases-private-ex
git -C /home/tc-repo/cubrid-testcases-private-ex sparse-checkout set <paths>
git -C /home/tc-repo/cubrid-testcases-private-ex checkout
```

> **Note:** containerd and kubelet bind mounts (`/home/containerd-data` → `/var/lib/containerd`, `/home/kubelet-data` → `/var/lib/kubelet`) are created automatically by `playbooks/cluster-only.yml`. No manual mount setup is required.

---

## External host prep (production only)

Each external host must have:

- Rocky 8 or CentOS 7 OS
- The controller's SSH public key in `root@authorized_keys`
- Port 9100 accessible from Prometheus pod hostIPs

Add each host to `inventory/production/external-nodes.ini` under `[external_host]` (bare-metal) or `[external_vm]` (virtual machines). Required per-host variables:

```ini
hostname  ansible_host=<ip>  distribution=<centos7|rocky8> \
          ansible_python_interpreter=<path> \
          type=<test|service|infra>  category=<sub-tag> \
          owner_email_primary=<UPN>  owner_email_secondary=<UPN>
```

`owner_email_secondary` is optional; omit it on single-owner hosts. Both `type` and `category` are exported as Prometheus labels and surfaced on Teams alert cards.

The `[external_nodes]` group is a union of `external_host` and `external_vm` and is what the `external-monitoring` role consumes.

---

## Inventory configuration

### hosts.ini

Groups required by Kubespray and the CircleCI playbooks:

```ini
[kube_control_plane]
k8s-master-01  ansible_host=<ip>  ansible_user=root

[etcd:children]
kube_control_plane

[kube_node]
k8s-worker-01  ansible_host=<ip>  ansible_user=root
k8s-worker-02  ansible_host=<ip>  ansible_user=root

[k8s_cluster:children]
kube_control_plane
kube_node

[circleci:children]
kube_control_plane
```

### external-nodes.ini (production only)

Groups: `external_host`, `external_vm`, `external_nodes`. The staging file is a stub with no actual hosts.

### group_vars layout

| File | Scope |
|------|-------|
| `group_vars/all/vars.yml` | Site-wide variables |
| `group_vars/all/kubespray.yml` | Kubernetes version (`1.31.9`), kubelet tuning, eviction thresholds |
| `group_vars/all/containerd.yml` | containerd runtime config |
| `group_vars/all/monitoring-external.yml` | External scrape config for Prometheus |
| `group_vars/all/vault.yml` | Vault-encrypted secrets (see Vault section) |
| `group_vars/k8s_cluster/k8s-cluster.yml` | Network plugin (calico), `resolvconf_mode: none`, service/pod CIDRs |
| `group_vars/k8s_cluster/addons.yml` | Kubespray addon flags |
| `group_vars/k8s_cluster/monitoring.yml` | kube-prometheus-stack chart version and values |
| `group_vars/k8s_cluster/monitoring-alertmanager.yml` | AlertManager routing config |
| `group_vars/k8s_cluster/monitoring-rules.yml` | Custom PrometheusRule definitions |
| `group_vars/circleci/runner.yml` | CircleCI namespace (`cubrid`), resource_class, replica count |

**Staging difference:** `monitoring.yml`, `monitoring-alertmanager.yml`, and `monitoring-rules.yml` under `inventory/staging/group_vars/k8s_cluster/` are symlinks to the production equivalents. The staging vault file contains placeholder values; `vault_teams_webhook_url` is commented out.

---

## Vault setup (production only)

Production requires three vault keys. Create the vault file:

```bash
ansible-vault create inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password
```

Required keys:

```yaml
vault_circleci_token: "<token>"
vault_grafana_admin_password: "<password>"
vault_teams_webhook_url: "<url>"
```

`vault_teams_webhook_url` must be a Power Automate Workflow trigger URL. The playbook asserts this regex at deploy time (`deploy-monitoring.yml:35`):

```
^https://[a-z0-9-]+(...).logic.azure.com|api.powerplatform.com/.../workflows/.../triggers/manual/paths/invoke?...sig=...
```

The URL must end in `/triggers/manual/paths/invoke?api-version=…&sig=…`. To edit an existing vault file:

```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password
```

---

## Cluster deployment

Verify connectivity before running playbooks:

```bash
ansible all -m ping
```

### Step 1 — Kubernetes cluster

```bash
ansible-playbook playbooks/cluster-only.yml
```

This runs Kubespray's `cluster.yml`, configures containerd/kubelet bind mounts, and sets up GlusterFS on worker nodes. On completion, `kubectl` artifacts land in `inventory/production/artifacts/`.

### Step 2 — Monitoring (in-cluster)

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring.yml
```

Renders the `alertmanager-config` Secret (with the vault Teams webhook URL), then deploys `kube-prometheus-stack` v75.6.2 via Helm.

### Step 3 — External monitoring (production only)

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-external-monitoring.yml
```

Installs `node_exporter` on the external fleet (142 hosts across 4 racks). Default batch size is 10 hosts; use `-e external_serial=1` for canary rollout.

Both steps 2 and 3 can be run together:

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring-full.yml
```

> In-cluster half must complete before external half — `deploy-monitoring-full.yml` enforces this order.

### Step 4 — CircleCI runner

```bash
ansible-playbook playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

Deploys the CircleCI container agent into the `cubrid` namespace. Requires the cluster to be up and `vault_circleci_token` to be set.

---

## Verification

**Cluster nodes:**

```bash
inventory/production/artifacts/kubectl.sh get nodes
```

**Monitoring pods:**

```bash
inventory/production/artifacts/kubectl.sh get pods -n monitoring
```

**External node_exporter** — confirm HTTP 200 from each external host:

```bash
curl -s http://<external-host-ip>:9100/metrics | head -5
```

**CircleCI runner:**

```bash
inventory/production/artifacts/kubectl.sh get deployment container-agent -n cubrid
```

---

## Next steps

- In-cluster monitoring, external fleet, and Teams alert routing — `docs/monitoring.md`
- CircleCI runner configuration and resource classes — `docs/circleci.md`
- Day-2 operations (upgrades, certificate renewal, scaling) — `docs/operations.md`
