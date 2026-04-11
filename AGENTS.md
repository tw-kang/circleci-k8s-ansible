<!-- Generated: 2026-04-11 | Updated: 2026-04-11 -->

# circleci-k8s-ansible

## Purpose
Ansible-based automation project that deploys production Kubernetes clusters using Kubespray, with integrated CircleCI self-hosted container runners, GlusterFS replicated build cache, and a monitoring stack (Prometheus/Grafana/AlertManager).

## Key Files

| File | Description |
|------|-------------|
| `ansible.cfg` | Ansible configuration — inventory path, roles_path, SSH connection, vault settings |
| `requirements.txt` | Python dependencies (ansible, kubernetes, cryptography, etc.) |
| `.gitmodules` | kubespray v2.28.0 submodule reference |
| `.vault-password` | Ansible Vault password file |
| `.gitignore` | Git ignore rules |
| `README.md` | Project documentation — Quick Start, deployment methods |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `3rdparty/` | External submodules (kubespray v2.28.0) |
| `docs/` | Installation, configuration, and operations guides (see `docs/AGENTS.md`) |
| `inventory/` | Per-environment inventories (production, staging) (see `inventory/AGENTS.md`) |
| `playbooks/` | Ansible playbooks for cluster lifecycle management (see `playbooks/AGENTS.md`) |
| `roles/` | Ansible roles — circleci, glusterfs (see `roles/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- `vault.yml` files are encrypted with `ansible-vault` — cannot be read directly; `.vault-password` file is required
- kubespray is managed as a git submodule at `3rdparty/kubespray` — do not modify it directly
- `ansible.cfg` sets `roles_path = roles:3rdparty/kubespray/roles`, so both local and kubespray roles are available
- Python interpreter is set to `/opt/miniconda3/bin/python`

### Testing Requirements
- Syntax check: `ansible-playbook --syntax-check -i inventory/<env>/hosts.ini playbooks/<playbook>.yml`
- Dry run: use `--check` flag
- Vault-related operations require `--vault-password-file .vault-password`

### Common Patterns
- All playbooks access kubectl through kubespray artifacts (`artifacts/kubectl.sh`)
- Helm chart deployments use the `kubernetes.core.helm` module
- Environment separation is managed via `inventory/production` and `inventory/staging`

## Dependencies

### Internal
- `3rdparty/kubespray` — Kubernetes cluster provisioning engine
- `roles/` — CircleCI runner and GlusterFS build cache roles

### External
- `ansible==9.13.0` — Automation framework
- `kubernetes>=31.0.0` — K8s API client
- `kubespray v2.28.0` — K8s cluster deployment tool

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
