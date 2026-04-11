<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-11 | Updated: 2026-04-11 -->

# production

## Purpose
Production environment Ansible inventory. Contains host definitions, group variables for Kubernetes and CircleCI configuration, vault-encrypted secrets, kubespray-generated kubectl artifacts, and cluster credentials.

## Key Files

| File | Description |
|------|-------------|
| `hosts.ini` | Host inventory file (not tracked in git — create manually) |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `group_vars/` | Group variable files organized by Ansible host groups |
| `host_vars/` | Per-host variable overrides (k8s-worker-01, k8s-worker-02) |
| `credentials/` | Cluster credentials (kubeadm certificate key) |
| `artifacts/` | Kubespray-generated kubectl artifacts (admin.conf, kubectl, kubectl.sh) |

## For AI Agents

### Working In This Directory
- `hosts.ini` must be created from `hosts.ini.sample` — it contains actual server IPs
- `artifacts/` is populated automatically by kubespray during cluster deployment
- `artifacts/kubectl.sh` is the primary way all playbooks interact with the cluster
- `credentials/kubeadm_certificate_key.creds` is sensitive — do not expose

### Common Patterns
- group_vars follow kubespray's group hierarchy: `all/`, `k8s_cluster/`, `kube_control_plane/`, `kube_node/`, `circleci/`
- Secrets are stored in `vault.yml` files encrypted with ansible-vault

## Dependencies

### Internal
- `../staging/` — Mirror structure for staging environment
- `../../ansible.cfg` — References this directory as default inventory

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
