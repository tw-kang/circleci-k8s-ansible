# Context — circleci-k8s-ansible

This repo provisions a kubespray-managed Kubernetes cluster on a CentOS 7 + Rocky 8 fleet that hosts a CircleCI self-hosted runner workload and the in-cluster monitoring stack (kube-prometheus-stack). External (non-K8s) hosts in the same fleet are brought into the monitoring fold via a slim node_exporter install plus a static `additionalScrapeConfigs` entry — they are NOT discovered through ServiceMonitors.

Architectural decisions live in `docs/adr/`. Start with [ADR-0001](docs/adr/0001-adapter-less-workflow.md) for the AlertManager → Teams alerting path.

## Glossary

### AlertManager → Teams alerting

| Term | Meaning |
|------|---------|
| **Workflow trigger URL** | The Power Automate `When a Teams webhook request is received` trigger's HTTP POST URL (ending in `/triggers/manual/paths/invoke?api-version=…&sig=…`). The `sig=` query parameter is a bearer token; the URL itself is therefore a secret. Stored in `vault.yml` as `vault_teams_webhook_url`. |
| **Workflow flow** | The Power Automate flow instance that fires on the trigger. Composes an AdaptiveCard from the AM webhook body and posts to Teams via the `Post adaptive card in chat or channel` action. Lives in Power Automate Portal; JSON export committed to `docs/flow-definitions/` (see ADR-0001). |
| **adapter** (deprecated, see [ADR-0001](docs/adr/0001-adapter-less-workflow.md)) | The in-cluster Python forwarder (`roles/alertmanager-teams-adapter/`, removed 2026-05-15) that previously sat between AlertManager and the Workflow trigger. Replaced by the flow's own Compose action. Source remains in git history (`git show c929c38`) for rollback reference. |
| **alertmanager-config Secret** | External Kubernetes Secret in the `monitoring` namespace, holding the AlertManager configuration (`alertmanager.yaml` key) including the bearer Workflow URL. Referenced from helm values via `alertmanagerSpec.configSecret`, so the URL never reaches `helm get values` output. Created by the playbook's `Render alertmanager-config Secret` task with `no_log`. |
| **monitoring stack** | The kube-prometheus-stack helm release (`kube-prometheus-stack` in `monitoring` ns) — Prometheus, Grafana, AlertManager, kube-state-metrics, in-cluster node-exporter daemonset. |

### External fleet

| Term | Meaning |
|------|---------|
| **external host** | A physical CentOS 7 / Rocky 8 server in the QA fleet that is NOT part of the K8s cluster. node_exporter is installed via the `external-monitoring` role; Prometheus scrapes via `additionalScrapeConfigs` (not via ServiceMonitor). |
| **external_nodes** | Inventory group containing all external hosts. Subgroups `external_host` (physical) + `external_vm`. |
| **owner_email_primary / owner_email_secondary** | Per-host inventory variables. Both propagate as Prometheus labels → AlertManager → Teams card mentions via `msteams.entities`. The `dual-mention` flow (`docs/flow-definitions/poc-channel-webhook-dual-mention.json`) conditionally appends a second `<at>…</at>` entity when `owner_email_secondary` is non-empty. M365 UPN inside the flow's tenant produces a real Teams notification; cross-tenant guest (gmail.com etc.) renders as plain text only — no notification fires. |
| **type / category** | Per-host inventory variables (`test` / `service` / `infra` and free-form category). Surface as Prometheus labels so dashboards and routing rules can filter. |
| **external_scrape_static_configs** | Ansible fact built by `roles/external-monitoring/tasks/scrape-config.yml`. A list of `{targets, labels}` entries that the playbook injects into `monitoring.yml`'s `additionalScrapeConfigs[0].static_configs`. Empty on `staging` because `inventory/staging/external-nodes.ini` has no hosts. |
