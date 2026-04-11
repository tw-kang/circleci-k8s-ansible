<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-11 | Updated: 2026-04-11 -->

# inventory

## Purpose
Per-environment Ansible inventories (production, staging) containing host definitions, group variables, vault-encrypted secrets, kubectl artifacts, and credentials.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `production/` | Production environment inventory (see `production/AGENTS.md`) |
| `staging/` | Staging environment inventory (see `staging/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- Each environment shares the same directory structure: `group_vars/`, `host_vars/`, `credentials/`, `artifacts/`
- `vault.yml` files are encrypted with `ansible-vault` — cannot be read directly
- Files in `credentials/` contain sensitive data — use caution when committing
- `hosts.ini` is in `.gitignore` and must be created manually

### Common Patterns
- group_vars structure follows kubespray group hierarchy: `all`, `k8s_cluster`, `kube_control_plane`, `kube_node`, `circleci`
- Environment differences are managed through variable values only (structure is identical)

## Dependencies

### Internal
- `../ansible.cfg` — Default inventory path configuration
- `../roles/` — Roles reference variables defined in group_vars

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
