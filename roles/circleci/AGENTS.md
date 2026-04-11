<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-11 | Updated: 2026-04-11 -->

# circleci

## Purpose
Ansible role that deploys CircleCI self-hosted container runner to a Kubernetes cluster using the official Helm chart from `packagecloud.io/circleci/container-agent`.

## Key Files

| File | Description |
|------|-------------|
| `tasks/main.yml` | Main task file — verifies Helm, adds repo, creates namespace, templates values, deploys chart |
| `templates/circleci-values.yaml.j2` | Jinja2 template for Helm values (token, resource class, replicas, resources, ramdisk) |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `tasks/` | Ansible task definitions |
| `templates/` | Jinja2 templates for Helm values |

## For AI Agents

### Working In This Directory
- The role requires these variables: `circleci_namespace`, `resource_class`, `token` (vault-encrypted)
- `token` must be encrypted with ansible-vault — the role validates this
- Helm values template configures: token, resource class, replicas, resource limits, ramdisk, and GlusterFS build cache volume mounts
- Config is written to `{{ circleci_config_path }}/values.yaml` on the target host
- Backup templates (`*_bak`, `*_with_glusterfs`, `*_without_glusterfs`) are untracked variants

### Testing Requirements
- Verify Helm is installed on target nodes before running
- Check deployment: `kubectl get deployment container-agent -n <namespace>`
- Check pods: `kubectl get pods -n <namespace>`

### Common Patterns
- Uses `kubernetes.core.helm_repository` to add the CircleCI Helm repo
- Uses `kubernetes.core.helm` to deploy the chart
- Namespace is created via `kubernetes.core.k8s` if it doesn't exist

## Dependencies

### Internal
- `../../inventory/*/group_vars/circleci/runner.yml` — Runner configuration variables
- `../../inventory/*/group_vars/all/vault.yml` — Encrypted CircleCI token

### External
- `container-agent` Helm chart from `packagecloud.io/circleci/container-agent`
- `kubernetes.core` Ansible collection

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
