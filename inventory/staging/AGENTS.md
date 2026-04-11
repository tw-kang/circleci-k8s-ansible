<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-11 | Updated: 2026-04-11 -->

# staging

## Purpose
Staging environment Ansible inventory. Mirrors the production structure for pre-production testing and validation.

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

## For AI Agents

### Working In This Directory
- Structure mirrors `../production/` — changes to one environment often need to be replicated
- No `artifacts/` directory until cluster is deployed
- Same vault encryption scheme as production

### Common Patterns
- Identical group_vars structure as production: `all/`, `k8s_cluster/`, `kube_control_plane/`, `kube_node/`, `circleci/`

## Dependencies

### Internal
- `../production/` — Reference environment; staging mirrors its structure

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
