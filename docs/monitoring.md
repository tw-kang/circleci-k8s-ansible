# Monitoring

## Overview

The monitoring stack has two halves:

- **In-cluster stack** — kube-prometheus-stack v75.6.2 deployed into the `monitoring` namespace via Helm.
- **External fleet** — node_exporter 1.8.2 installed on bare-metal hosts and VMs in the `external_nodes` inventory group (production only).
- **Alerting** — AlertManager POSTs raw `{"alerts":[...]}` directly to a Power Automate Workflow trigger URL. No in-cluster adapter. See ADR-0001.

```
inventory (owner_email_primary/secondary, type, category)
  │
  ▼
[localhost] external-monitoring role (scrape-config)
  builds external_scrape_static_configs fact
  │
  ▼
[kube_control_plane[0]] kube-prometheus-stack Helm upgrade
  Prometheus additionalScrapeConfigs ← static_configs
  │
  ├─── scrape ──► node_exporter :9100 on external_nodes
  │                 (labels: distribution, tier, environment,
  │                  owner_email_primary, owner_email_secondary,
  │                  type, category)
  │
  └─── alert ──► AlertManager
                   │
                   ▼
              POST {"alerts":[...]}
                   │
                   ▼
          Power Automate Workflow trigger
          For each alerts → Compose AdaptiveCard → Post to Teams
          @mention via msteams.entities (M365 UPN only)
```


## In-cluster stack

**Playbook**: `playbooks/deploy-monitoring.yml`
**Full pipeline**: `playbooks/deploy-monitoring-full.yml` (runs deploy-monitoring.yml then deploy-external-monitoring.yml)

### Chart

| Field | Value |
|---|---|
| Chart | prometheus-community/kube-prometheus-stack |
| Version | 75.6.2 |
| Namespace | monitoring |
| Helm release name | kube-prometheus-stack |

Source: `inventory/production/group_vars/k8s_cluster/monitoring.yml:14`

### Components

| Component | Kind | Notes |
|---|---|---|
| Prometheus | StatefulSet | additionalScrapeConfigs for external fleet |
| Grafana | Deployment | NodePort 32000, dashboard sidecar enabled |
| AlertManager | StatefulSet | config from external Secret, not helm values |
| kube-state-metrics | Deployment | in-cluster K8s object metrics |
| node-exporter | DaemonSet | in-cluster nodes; external nodes use separate role |

### NodePorts

| Service | NodePort |
|---|---|
| Grafana | 32000 |
| Prometheus | 32001 |
| AlertManager | 32002 |

Source: `inventory/production/group_vars/k8s_cluster/monitoring.yml:64,80` and `monitoring-alertmanager.yml:23`

Access via any cluster node IP (printed by the `Deployment summary` post-task):

```bash
# NodePort
http://<node-ip>:32000   # Grafana
http://<node-ip>:32001   # Prometheus
http://<node-ip>:32002   # AlertManager

# Port-forward (no node IP required)
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
```

### Storage and retention

Source: `inventory/production/group_vars/k8s_cluster/monitoring.yml:31-39`

| Component | PVC size | Retention |
|---|---|---|
| Prometheus | 250Gi | 15d |
| Grafana | 10Gi | — |
| AlertManager | 5Gi | 120h (chart default) |

StorageClass: `local-path` for all three.

### Scheduling

All components (Prometheus, Grafana, AlertManager, kube-state-metrics) are pinned to control-plane nodes via:

```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

Source: `monitoring.yml:67-72`, `monitoring.yml:83-88`, `monitoring-alertmanager.yml:26-30`

### Grafana credentials

Admin user: `admin`
Admin password: `vault_grafana_admin_password` (ansible-vault)

To retrieve the password from the deployed secret:

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

### Resource limits

Source: `inventory/production/group_vars/k8s_cluster/monitoring.yml:19-28`

| Component | CPU request/limit | Memory request/limit |
|---|---|---|
| Prometheus | 1500m / 4000m | 4Gi / 12Gi |
| Grafana | 500m / 2000m | 1Gi / 3Gi |
| AlertManager | 100m / 1000m | 256Mi / 1Gi |


## External fleet

**Playbook**: `playbooks/deploy-external-monitoring.yml`

Run standalone for node_exporter-only changes (requires Prometheus already running). Both inventory files must be passed so the firewall role can resolve `kube_control_plane` IPs:

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-external-monitoring.yml
```

### Role: external-monitoring

Source: `roles/external-monitoring/`

| Sub-task file | Runs on | Purpose |
|---|---|---|
| `tasks/install.yml` (via `node-exporter`) | `external_nodes` | binary + systemd install |
| `tasks/scrape-config.yml` | `localhost` | builds `external_scrape_static_configs` fact |
| `tasks/grafana-dashboard.yml` | `kube_control_plane[0]` | dashboard ConfigMap apply |

### node_exporter install

- Version: 1.8.2
- Binary: `/usr/local/bin/node_exporter`
- Listen: `0.0.0.0:9100`
- Download SHA256-verified against `node_exporter_sha256_map["1.8.2"]` in `monitoring-external.yml`

SHA256 (linux/amd64): `6809dd0b3ec45fd6e992c19071d6b5253aed3ead7bf0686885a51d85c6643c66`

Systemd unit hardening (`roles/external-monitoring/templates/node_exporter.service.j2`):
- `User=node_exporter` / `Group=node_exporter`
- `NoNewPrivileges=yes`
- `ProtectSystem=strict`
- `ProtectHome=yes`
- `PrivateTmp=yes`
- `ProtectControlGroups=yes`

### Inventory groups

| Group | Host class |
|---|---|
| `external_host` | bare-metal |
| `external_vm` | virtual machines |
| `external_nodes` | parent group (both) |

Target for `deploy-external-monitoring.yml`: `external_nodes`.

### Per-host inventory variables

Declared on each inventory row in `external-nodes.ini`:

| Variable | Purpose |
|---|---|
| `owner_email_primary` | Primary contact; becomes Prometheus label; used for Teams @mention |
| `owner_email_secondary` | Secondary contact (optional; empty = absent label) |
| `type` | Host role: `test` / `service` / `infra` |
| `category` | Workload sub-tag: `shell-ext`, `proxy`, `vm-host`, `perf-tpcc`, etc. |
| `distribution` | Derived from group membership: `centos7` / `rocky8` |

### external_scrape_static_configs fact

Built by `tasks/scrape-config.yml` on localhost (Play A of `deploy-monitoring.yml`). Each host emits one entry:

```yaml
- targets: ["<ansible_host>:9100"]
  labels:
    distribution: rocky8
    tier: host          # or: vm
    environment: production
    owner_email_primary: <from inventory>
    owner_email_secondary: <from inventory, empty if unset>
    type: <from inventory>
    category: <from inventory>
```

This fact is injected into `monitoring_prometheus_values.prometheusSpec.additionalScrapeConfigs[0].static_configs` at Helm render time. Source: `monitoring.yml:108`.

Play B asserts the fact exists before Helm render (skipped under `--check`). Source: `deploy-monitoring.yml:49-60`.

### Canary deploy

Control batch size with `external_serial` extra-var (default: 10):

```bash
# Phase 1 — single pilot host
ansible-playbook ... -e external_serial=1 --limit "<pilot-host>,kube_control_plane,localhost"

# Phase 2 — four hosts
ansible-playbook ... -e external_serial=4 --limit "<4-hosts>,kube_control_plane,localhost"

# Phase 3 — full fleet (default serial=10)
ansible-playbook ... playbooks/deploy-external-monitoring.yml
```

`max_fail_percentage: 20` per batch; `any_errors_fatal: false`.

### Staging

`inventory/staging/external-nodes.ini` is empty — no external hosts in staging. The `external_scrape_static_configs` fact resolves to an empty list, rendering a valid but empty `static_configs: []`.


## Configuration files

| File | Variables defined |
|---|---|
| `inventory/production/group_vars/k8s_cluster/monitoring.yml` | Prometheus, Grafana, storage, retention, `additionalScrapeConfigs`, `kube_prometheus_stack_values` |
| `inventory/production/group_vars/k8s_cluster/monitoring-alertmanager.yml` | AlertManager spec, route/receivers, `alertmanager_config_yaml`, `alertmanager_config_secret_name` |
| `inventory/production/group_vars/k8s_cluster/monitoring-rules.yml` | `monitoring_rules_external`, `monitoring_rules_meta` |
| `inventory/production/group_vars/all/monitoring-external.yml` | `node_exporter_scrape_interval` (30s), `node_exporter_scrape_timeout` (10s), `node_exporter_sha256_map` |

Staging `monitoring*.yml` files are symlinks to the production equivalents (drift prevention):

```
inventory/staging/group_vars/k8s_cluster/monitoring.yml
  -> ../../../production/group_vars/k8s_cluster/monitoring.yml
inventory/staging/group_vars/k8s_cluster/monitoring-alertmanager.yml
  -> ../../../production/group_vars/k8s_cluster/monitoring-alertmanager.yml
inventory/staging/group_vars/k8s_cluster/monitoring-rules.yml
  -> ../../../production/group_vars/k8s_cluster/monitoring-rules.yml
```


## Alerting (AlertManager → MS Teams)

### AlertManager Secret

AlertManager configuration (including the Workflow URL) is held in a Kubernetes Secret, not in helm values.

| Field | Value |
|---|---|
| Secret name | `alertmanager-config` |
| Namespace | `monitoring` |
| Key | `alertmanager.yaml` |
| Chart reference | `alertmanagerSpec.configSecret: "alertmanager-config"` |

The playbook task `Render alertmanager-config Secret` (deploy-monitoring.yml:98-116) applies this Secret with `no_log: true`. The bearer URL therefore does not appear in `helm get values kube-prometheus-stack` output.

The Workflow URL is validated before the helm upgrade by a `pre_tasks` assert (deploy-monitoring.yml:31-43):
- Must match `logic.azure.com` or `api.powerplatform.com` host suffix
- Must contain `/triggers/manual/paths/invoke?` with a `sig=` query parameter

### Routing

Source: `inventory/production/group_vars/k8s_cluster/monitoring-alertmanager.yml:65-86`

```yaml
route:
  receiver: teams-default
  group_by: [alertname, instance]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h       # fallback (critical-equivalent)
  routes:
    - matchers: [alertname = "Watchdog"]
      receiver: "null"
    - matchers: [alertname = "InfoInhibitor"]
      receiver: "null"
    - matchers: [severity = "info"]
      receiver: "null"
    - matchers: [severity = "none"]
      receiver: "null"
    - matchers: [severity = "warning"]
      receiver: teams-default
      repeat_interval: 3h
    - matchers: [severity = "critical"]
      receiver: teams-default
      repeat_interval: 1h
```

Watchdog is AlertManager's built-in always-firing deadman heartbeat; routing it to `null` suppresses Teams noise. InfoInhibitor is the chart-shipped meta-alert that drives the `inhibit_rules` block only.

`send_resolved: true` on the `teams-default` receiver.

### Alert rules

Two rule groups are defined in `monitoring-rules.yml`:

**`external-node.rules`** (monitoring_rules_external):

| Alert | Expr | For | Severity |
|---|---|---|---|
| ExternalNodeDown | `up{job="external-node-exporter"} == 0` | 3m | critical |
| ExternalNodeDiskFull | disk > 90%, excl. tmpfs/overlay/boot | 10m | warning |

CPU saturation rules are omitted intentionally — QA hosts legitimately push CPU > 90% under load tests. Source: `monitoring-rules.yml:6-9`.

**`alertmanager-self.rules`** (monitoring_rules_meta): self-monitoring on the alerting pipeline (webhook delivery canary).

### Power Automate flow definitions

| File | Purpose |
|---|---|
| `docs/flow-definitions/poc-channel-webhook.json` | Single owner @mention |
| `docs/flow-definitions/poc-channel-webhook-dual-mention.json` | Primary + secondary @mention (production) |

The dual-mention flow is the current production version (later timestamp). Any change to the flow in Power Automate Portal must be exported and committed here before merging. A Portal-side edit that bypasses git is undetectable from the AlertManager side (AM only sees HTTP 200 from the trigger regardless of downstream action success).

**AdaptiveCard color logic** (both flows):
```
color: @{if(equals(item()?['status'],'firing'),'attention','good')}
```
`attention` = firing (red), `good` = resolved (green).

**Mention mechanism** (dual-mention flow):
- `mentionEntities` is a Variable (not Compose) declared outside the foreach loop — the Bot Framework rejects `msteams.entities` unless it is a strict Array type.
- Tokens `<at>primary</at>` / `<at>secondary</at>` are hardcoded strings; Teams matches `entities[].text` against these at render time.
- `msteams.entities` field carries the variable: `"entities": "@variables('mentionEntities')"`.

### owner_email propagation

```
inventory hostvar (owner_email_primary / owner_email_secondary)
  → scrape-config role → static_configs.labels
  → Prometheus metric label (survives scrape)
  → AlertManager label (survives routing)
  → flow triggerBody().alerts[].labels
  → Compose AdaptiveCard → msteams.entities[]
  → Teams render: @mention notification
```

M365 UPN constraint: `msteams.entities[].mentioned` resolves only when `owner_email` is a UPN inside the flow's tenant. Gmail addresses and cross-tenant guest accounts render the `<at>...</at>` token as plain text without triggering a notification.


## ADR-0001 summary

An in-cluster Python adapter (234-line forwarder, Deployment/Service/ConfigMap/Secret) previously translated AM payloads into AdaptiveCard envelopes. It was removed after round 6 PoC (2026-05-15) validated direct AM → Power Automate routing.

Key points:
- Adapter source remains in git history at commit `c929c38`.
- `helm get values` no longer contains the bearer URL; other surfaces (kubectl exec into AM pod, `kubectl get secret`) are equivalent to before and depend on K8s RBAC.
- Idle adapter K8s resources (if not yet pruned) can be removed: `kubectl -n monitoring delete deploy,svc,cm,secret -l app.kubernetes.io/name=alertmanager-teams-adapter`

Full decision record: `docs/adr/0001-adapter-less-workflow.md`


## Operations

### Apply a config change

```bash
# In-cluster stack only (Helm + alertmanager-config Secret)
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring.yml

# Full pipeline (in-cluster + node_exporter on external fleet)
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring-full.yml
```

The playbook runs a pre-flight check that requires `kubectl >= 1.31` (for `--for=create` support) and a reachable cluster. Post-tasks wait for Prometheus, Grafana, and AlertManager pods to reach `Ready` before exiting.

### Rollout restart

```bash
kubectl -n monitoring rollout restart statefulset/prometheus-kube-prometheus-stack-prometheus
kubectl -n monitoring rollout restart deployment/kube-prometheus-stack-grafana
kubectl -n monitoring rollout restart statefulset/alertmanager-kube-prometheus-stack-alertmanager
```

### Troubleshooting

**Pods not starting**

```bash
kubectl -n monitoring get pods
kubectl -n monitoring describe pod <pod>
kubectl -n monitoring logs <pod> --previous
```

Common causes: PVC not bound (check `kubectl get pvc -n monitoring`); control-plane taint not matched (check nodeSelector/tolerations in monitoring.yml).

**Prometheus targets not appearing**

```bash
# Check scrape config rendered correctly
kubectl -n monitoring get secret prometheus-kube-prometheus-stack-prometheus \
  -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | grep external

# Verify the fact was built (dry-run check)
ansible-playbook -i ... playbooks/deploy-monitoring.yml --check
```

External hosts appear under `Status → Targets` in the Prometheus UI as job `external-node-exporter`.

**Grafana login**

If the password was rotated via vault, re-run `deploy-monitoring.yml` to push the updated value. Retrieve the current value with the command shown in the [Grafana credentials](#grafana-credentials) section above.

**PVC issues**

```bash
kubectl get pvc -n monitoring
```

StorageClass `local-path` provisions on-node; PVC binding requires the pod to be scheduled first.

**Flow regression detection**

AlertManager only sees HTTP 200 from the Power Automate trigger — a flow-side failure (broken AdaptiveCard JSON, wrong action type) produces no AM-side error. Verify card delivery directly in the Teams channel after any flow or routing change.
