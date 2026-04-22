# node-exporter-external Role

Installs and manages Prometheus `node_exporter` on **CentOS 7** and **Rocky 8** external machines (physical + VM) that are outside the Kubernetes cluster.

## Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `node_exporter_version` | `1.8.2` | node_exporter release version |
| `node_exporter_prometheus_source_ips` | `[]` | Pod hostIPs from `kubectl get pod status.hostIP` — used for firewalld rich rules |
| `node_exporter_force_reinstall` | `false` | Trigger full uninstall + reinstall |
| `node_exporter_uninstall_only` | `false` | Only uninstall (for rollback) |
| `node_exporter_download_url_mirror` | `""` | Internal tarball mirror URL |
| `node_exporter_manage_firewalld` | `true` | Skip firewalld tasks when false |

## Security Notes

- Binary SHA256 verified via `get_url checksum:` before extraction.
- SELinux: `restorecon` applied after binary install; `semanage fcontext` fallback if it fails.
- Firewalld: TCP/9100 opened only to explicit Prometheus pod hostIPs (not broad subnet).

## Supported OS

- CentOS 7 (systemd, SELinux enforcing)
- Rocky Linux 8

CentOS 6 is explicitly unsupported (glibc too old for modern node_exporter).
