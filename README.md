# circleci-k8s-ansible

Ansible automation that provisions a kubespray-managed Kubernetes cluster, a
kube-prometheus-stack monitoring stack (in-cluster + external fleet), and a
CircleCI self-hosted container runner.

## Quick start

```bash
git clone <repo> && cd circleci-k8s-ansible
git submodule update --init --recursive
python -m pip install -U -r requirements.txt

# Copy a sample inventory or edit production/staging directly
vim inventory/production/hosts.ini
vim inventory/production/external-nodes.ini   # production only

# Provision K8s + GlusterFS build cache
ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml

# Deploy in-cluster monitoring (Prometheus / Grafana / AlertManager) + Teams alerting
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml \
  --vault-password-file .vault-password

# (Production only) Deploy node_exporter on the external fleet
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-external-monitoring.yml

# Deploy the CircleCI runner
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

Detailed prerequisites, target-node preparation and verification steps live in [docs/installation.md](docs/installation.md).

## Deployment modes

| Playbook | Wraps (kubespray) | Purpose |
|----------|-------------------|---------|
| `playbooks/cluster-only.yml` | `cluster.yml` | K8s cluster + GlusterFS build cache |
| `playbooks/deploy-monitoring.yml` | — | In-cluster kube-prometheus-stack + AlertManager → Teams Secret |
| `playbooks/deploy-external-monitoring.yml` | — | `node_exporter` on `external_nodes` (production-only) |
| `playbooks/deploy-monitoring-full.yml` | — | In-cluster + external in one run |
| `playbooks/deploy-circleci.yml` | — | CircleCI `container-agent` Helm release in `cubrid` namespace |
| `playbooks/add-node.yml` | `scale.yml` | Add nodes to the cluster |
| `playbooks/remove-node.yml` | `remove-node.yml` | Remove nodes |
| `playbooks/upgrade-cluster.yml` | `upgrade-cluster.yml` | Roll a new `kube_version` |
| `playbooks/reset-cluster.yml` | `reset.yml` | Tear the cluster down |

## Repository layout

```
.
├── ansible.cfg                  # default inventory, vault password file, roles_path
├── requirements.txt             # ansible 9.13, kubernetes >=31, supporting libs
├── 3rdparty/kubespray/          # submodule pinned to v2.28.0
├── inventory/
│   ├── production/              # 3-node K8s + 142 external monitoring targets
│   └── staging/                 # 3-node K8s, no external hosts (monitoring symlinks to production)
├── playbooks/                   # 9 playbooks (5 wrap kubespray plays)
├── roles/
│   ├── circleci/                # Helm: container-agent in namespace `cubrid`
│   ├── external-monitoring/     # node_exporter 1.8.2 on external_nodes
│   └── glusterfs/               # replicated build-cache volume + cleanup CronJob
└── docs/
    ├── installation.md          # control machine + node prep + deploy
    ├── monitoring.md            # in-cluster + external + MS Teams alerting
    ├── circleci.md              # CircleCI runner deployment + ops
    ├── operations.md            # day-2 ops, node lifecycle, vault, backup
    ├── adr/
    │   └── 0001-adapter-less-workflow.md
    └── flow-definitions/        # Power Automate flow JSON exports
```

## Documentation

- [docs/installation.md](docs/installation.md) — Control machine + K8s and external node preparation + cluster deploy
- [docs/monitoring.md](docs/monitoring.md) — kube-prometheus-stack, external fleet `node_exporter`, AlertManager → MS Teams Workflow
- [docs/circleci.md](docs/circleci.md) — CircleCI runner Helm release, build-cache integration, ops
- [docs/operations.md](docs/operations.md) — Node lifecycle, vault, backup, troubleshooting
- [docs/adr/0001-adapter-less-workflow.md](docs/adr/0001-adapter-less-workflow.md) — Why AlertManager routes directly to Power Automate
- [CONTEXT.md](CONTEXT.md) — Glossary (alerting, external fleet)
- [3rdparty/kubespray/docs/](3rdparty/kubespray/docs/) — Upstream kubespray reference

## Supported targets

- **K8s cluster nodes**: Rocky Linux 8/9, CentOS 8/9, RHEL 8/9, AlmaLinux 8/9, Ubuntu 20.04/22.04
- **External monitoring hosts**: CentOS 7, Rocky Linux 8 (production fleet)
- **Architectures**: x86_64 (mixed architectures within a cluster are not supported)

## Common operations

```bash
# kubectl from the artifacts the cluster install produced
inventory/production/artifacts/kubectl.sh get nodes
inventory/production/artifacts/kubectl.sh get pods -A

# Edit the encrypted vault
ansible-vault edit inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password

# Dry run any playbook before committing
ansible-playbook -i inventory/staging/hosts.ini playbooks/cluster-only.yml --check
```

For everything else, start with [docs/operations.md](docs/operations.md).
