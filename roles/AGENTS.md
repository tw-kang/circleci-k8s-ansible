<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-11 | Updated: 2026-04-11 -->

# roles

## Purpose
Project-specific Ansible roles. Referenced alongside kubespray's built-in roles via the `roles_path` setting in `ansible.cfg`.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `circleci/` | CircleCI self-hosted container runner Helm deployment (see `circleci/AGENTS.md`) |
| `glusterfs/` | GlusterFS replicated volume build cache management (see `glusterfs/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- New roles should follow the standard Ansible role structure: `tasks/`, `templates/`, `defaults/`, `handlers/`
- Kubespray roles live in `3rdparty/kubespray/roles/` — only project-specific roles go here

### Common Patterns
- Each role uses `tasks/main.yml` as the entry point
- Default variables are defined in `defaults/main.yml`
- Jinja2 templates are stored in `templates/` with `.j2` extension

## Dependencies

### Internal
- `../inventory/` — group_vars override role variables
- `../playbooks/` — Playbooks invoke roles via `include_role`

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
