<!-- Generated from code — keep in sync with playbooks/, roles/, inventory/ -->

# circleci-k8s-ansible

Ansible automation that provisions a kubespray-managed Kubernetes cluster, a kube-prometheus-stack monitoring stack (in-cluster + external fleet), and a CircleCI self-hosted container runner.

## Key files

| Path | Description |
|------|-------------|
| `ansible.cfg` | Inventory default (`inventory/production/hosts.ini`), `roles_path` (local + kubespray), `vault_password_file=.vault-password`, `interpreter_python=/opt/miniconda3/bin/python` |
| `requirements.txt` | `ansible==9.13.0`, `kubernetes>=31.0.0`, supporting libs |
| `.gitmodules` | kubespray submodule pinned to `v2.28.0` |
| `.vault-password` | Vault password file (required by `ansible.cfg`) |
| `CONTEXT.md` | Domain glossary (alerting, external fleet) |
| `README.md` | Quick start, deployment modes table |
| `docs/installation.md` | Control machine + node prep + cluster deploy |
| `docs/monitoring.md` | kube-prometheus-stack + external node_exporter + MS Teams alerting |
| `docs/circleci.md` | CircleCI runner deployment + ops |
| `docs/operations.md` | Day-2 ops, node lifecycle, vault, backup |
| `docs/adr/0001-adapter-less-workflow.md` | AlertManager → Teams direct routing decision |
| `docs/flow-definitions/` | Power Automate flow JSON exports (single + dual-mention) |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `3rdparty/kubespray/` | kubespray `v2.28.0` submodule. Do not modify directly. |
| `docs/` | Topical guides + ADRs + flow definitions |
| `inventory/production/` | 3-node K8s cluster + 142 external monitoring targets |
| `inventory/staging/` | 3-node K8s cluster; external-nodes inventory is an empty stub. monitoring config files are symlinks to production to avoid drift. |
| `playbooks/` | 9 playbooks: `cluster-only`, `deploy-monitoring`, `deploy-external-monitoring`, `deploy-monitoring-full`, `deploy-circleci`, `add-node`, `remove-node`, `upgrade-cluster`, `reset-cluster`. Five wrap kubespray plays from `3rdparty/kubespray/`. |
| `roles/circleci/` | Helm releases `container-agent` (cubrid/ramdisk) + `container-agent-staging` (cubrid/staging canary lane, tag `staging_agent`) in namespace `cubrid` |
| `roles/external-monitoring/` | `node_exporter` install (SHA256-verified) on `external_nodes` + builds `external_scrape_static_configs` fact |
| `roles/glusterfs/` | Replicated `build-cache` volume on `kube_node`. Actions: `install` / `add_node` / `remove_node` / `reset`. Daily cleanup CronJob, 7d retention |

## For AI agents

### Working in this directory

- `vault.yml` files are encrypted; pass `--vault-password-file .vault-password` to read or use them
- kubespray is a git submodule at `3rdparty/kubespray/` (pinned to branch `v2.28.0` in `.gitmodules`); never edit in place
- `ansible.cfg` sets `roles_path = roles:3rdparty/kubespray/roles`, so role names from both trees resolve
- Python interpreter on managed nodes is `/opt/miniconda3/bin/python`
- After a deploy, `kubectl` artifacts land in `inventory/<env>/artifacts/` (use `kubectl.sh`)

### Docs language convention

- Human-targeted docs are written in Korean: `README.md`, `docs/*.md` body text, `docs/adr/*.md`
- AI-targeted docs stay in English: this `AGENTS.md`, `CONTEXT.md` glossary
- Code identifiers, file paths, ansible/kubectl commands, YAML/JSON snippets, and technical proper nouns (AlertManager, Prometheus, Helm, kubespray, …) are preserved in their original form even inside Korean prose

### Critical task names

| Task | Where | Why it matters |
|------|-------|----------------|
| `Render alertmanager-config Secret` | `playbooks/deploy-monitoring.yml` | Writes `vault_teams_webhook_url` into an external K8s Secret with `no_log: true`. Helm values reference it via `alertmanagerSpec.configSecret`, so the URL never reaches `helm get values` output. |
| Token validation block | `playbooks/deploy-circleci.yml:23-40` | Rejects unencrypted `vault_circleci_token`. |
| `additionalScrapeConfigs` injection | `playbooks/deploy-monitoring.yml` | Consumes the `external_scrape_static_configs` fact built by `roles/external-monitoring/tasks/scrape-config.yml`. |

### Validation

- `ansible-playbook --syntax-check -i inventory/<env>/hosts.ini playbooks/<name>.yml`
- `--check` for dry run
- `ansible all -i inventory/<env>/hosts.ini -m ping`

## Dependencies

### Internal

- `3rdparty/kubespray` (v2.28.0) — cluster provisioning engine
- `roles/circleci`, `roles/external-monitoring`, `roles/glusterfs` — project-local roles

### External

- Kubernetes 1.31.9 (pinned in `inventory/<env>/group_vars/all/kubespray.yml`)
- kube-prometheus-stack v75.6.2 Helm chart
- CircleCI `container-agent` Helm chart (https://packagecloud.io/circleci/container-agent/helm)
- Power Automate Workflow trigger URL (production-only, stored as `vault_teams_webhook_url`)
- `node_exporter` 1.8.2 binary (SHA256 pinned in `roles/external-monitoring/defaults/main.yml`)
