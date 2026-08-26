<!-- Generated from code — keep in sync with playbooks/, roles/, inventory/ -->

# circleci-k8s-ansible

Ansible automation that provisions a kubespray-managed Kubernetes cluster, a kube-prometheus-stack monitoring stack (in-cluster + external fleet), a CircleCI self-hosted container runner, and the GitHub Actions self-hosted runners (ARC).

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
| `roles/arc/README.md` | ARC runner deployment + the workflow ↔ IaC contract table. `gha-ci.yml` points at it |
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
| `playbooks/` | 10 playbooks: `cluster-only`, `deploy-monitoring`, `deploy-external-monitoring`, `deploy-monitoring-full`, `deploy-circleci`, `deploy-arc`, `add-node`, `remove-node`, `upgrade-cluster`, `reset-cluster`. Five wrap kubespray plays from `3rdparty/kubespray/`. |
| `roles/arc/` | Helm release `cubrid-arc` (`gha-runner-scale-set` 0.14.2) — the GitHub Actions self-hosted runners. Two lanes, one role: production (ns `gha-ci`) untagged, fork (ns `default`) behind tag `arc_fork`. Also owns the `<release>-gh-app` Secret, `<release>-pod-template` and `<release>-job-hook` ConfigMaps. Contract table in `roles/arc/README.md` |
| `roles/circleci/` | Helm releases `container-agent` (cubrid/ramdisk) + `container-agent-staging` (cubrid/staging canary lane, tag `staging_agent`) in namespace `cubrid` |
| `roles/external-monitoring/` | `node_exporter` install (SHA256-verified) on `external_nodes` + builds `external_scrape_static_configs` fact |
| `roles/glusterfs/` | Replicated `build-cache` volume on `kube_node`. Actions: `install` / `add_node` / `remove_node` / `reset`. Daily cleanup CronJob, 7d retention, one window over every path in `glusterfs_cleanup_dirs` (CircleCI `builds/` + `gha-ci/builds/pr` + `gha-ci/runs`; `gha-ci/builds/develop` is kept) |

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
| `Render the GitHub App secret` | `roles/arc/tasks/lane.yml` | Builds `<release>-gh-app` from `vault_arc_*` / `vault_arc_fork_*` with `no_log: true`. The three key names are fixed by the ARC chart. |
| `Refuse to repoint another lane's scale set` | `roles/arc/tasks/lane.yml` | Both lanes share a release name, so deploying one into the namespace the other still occupies makes Helm silently upgrade — and repoint — the wrong scale set. Compares `githubConfigUrl` before touching anything. Same-name releases in *different* namespaces are fine and expected. |
| `Validate ARC configuration` | `playbooks/deploy-arc.yml` | Rejects a deploy from an inventory with no `group_vars/arc/` before the banner or any cluster call. `roles/arc/tasks/main.yml` repeats it as `Require the arc group_vars` so the role stays safe when included from elsewhere (same shape as the `staging_token` guard). |

### Validation

- `ansible-playbook --syntax-check -i inventory/<env>/hosts.ini playbooks/<name>.yml`
- `--check` for dry run
- `ansible all -i inventory/<env>/hosts.ini -m ping`

## Dependencies

### Internal

- `3rdparty/kubespray` (v2.28.0) — cluster provisioning engine
- `roles/arc`, `roles/circleci`, `roles/external-monitoring`, `roles/glusterfs` — project-local roles

### External

- Kubernetes 1.31.9 (pinned in `inventory/<env>/group_vars/all/kubespray.yml`)
- kube-prometheus-stack v75.6.2 Helm chart
- CircleCI `container-agent` Helm chart (https://packagecloud.io/circleci/container-agent/helm)
- ARC `gha-runner-scale-set` + `gha-runner-scale-set-controller` 0.14.2 Helm charts (`oci://ghcr.io/actions/actions-runner-controller-charts/…`)
- GitHub Apps `cubrid-arc-runner-bot` / `cubrid-arc-fork-runner-bot` (stored as `vault_arc_gh_app_*` / `vault_arc_fork_gh_app_*`)
- Power Automate Workflow trigger URL (production-only, stored as `vault_teams_webhook_url`)
- `node_exporter` 1.8.2 binary (SHA256 pinned in `roles/external-monitoring/defaults/main.yml`)
