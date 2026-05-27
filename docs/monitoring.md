# Monitoring

## 개요

모니터링 스택은 두 부분으로 구성된다:

- **In-cluster 스택** — kube-prometheus-stack v75.6.2를 Helm으로 `monitoring` namespace에 배포한다.
- **외부 fleet** — `external_nodes` 인벤토리 그룹의 베어메탈 호스트 및 VM에 node_exporter 1.8.2를 설치한다 (production 전용).
- **알림** — AlertManager가 raw `{"alerts":[...]}` 페이로드를 Power Automate Workflow trigger URL로 직접 POST한다. In-cluster 어댑터 없음. ADR-0001 참조.

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


## In-cluster 스택

**Playbook**: `playbooks/deploy-monitoring.yml`
**전체 파이프라인**: `playbooks/deploy-monitoring-full.yml` (deploy-monitoring.yml 실행 후 deploy-external-monitoring.yml 실행)

### Chart

| 항목 | 값 |
|---|---|
| Chart | prometheus-community/kube-prometheus-stack |
| Version | 75.6.2 |
| Namespace | monitoring |
| Helm release name | kube-prometheus-stack |

출처: `inventory/production/group_vars/k8s_cluster/monitoring.yml:14`

### 구성 요소

| 구성 요소 | Kind | 비고 |
|---|---|---|
| Prometheus | StatefulSet | 외부 fleet용 additionalScrapeConfigs |
| Grafana | Deployment | NodePort 32000, dashboard sidecar 활성화 |
| AlertManager | StatefulSet | helm values가 아닌 외부 Secret에서 설정 로드 |
| kube-state-metrics | Deployment | In-cluster K8s 오브젝트 메트릭 |
| node-exporter | DaemonSet | In-cluster 노드용. 외부 노드는 별도 role 사용 |

### NodePort

| 서비스 | NodePort |
|---|---|
| Grafana | 32000 |
| Prometheus | 32001 |
| AlertManager | 32002 |

출처: `inventory/production/group_vars/k8s_cluster/monitoring.yml:64,80` 및 `monitoring-alertmanager.yml:23`

클러스터 노드 IP로 접근한다 (`Deployment summary` post-task에서 출력):

```bash
# NodePort
http://<node-ip>:32000   # Grafana
http://<node-ip>:32001   # Prometheus
http://<node-ip>:32002   # AlertManager

# Port-forward (노드 IP 불필요)
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
```

### 스토리지 및 보존 기간

출처: `inventory/production/group_vars/k8s_cluster/monitoring.yml:31-39`

| 구성 요소 | PVC 크기 | 보존 기간 |
|---|---|---|
| Prometheus | 250Gi | 15d |
| Grafana | 10Gi | — |
| AlertManager | 5Gi | 120h (chart 기본값) |

StorageClass: 세 구성 요소 모두 `local-path`.

### 스케줄링

Prometheus, Grafana, AlertManager, kube-state-metrics 전체를 컨트롤 플레인 노드에 고정한다:

```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

출처: `monitoring.yml:67-72`, `monitoring.yml:83-88`, `monitoring-alertmanager.yml:26-30`

### Grafana 자격증명

Admin 사용자: `admin`
Admin 비밀번호: `vault_grafana_admin_password` (ansible-vault)

배포된 Secret에서 비밀번호를 조회한다:

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

### 리소스 제한

출처: `inventory/production/group_vars/k8s_cluster/monitoring.yml:19-28`

| 구성 요소 | CPU request/limit | Memory request/limit |
|---|---|---|
| Prometheus | 1500m / 4000m | 4Gi / 12Gi |
| Grafana | 500m / 2000m | 1Gi / 3Gi |
| AlertManager | 100m / 1000m | 256Mi / 1Gi |


## 외부 fleet

**Playbook**: `playbooks/deploy-external-monitoring.yml`

node_exporter 변경만 적용할 때 단독 실행한다 (Prometheus가 이미 실행 중이어야 함). 방화벽 role이 `kube_control_plane` IP를 해석할 수 있도록 두 인벤토리 파일을 모두 전달한다:

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-external-monitoring.yml
```

### Role: external-monitoring

출처: `roles/external-monitoring/`

| Sub-task 파일 | 실행 대상 | 역할 |
|---|---|---|
| `tasks/install.yml` (via `node-exporter`) | `external_nodes` | 바이너리 + systemd 설치 |
| `tasks/scrape-config.yml` | `localhost` | `external_scrape_static_configs` fact 생성 |
| `tasks/grafana-dashboard.yml` | `kube_control_plane[0]` | dashboard ConfigMap 적용 |

### node_exporter 설치

- 버전: 1.8.2
- 바이너리: `/usr/local/bin/node_exporter`
- Listen: `0.0.0.0:9100`
- `monitoring-external.yml`의 `node_exporter_sha256_map["1.8.2"]`로 다운로드 SHA256 검증

SHA256 (linux/amd64): `6809dd0b3ec45fd6e992c19071d6b5253aed3ead7bf0686885a51d85c6643c66`

Systemd 유닛 보안 강화 (`roles/external-monitoring/templates/node_exporter.service.j2`):
- `User=node_exporter` / `Group=node_exporter`
- `NoNewPrivileges=yes`
- `ProtectSystem=strict`
- `ProtectHome=yes`
- `PrivateTmp=yes`
- `ProtectControlGroups=yes`

### 인벤토리 그룹

| 그룹 | 호스트 종류 |
|---|---|
| `external_host` | 베어메탈 |
| `external_vm` | 가상 머신 |
| `external_nodes` | 상위 그룹 (둘 다 포함) |

`deploy-external-monitoring.yml`의 대상: `external_nodes`.

### 호스트별 인벤토리 변수

`external-nodes.ini`의 각 인벤토리 행에 선언한다:

| 변수 | 역할 |
|---|---|
| `owner_email_primary` | 주 담당자. Prometheus 레이블로 사용되며 Teams @mention에 활용 |
| `owner_email_secondary` | 보조 담당자 (선택. 값이 없으면 레이블 미포함) |
| `type` | 호스트 역할: `test` / `service` / `infra` |
| `category` | 워크로드 서브 태그: `shell-ext`, `proxy`, `vm-host`, `perf-tpcc` 등 |
| `distribution` | 그룹 멤버십에서 파생: `centos7` / `rocky8` |

### external_scrape_static_configs fact

localhost에서 `tasks/scrape-config.yml`이 생성한다 (`deploy-monitoring.yml`의 Play A). 각 호스트는 다음 항목 하나를 생성한다:

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

이 fact는 Helm 렌더 시 `monitoring_prometheus_values.prometheusSpec.additionalScrapeConfigs[0].static_configs`에 주입된다. 출처: `monitoring.yml:108`.

Play B는 Helm 렌더 전에 fact 존재를 assert한다 (`--check` 시 건너뜀). 출처: `deploy-monitoring.yml:49-60`.

### Canary 배포

`external_serial` extra-var로 배치 크기를 조절한다 (기본값: 10):

```bash
# Phase 1 — 단일 파일럿 호스트
ansible-playbook ... -e external_serial=1 --limit "<pilot-host>,kube_control_plane,localhost"

# Phase 2 — 4개 호스트
ansible-playbook ... -e external_serial=4 --limit "<4-hosts>,kube_control_plane,localhost"

# Phase 3 — 전체 fleet (기본 serial=10)
ansible-playbook ... playbooks/deploy-external-monitoring.yml
```

배치당 `max_fail_percentage: 20`; `any_errors_fatal: false`.

### Staging

`inventory/staging/external-nodes.ini`는 비어 있다 — staging에 외부 호스트 없음. `external_scrape_static_configs` fact가 빈 리스트로 해석되어 유효하지만 비어 있는 `static_configs: []`를 렌더링한다.


## 설정 파일

| 파일 | 정의된 변수 |
|---|---|
| `inventory/production/group_vars/k8s_cluster/monitoring.yml` | Prometheus, Grafana, 스토리지, 보존 기간, `additionalScrapeConfigs`, `kube_prometheus_stack_values` |
| `inventory/production/group_vars/k8s_cluster/monitoring-alertmanager.yml` | AlertManager spec, route/receivers, `alertmanager_config_yaml`, `alertmanager_config_secret_name` |
| `inventory/production/group_vars/k8s_cluster/monitoring-rules.yml` | `monitoring_rules_external`, `monitoring_rules_meta` |
| `inventory/production/group_vars/all/monitoring-external.yml` | `node_exporter_scrape_interval` (30s), `node_exporter_scrape_timeout` (10s), `node_exporter_sha256_map` |

Staging의 `monitoring*.yml` 파일은 production 파일의 심볼릭 링크다 (드리프트 방지):

```
inventory/staging/group_vars/k8s_cluster/monitoring.yml
  -> ../../../production/group_vars/k8s_cluster/monitoring.yml
inventory/staging/group_vars/k8s_cluster/monitoring-alertmanager.yml
  -> ../../../production/group_vars/k8s_cluster/monitoring-alertmanager.yml
inventory/staging/group_vars/k8s_cluster/monitoring-rules.yml
  -> ../../../production/group_vars/k8s_cluster/monitoring-rules.yml
```


## 알림 (AlertManager → MS Teams)

### AlertManager Secret

AlertManager 설정(Workflow URL 포함)은 helm values가 아닌 Kubernetes Secret에 저장한다.

| 항목 | 값 |
|---|---|
| Secret 이름 | `alertmanager-config` |
| Namespace | `monitoring` |
| Key | `alertmanager.yaml` |
| Chart 참조 | `alertmanagerSpec.configSecret: "alertmanager-config"` |

Render alertmanager-config Secret task (deploy-monitoring.yml:98-116)가 `no_log: true`로 이 Secret을 적용한다. 따라서 bearer URL은 `helm get values kube-prometheus-stack` 출력에 나타나지 않는다.

Workflow URL은 helm upgrade 전에 `pre_tasks` assert로 검증한다 (deploy-monitoring.yml:31-43):
- `logic.azure.com` 또는 `api.powerplatform.com` 호스트 suffix와 일치해야 함
- `/triggers/manual/paths/invoke?`에 `sig=` 쿼리 파라미터가 포함되어야 함

### 라우팅

출처: `inventory/production/group_vars/k8s_cluster/monitoring-alertmanager.yml:65-86`

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

Watchdog은 AlertManager의 내장 상시 발화 deadman 하트비트다. `null`로 라우팅하여 Teams 노이즈를 억제한다. InfoInhibitor는 chart에 포함된 메타 알림으로 `inhibit_rules` 블록만 구동한다.

`teams-default` receiver에 `send_resolved: true` 설정.

### 알림 규칙

`monitoring-rules.yml`에 두 개의 규칙 그룹이 정의되어 있다:

**`external-node.rules`** (monitoring_rules_external):

| Alert | Expr | For | Severity |
|---|---|---|---|
| ExternalNodeDown | `up{job="external-node-exporter"} == 0` | 3m | critical |
| ExternalNodeDiskFull | disk > 90%, tmpfs/overlay/boot 제외 | 10m | warning |

CPU 포화 규칙은 의도적으로 제외한다 — QA 호스트는 부하 테스트 중 CPU > 90%가 정상 범위다. 출처: `monitoring-rules.yml:6-9`.

**`alertmanager-self.rules`** (monitoring_rules_meta): 알림 파이프라인 자체 모니터링 (webhook 전달 카나리).

### Power Automate Flow definitions

| 파일 | 역할 |
|---|---|
| `docs/flow-definitions/poc-channel-webhook.json` | 단일 소유자 @mention |
| `docs/flow-definitions/poc-channel-webhook-dual-mention.json` | Primary + secondary @mention (production) |

dual-mention flow가 현재 production 버전이다 (최신 타임스탬프). Power Automate Portal에서 flow를 변경한 경우 반드시 내보내기(export)하여 머지 전에 커밋해야 한다. Portal 측 편집이 git을 우회하면 AlertManager 쪽에서 감지할 수 없다 (AM은 downstream 액션 성공 여부와 무관하게 trigger에서 HTTP 200만 수신함).

**AdaptiveCard 색상 로직** (두 flow 모두):
```
color: @{if(equals(item()?['status'],'firing'),'attention','good')}
```
`attention` = firing (빨강), `good` = resolved (초록).

**Mention 메커니즘** (dual-mention flow):
- `mentionEntities`는 foreach 루프 외부에서 선언된 Variable이다 (Compose 아님). Bot Framework가 `msteams.entities`를 엄격한 Array 타입으로 요구하기 때문이다.
- `<at>primary</at>` / `<at>secondary</at>` 토큰은 하드코딩된 문자열이다. Teams는 렌더 시 `entities[].text`와 이 토큰을 매칭한다.
- `msteams.entities` 필드에 변수를 전달한다: `"entities": "@variables('mentionEntities')"`.

### owner_email 레이블 흐름

```
inventory hostvar (owner_email_primary / owner_email_secondary)
  → scrape-config role → static_configs.labels
  → Prometheus metric label (scrape 이후 유지)
  → AlertManager label (라우팅 이후 유지)
  → flow triggerBody().alerts[].labels
  → Compose AdaptiveCard → msteams.entities[]
  → Teams render: @mention 알림
```

M365 UPN 제약: `msteams.entities[].mentioned`는 `owner_email`이 flow 테넌트 내 UPN일 때만 해석된다. Gmail 주소 및 크로스 테넌트 게스트 계정은 `<at>...</at>` 토큰을 알림 없이 일반 텍스트로 렌더링한다.


## ADR-0001 요약

In-cluster Python 어댑터 (234줄 forwarder, Deployment/Service/ConfigMap/Secret)가 이전에 AM 페이로드를 AdaptiveCard 봉투로 변환했다. round 6 PoC (2026-05-15)에서 직접 AM → Power Automate 라우팅이 검증된 후 제거되었다.

주요 사항:
- 어댑터 소스는 git 히스토리의 커밋 `c929c38`에 남아 있다.
- `helm get values`에 더 이상 bearer URL이 포함되지 않는다. 다른 접근 경로(AM Pod에서 kubectl exec, `kubectl get secret`)는 이전과 동일하며 K8s RBAC에 의존한다.
- 미정리 어댑터 K8s 리소스는 다음 명령으로 제거한다: `kubectl -n monitoring delete deploy,svc,cm,secret -l app.kubernetes.io/name=alertmanager-teams-adapter`

전체 결정 기록: `docs/adr/0001-adapter-less-workflow.md`


## 운영

### 설정 변경 적용

```bash
# In-cluster 스택만 (Helm + alertmanager-config Secret)
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring.yml

# 전체 파이프라인 (in-cluster + 외부 fleet node_exporter)
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring-full.yml
```

playbook은 `kubectl >= 1.31` (`--for=create` 지원 필요)과 클러스터 접근 가능 여부를 pre-flight 검사한다. post-task에서 Prometheus, Grafana, AlertManager Pod가 `Ready` 상태가 될 때까지 대기 후 종료한다.

### Rollout 재시작

```bash
kubectl -n monitoring rollout restart statefulset/prometheus-kube-prometheus-stack-prometheus
kubectl -n monitoring rollout restart deployment/kube-prometheus-stack-grafana
kubectl -n monitoring rollout restart statefulset/alertmanager-kube-prometheus-stack-alertmanager
```

### 트러블슈팅

**Pod가 시작되지 않는 경우**

```bash
kubectl -n monitoring get pods
kubectl -n monitoring describe pod <pod>
kubectl -n monitoring logs <pod> --previous
```

주요 원인: PVC 미바인딩 (`kubectl get pvc -n monitoring` 확인); 컨트롤 플레인 taint 불일치 (monitoring.yml의 nodeSelector/tolerations 확인).

**Prometheus 타겟이 보이지 않는 경우**

```bash
# scrape 설정이 올바르게 렌더링되었는지 확인
kubectl -n monitoring get secret prometheus-kube-prometheus-stack-prometheus \
  -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | grep external

# fact 생성 확인 (dry-run)
ansible-playbook -i ... playbooks/deploy-monitoring.yml --check
```

외부 호스트는 Prometheus UI의 `Status → Targets`에서 job `external-node-exporter`로 표시된다.

**Grafana 로그인**

vault를 통해 비밀번호를 교체한 경우 `deploy-monitoring.yml`을 재실행하여 변경된 값을 반영한다. 현재 값은 위의 [Grafana 자격증명](#grafana-자격증명) 섹션의 명령으로 조회한다.

**PVC 문제**

```bash
kubectl get pvc -n monitoring
```

StorageClass `local-path`는 노드에 온디맨드 프로비저닝한다. PVC 바인딩은 Pod가 먼저 스케줄링되어야 한다.

**Flow 회귀 감지**

AlertManager는 Power Automate trigger에서 HTTP 200만 수신한다 — flow 측 장애 (손상된 AdaptiveCard JSON, 잘못된 action 타입)는 AM 측에서 오류가 발생하지 않는다. flow 또는 라우팅 변경 후에는 Teams 채널에서 카드 전달을 직접 확인한다.
