<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-11 | Updated: 2026-04-11 -->

# playbooks

## Purpose
Ansible playbooks that manage the full Kubernetes cluster lifecycle — deployment, node management, CircleCI runner deployment, and monitoring stack provisioning.

## Key Files

| File | Description |
|------|-------------|
| `cluster-only.yml` | Full cluster deployment — bind mounts, kubespray execution, GlusterFS, kubectl verification |
| `deploy-circleci.yml` | Deploy CircleCI container runner to an existing cluster |
| `deploy-monitoring.yml` | Deploy kube-prometheus-stack (Prometheus, Grafana, AlertManager) via Helm |
| `add-node.yml` | Add worker nodes to an existing cluster (includes GlusterFS) |
| `remove-node.yml` | Remove nodes from the cluster (includes GlusterFS cleanup) |
| `reset-cluster.yml` | Complete cluster teardown (irreversible — use with caution) |
| `upgrade-cluster.yml` | Cluster upgrade via kubespray |

## For AI Agents

### Working In This Directory
- All playbooks access kubectl through kubespray artifacts (`artifacts/kubectl.sh`)
- `cluster-only.yml` is the main deployment playbook — it bind-mounts containerd/kubelet data to `/home` partition
- `reset-cluster.yml` is irreversible — never run without confirmation
- CircleCI deployment requires a vault-encrypted token

### Testing Requirements
- Syntax check: `ansible-playbook --syntax-check -i inventory/production/hosts.ini <playbook>.yml`
- Dry run: use `--check` mode
- Vault playbooks: `--vault-password-file .vault-password` is required

### Common Patterns
- Each playbook displays an info banner at start and a status summary on completion
- Kubespray playbooks are imported via `import_playbook: ../3rdparty/kubespray/`
- pre_tasks verify kubectl artifacts exist and cluster is accessible
- kubectl commands run with `delegate_to: localhost`

## Dependencies

### Internal
- `../3rdparty/kubespray/` — Imports cluster.yml, upgrade-cluster.yml, etc.
- `../roles/circleci/` — CircleCI runner deployment role
- `../roles/glusterfs/` — GlusterFS build cache role
- `../inventory/` — Host definitions and variables

### External
- `kubernetes.core` — Helm and k8s modules (Ansible collection)
- `ansible.posix` — mount module

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
