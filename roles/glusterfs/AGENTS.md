<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-11 | Updated: 2026-04-11 -->

# glusterfs

## Purpose
Ansible role that manages a GlusterFS replicated volume for CI/CD build cache across Kubernetes worker nodes. Supports full lifecycle: install, add node, remove node, and reset.

## Key Files

| File | Description |
|------|-------------|
| `tasks/main.yml` | Entry point — routes to action-specific task files based on `glusterfs_action` variable |
| `tasks/install.yml` | Install GlusterFS packages from CentOS SIG Storage repo |
| `tasks/configure.yml` | Peer probing and replicated volume creation |
| `tasks/mount.yml` | Mount GlusterFS volume and register in fstab |
| `tasks/k8s_cleanup.yml` | Deploy Kubernetes CronJob for build cache retention cleanup |
| `tasks/add_node.yml` | Add a new node to the GlusterFS cluster |
| `tasks/remove_node.yml` | Remove a node from the GlusterFS cluster |
| `tasks/reset.yml` | Full GlusterFS teardown and cleanup |
| `defaults/main.yml` | Default variables — volume name, paths, repo URL, cleanup schedule |
| `handlers/main.yml` | Service restart handlers |
| `templates/glusterfs-repo.j2` | Yum repository configuration template |
| `templates/build-cache-cleanup-cronjob.yaml.j2` | K8s CronJob manifest for build cache cleanup |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `tasks/` | Task files for each lifecycle action |
| `templates/` | Jinja2 templates for repo config and K8s manifests |
| `defaults/` | Default variable values |
| `handlers/` | Service handlers |

## For AI Agents

### Working In This Directory
- Control behavior via `glusterfs_action`: `install` (default), `add_node`, `remove_node`, `reset`
- Default volume name is `build-cache` with replica count 2
- All data paths are under `/home/` to use the large partition: brick at `/home/gluster/brick1`, mount at `/home/build-cache`
- Build cache cleanup CronJob runs daily at 03:00, retains builds for 3 days
- Repository is CentOS SIG Storage (GlusterFS 10) for RHEL 8 / CentOS 8

### Testing Requirements
- Verify GlusterFS service: `systemctl status glusterd`
- Check volume: `gluster volume info build-cache`
- Check peers: `gluster peer status`
- Check mount: `df -h /home/build-cache`
- Check CronJob: `kubectl get cronjob -n kube-system build-cache-cleanup`

### Common Patterns
- Peer probing uses retries with delay for reliability (`glusterfs_peer_probe_retries: 5`)
- Volume creation is idempotent — checks existing state before creating
- CronJob uses `busybox:1.36` image with hostPath mount to clean old builds

## Dependencies

### Internal
- `../../inventory/*/group_vars/` — Variable overrides for environment-specific settings

### External
- GlusterFS 10 packages from CentOS SIG Storage repository
- `kubernetes.core` Ansible collection (for CronJob deployment)

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
