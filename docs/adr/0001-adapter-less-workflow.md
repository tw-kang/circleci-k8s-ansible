# ADR-0001 — Drop AlertManager → Teams adapter; route AlertManager directly to Power Automate Workflow

**Status**: Accepted (2026-05-15, round 6 — supersedes the round 1-5 'keep adapter' decision of 2026-05-11)

## Context

The original architecture sent AlertManager webhooks to an in-cluster Python adapter (`roles/alertmanager-teams-adapter/`, 234-line forwarder + Deployment / Service / ConfigMap / Secret), which translated the AM payload into the AdaptiveCard envelope expected by the Power Automate `Post adaptive card in chat or channel` action and forwarded it to a Workflow trigger.

That adapter accumulated 27 inline review findings on PR #1 (round 1 + round 2 adversarial grills, 2026-05-12), spanning OOM, SIGTERM, NetworkPolicy, PDB absence, image pin, systemd hardening, ephemeral Secret hygiene leaks, etc. Round 1-5 (2026-05-11) had previously rejected OSS forwarders (prom2teams, prometheus-msteams) and the Power Automate flow-only path, keeping the adapter.

Round 6 (2026-05-15) ran an in-place URL-swap PoC on the production helm release: AM webhook URL flipped from the adapter Service to a Power Automate Workflow trigger URL, and a hand-built flow (`triggerBody → For each alerts → Compose AdaptiveCard JSON → Post adaptive card in chat or channel`) handled the translation server-side. After fixing two flow construction bugs (action picked was `PostCardToConversation` instead of `PostAdaptiveCardToConversation`; `messageBody` carried an unevaluated `outputs('Compose')` literal instead of `@outputs('작성')`), the path passed all four pass criteria: card arrival ≤ group_wait + 5s, real Teams mention notification on M365 UPN owner_email, AdaptiveCard rendering parity (FactSet/summary/description/severity color), AM `Notify success`.

## Decision

Remove the adapter role entirely. AlertManager POSTs raw `{"alerts":[...]}` payload directly to a Power Automate Workflow trigger URL. The flow's `For each alerts → Compose AdaptiveCard JSON → Post adaptive card in chat or channel` chain handles all translation server-side at Microsoft.

The bearer Workflow URL is held in an external Kubernetes Secret (`alertmanager-config` in `monitoring` ns) created by the playbook's `Render alertmanager-config Secret` task (`no_log: true`). The kube-prometheus-stack chart references this Secret via `alertmanagerSpec.configSecret`; the URL therefore never reaches the helm release values dict.

The flow JSON definition is committed to `docs/flow-definitions/` so changes go through PR review. Without that discipline, a Portal-side edit could silently regress AdaptiveCard rendering with no AM-side error (AM only sees HTTP 200 from the trigger, regardless of whether the action downstream succeeds).

## Consequences

**Benefits**
- ~20 of 27 PR #1 round 1+2 inline findings auto-resolved (adapter code removed).
- Operational surface area shrinks: no Python pod to keep healthy. Concerns about replicas=1 SPOF, image pin, systemd-style hardening, OOM under burst, NetworkPolicy authn, PDB absence — all moot.
- Single source of truth for AdaptiveCard rendering moves to the flow JSON in `docs/flow-definitions/`.
- `helm get values kube-prometheus-stack` no longer leaks the bearer URL.

**Costs**
- **Secret protection is partial, not generic.** Only `helm get values` is cleaned of the URL. Other surfaces are equivalent or wider:
  - `kubectl get secret alertmanager-config -o yaml` returns base64 (same caliber as before)
  - `kubectl exec alertmanager-... -c alertmanager -- cat /etc/alertmanager/config/alertmanager.yaml` returns the URL plaintext to anyone with AM pod exec rights
  - The new path widens the audience from "adapter pod exec" to "AM pod exec" — potentially a broader monitoring-stack admin set
  This ADR's value is therefore *adapter complexity removal*, not generic secret hygiene. Treat the `helm get values` cleanup as an incidental win and rely on K8s RBAC for AM pod exec/secret-read for the rest.
- **Flow logic is no longer in code.** Compose body and action parameters live in Power Automate Portal. Mitigated by committing flow JSON exports to `docs/flow-definitions/` and treating any flow change as a PR-worthy commit. A Portal edit that bypasses git review can silently regress with no AM-side error.
- **Mention is M365-tenant-only.** `msteams.entities[].mentioned` resolves only when `owner_email` is a UPN inside the flow's tenant. Gmail / cross-tenant guest emails render the `<at>...</at>` token as plain text without producing a notification. This is identical to the adapter path's constraint.

## Rollback

`git revert` of this PR is **not sufficient by itself** — the vault `vault_teams_webhook_url` value cannot be reverted to a usable adapter-tenant URL because that URL was rotated and destroyed during the round 6 PoC sig-leak handling.

Manual rollback procedure:

1. Power Automate Portal: provision a new Workflow trigger URL suitable for the adapter to forward to (or rebuild a flow that accepts the adapter's already-translated `{type:"message",attachments:[…]}` envelope and posts the embedded card).
2. `ansible-vault edit inventory/production/group_vars/all/vault.yml` and update `vault_teams_webhook_url` to the new URL.
3. `git revert <PR-#1-merge-commit>` (or selectively revert this ADR's commits).
4. `ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml` — Play B reapplies adapter K8s resources, helm upgrade restores in-line `monitoring_alertmanager_values.config`.
5. Verify adapter pod healthy, AM `Notify success` to adapter Service, Teams card delivery.

Adapter source remains in git history (`git show c929c38`). If a re-introduction is needed, treat the history as reference material rather than literally reverting — the round 1+2 inline findings (OOM, SIGTERM, hardening, etc.) should be addressed before re-deploying.

## One-time cleanup after rollout

The adapter K8s resources are NOT pruned by `helm upgrade` (they were applied directly by the ansible role, not generated by the chart). Run once after the first post-merge `deploy-monitoring.yml` execution:

```
kubectl -n monitoring delete deploy,svc,cm,secret -l app.kubernetes.io/name=alertmanager-teams-adapter
```

Forgetting this leaves an idle Python pod in the namespace, holding a few MiB of memory and surfacing in `kubectl get all` noise.

## Alternatives considered

- **prom2teams** (Python/Flask, idealista, 288★) — rejected round 1-5 due to no msteams.entities mention support + Helm chart writing webhook URL to a plaintext ConfigMap (worse Secret hygiene than either path here).
- **prometheus-msteams** (Go, 567★) — rejected round 1-5: strict-struct `MsTeams` JSON deserialization silently strips the `entities` field, so `@mention` cannot fire.
- **Keep adapter, fix all 27 round 1+2 inline findings** — viable but ~20 of those evaporate with this approach. Estimated ~1-2 weeks of focused work vs. ~1 day for this ADR.
- **External-secrets-operator + sealed-secrets for the URL** — would address some non-helm surfaces but adds an operator dependency for one secret. Rejected as over-engineering.
- **Smoke-test canary alert** — proposed during grill 1 as a way to detect silent flow regressions. Deferred (would add `WorkflowCanary` rule to `monitoring-rules.yml` with severity=critical and 6h repeat_interval). Reconsider if a flow-side regression is observed in the field.

## Related

- **PR #1** (`external-monitoring` branch) — original adapter introduction + round 1+2 inline review (27 findings).
- **Memory `project_msteams_adapter_decision.md`** — round 6 decision (this ADR) and superseded round 1-5 history.
- **`docs/flow-definitions/`** (committed by follow-up) — Power Automate flow JSON export. Update any time the flow changes in Portal.
