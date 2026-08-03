# Context — circleci-k8s-ansible

This repo provisions a kubespray-managed Kubernetes cluster on a CentOS 7 + Rocky 8 fleet that hosts a CircleCI self-hosted runner workload and the in-cluster monitoring stack (kube-prometheus-stack). External (non-K8s) hosts in the same fleet are brought into the monitoring fold via a slim node_exporter install plus a static `additionalScrapeConfigs` entry — they are NOT discovered through ServiceMonitors.

Architectural decisions live in `docs/adr/`. Start with [ADR-0001](docs/adr/0001-adapter-less-workflow.md) for the AlertManager → Teams alerting path, then [ADR-0002](docs/adr/0002-service-workinghours-route.md) for the service-host weekday-office-hours mute policy. shell controller/worker fan-out 러너 변경(RBAC + 노드 증설)의 배치는 [ADR-0003](docs/adr/0003-shell-controller-worker-runner.md)를 참조한다. 빌드 전송(병렬 download-build, mount 소유권의 config.yml 이관)은 [ADR-0005](docs/adr/0005-build-transport-and-mount-ownership.md)를 참조한다. 테스트 분배의 plugin 제거와 /rerun 코멘트 기반 failed-only rerun은 [ADR-0006](docs/adr/0006-plugin-free-split-and-custom-rerun.md)을 참조한다(설계만 존재, 미구현). runner pool 40/10 분할([ADR-0007](docs/adr/0007-runner-pool-partition.md))은 **기각**됐다 — 대기 문제의 근본 해결은 ADR-0003이다.

## Glossary

### AlertManager → Teams alerting

| Term | Meaning |
|------|---------|
| **Workflow trigger URL** | The Power Automate `When a Teams webhook request is received` trigger's HTTP POST URL (ending in `/triggers/manual/paths/invoke?api-version=…&sig=…`). The `sig=` query parameter is a bearer token; the URL itself is therefore a secret. Stored in `vault.yml` as `vault_teams_webhook_url`. |
| **Workflow flow** | The Power Automate flow instance that fires on the trigger. Composes an AdaptiveCard from the AM webhook body and posts to Teams via the `Post adaptive card in chat or channel` action. Lives in Power Automate Portal; JSON export committed to `docs/flow-definitions/` (see ADR-0001). |
| **adapter** (deprecated, see [ADR-0001](docs/adr/0001-adapter-less-workflow.md)) | The in-cluster Python forwarder (`roles/alertmanager-teams-adapter/`, removed 2026-05-15) that previously sat between AlertManager and the Workflow trigger. Replaced by the flow's own Compose action. Source remains in git history (`git show c929c38`) for rollback reference. |
| **alertmanager-config Secret** | External Kubernetes Secret in the `monitoring` namespace, holding the AlertManager configuration (`alertmanager.yaml` key) including the bearer Workflow URL. Referenced from helm values via `alertmanagerSpec.configSecret`, so the URL never reaches `helm get values` output. Created by the playbook's `Render alertmanager-config Secret` task with `no_log`. |
| **monitoring stack** | The kube-prometheus-stack helm release (`kube-prometheus-stack` in `monitoring` ns) — Prometheus, Grafana, AlertManager, kube-state-metrics, in-cluster node-exporter daemonset. |
| **korea-workinghours** (`active_time_intervals`) | AlertManager mute window: weekdays 08-18 `Asia/Seoul`. Gates the `scope=external` + `type=service` sub-route only — K8s default alerts and the `scope=meta` canary stay 24/7. AlertManager does NOT queue suppressed alerts; alerts that fire AND auto-resolve fully outside the window never reach Teams (sole post-hoc visibility is Prometheus / AlertManager UI). See [ADR-0002](docs/adr/0002-service-workinghours-route.md). |

### External fleet

| Term | Meaning |
|------|---------|
| **external host** | A physical CentOS 7 / Rocky 8 server in the QA fleet that is NOT part of the K8s cluster. node_exporter is installed via the `external-monitoring` role; Prometheus scrapes via `additionalScrapeConfigs` (not via ServiceMonitor). |
| **external_nodes** | Inventory group containing all external hosts. Subgroups `external_host` (physical) + `external_vm`. |
| **owner_email_primary / owner_email_secondary** | Per-host inventory variables. Both propagate as Prometheus labels → AlertManager → Teams card mentions via `msteams.entities`. The `dual-mention` flow (`docs/flow-definitions/poc-channel-webhook-dual-mention.json`) conditionally appends a second `<at>…</at>` entity when `owner_email_secondary` is non-empty. M365 UPN inside the flow's tenant produces a real Teams notification; cross-tenant guest (gmail.com etc.) renders as plain text only — no notification fires. |
| **type / category** | Per-host inventory variables. `type` is free-form but production values today are `service`, `infra`, `test`, `test-perf`, `test-func`; `external_scrape_type_default: unassigned` is the fallback when an inventory line omits `type=`. `category` is a free-form workload sub-tag. Both surface as Prometheus labels. `type` drives the [ADR-0002](docs/adr/0002-service-workinghours-route.md) Teams-routing policy (`type=service` → workinghours-only; everything else → null). |
| **scope** (alert-rule label) | Required label on every external rule in `monitoring-rules.yml`: `scope: external` for data-plane rules on the external fleet, `scope: meta` for the AlertManager pipeline self-canary. The Teams routing tree in `monitoring-alertmanager.yml` keys off this label to separate the externally-gated path (workinghours mute) from the K8s-default + meta 24/7 path. K8s default alerts from kube-prometheus-stack have no `scope` label and fall through to the 24/7 fallback. New external rules MUST set `scope` — omitting it routes the rule into the K8s fallback (24/7) instead of the intended workinghours gate. |
| **external_scrape_static_configs** | Ansible fact built by `roles/external-monitoring/tasks/scrape-config.yml`. A list of `{targets, labels}` entries that the playbook injects into `monitoring.yml`'s `additionalScrapeConfigs[0].static_configs`. Empty on `staging` because `inventory/staging/external-nodes.ini` has no hosts. |

### CircleCI shell controller/worker 러너

계획 중인 `test_shell` fan-out 구조([ADR-0003](docs/adr/0003-shell-controller-worker-runner.md) 참조;
테스트 쪽 설계는 cubrid-testtools ADR-0001). 이 repo는 *인프라* 부분 — RBAC, 노드, 공유 저장소 —
만 소유하며, worker Pod의 형태나 entrypoint 로직은 소유하지 않는다(그건 cubridci 이미지에 있음).

| 용어 | 의미 |
|------|------|
| **controller pod** | shell 파이프라인 1개에 대한 유일한 CircleCI task pod(resource class `cubrid/ramdisk`). entrypoint가 `kubectl`로 worker pod를 생성하고 CTP 테스트 케이스를 SSH로 fan-out한 뒤 teardown한다. `maxConcurrentTasks`에 1로 카운트된다. |
| **worker pod** | controller가 별도(out-of-band)로 생성하는 bare Pod(파이프라인당 50개); `sshd`만 실행하며 CircleCI task가 아니므로 `maxConcurrentTasks`에 **카운트되지 않는다**. K8s API를 호출하지 않으므로 default SA + `automountServiceAccountToken: false`를 사용한다. |
| **shell-controller (ServiceAccount)** | controller pod가 worker pod를 `kubectl`로 생성/삭제할 수 있도록 `cubrid` ns에서 namespaced `Role`(pods: create/delete/get/list/watch)에 바인딩된 SA. `roles/circleci/templates/shell-controller-rbac.yaml.j2`가 렌더하고 `roles/circleci/tasks/rbac.yml`이 적용하며, `circleci-values.yaml.j2`의 `cubrid/ramdisk` resource-class podSpec에 `serviceAccountName`으로 참조된다. `runner.yml`의 `shell_controller_sa`로 설정. |
| **pod-slot ceiling** | shell fan-out의 실제 동시성 한계: `kubelet_max_pods`(기본 110) × 노드 수. worker 노드 4대 = 440 슬롯, full fleet ~7–8개(각 51 pod); 초과 worker pod는 `Pending`으로 남는다. 필요 시 `k8s_cluster/k8s-cluster.yml`의 `kubelet_max_pods`로 상향. `maxConcurrentTasks`에 묶이지 않음(그건 controller만 제한). |

### 빌드 전송 (build transport)

빌드 산출물이 CircleCI 아티팩트에서 GlusterFS `build-cache`로 오는 경로([ADR-0005](docs/adr/0005-build-transport-and-mount-ownership.md) 참조). 핵심 원칙: 클러스터에 inbound가 없으므로 전송 주체는 항상 클러스터 내부이고, 방향은 outbound pull이다.

| 용어 | 의미 |
|------|------|
| **download-build (job)** | (의미 변경, ADR-0005) PR·develop 양쪽의 빌드 전송 job. PR에서는 현행대로 test_shell에 **선행**(requires 유지)하여 debug 빌드를, develop 머지에서는 release·debug 둘 다 신규 레이아웃 + `.complete` sentinel로 저장한다. 테스트 pod는 postStart가 아니라 job step에서 sentinel을 확인하고 마운트한다(rerun 동시 실행 안전벨트). 폐기된 과거 계약은 "postStart job명 분기"다. 기각 이력: leader pod 다운로드(2026-07-29), 병렬 시작(2026-07-30, test step 45m timeout 리스크) — ADR-0005 Considered options. |
| **moded 레이아웃** | GlusterFS 빌드 트리의 현행 레이아웃 `builds/<SHA>/{release,debug}/CUBRID`. PR은 debug만, develop 머지는 둘 다 채운다. |
| **flat 레이아웃** | 구 경로 `builds/<SHA>/CUBRID`. "과거 데이터"가 아니다 — CircleCI는 *PR 브랜치의* config.yml을 실행하므로, moded 레이아웃 도입 커밋(cubrid `ae1376524`) 이전에 갈라진 PR은 **지금도 새로** flat으로 저장한다. postStart v2의 호환 mount가 이들을 받쳐 준다. 제거 조건은 [ADR-0005](docs/adr/0005-build-transport-and-mount-ownership.md) "flat 호환 제거 조건" 참조. |
| **`.complete` sentinel** | `builds/<SHA>/<mode>/`의 다운로드·해제 완료 표식 파일. 소비자(테스트 pod, 에이전트)는 디렉토리 존재가 아니라 sentinel을 기준으로 대기한다 — "tar 추출 중 디렉토리" race 방지. |
| **postStart v2** | task pod postStart의 축소된 계약: 구 flat 경로가 존재하면 mount(구 config 호환), 없으면 즉시 exit 0. CUBRID 경로 지식·대기 루프·job명 분기는 config.yml step으로 이관되어 본 repo 소유가 아니다. 과도기 이후에는 testcases overlay만 남는다. |

### CI 테스트 재실행 (test rerun)

테스트 분배와 실패 재실행 경로([ADR-0006](docs/adr/0006-plugin-free-split-and-custom-rerun.md), 스펙 CUBRIDQA-1471). plugin(`circleci tests run`) 기반 분배와 네이티브 "rerun failed tests only"는 폐기되었다 — tests split 전환 후 네이티브 버튼은 사실상 풀런으로 동작한다. **아래는 설계만 있고 아직 배포되지 않았다** — 현재 운영되는 것은 여전히 plugin 기반 분배와 네이티브 rerun이다. CUBRIDQA-1471은 lane 관련 범위만 제외하고([ADR-0007](docs/adr/0007-runner-pool-partition.md) 기각) 나머지는 진행하며, 2026-08-03에 [ADR-0003](docs/adr/0003-shell-controller-worker-runner.md)보다 우선순위가 높게 결정됐다.

| 용어 | 의미 |
|------|------|
| **tests split (내장 분배)** | agent 내장 `circleci tests split` — 전 suite(shell/sql/medium)의 유일한 테스트 분배 수단. 외부 plugin 다운로드가 없고 timing 기반 분배를 유지한다. |
| **failed-only rerun** | 직전 실패 케이스만 재실행하는 자체 rerun 파이프라인. CircleCI tests API의 실패 목록 ∩ 현재 브랜치 glob으로 대상을 정하고 tests split으로 분배한다. 성공 시 같은 SHA의 status context가 갱신되어 머지가 풀린다 — 보장 수준은 "모든 케이스가 해당 SHA에서 1회 이상 통과"(네이티브 rerun failed tests only와 동일). |
| **/rerun 트리거** | PR 코멘트 `/rerun <suite>`. GitHub Actions(issue_comment)가 실패 잡 자동 탐색 → 가드(SHA 일치, 교집합 비어있지 않음) → CircleCI 파이프라인 트리거(`pull/<PR>/head`). write 권한자 전용, 접수·거부 모두 봇 코멘트로 안내, 가드 실패 시 암묵적 풀런 전환 없음. 기존 `CIRCLECI_TOKEN` secret(cubridci 계정) 사용. |
| **lane 분할** (기각, [ADR-0007](docs/adr/0007-runner-pool-partition.md)) | self-hosted 자리 50개를 별도 resource class로 갈라 full run / rerun을 분리하려던 안(`cubrid/rerun` 신설, 40/10). **2026-08-03 기각** — lane은 자리를 늘리지 않고 나눌 뿐이라 full run이 +25% 느려지고 바쁜 날 본선 사용률이 73%→91%로 오르는 반면, 떼어낸 lane은 약 5%만 쓰인다. 대기의 원인은 배분이 아니라 용량(full run 1건 = task 50개 × 31분 × 하루 37건)이므로 [ADR-0003](docs/adr/0003-shell-controller-worker-runner.md)으로 넘긴다. 구 문서에 나오는 "full run lane / rerun lane"이 이 안을 가리킨다. |
| **tc-repo seed** | 노드 `/home/tc-repo/` 아래의 git seed(blob:none partial + sparse clone). task pod가 overlay lowerdir로 마운트해 재사용한다. `cubrid-testcases-private-ex`(비공개 — 갱신 cron은 자격증명 문제로 보류, 수동 갱신)와 `cubrid-testtools`(공개 — ansible cron으로 자동 갱신)가 있다. |
