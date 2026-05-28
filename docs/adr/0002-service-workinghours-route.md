# ADR-0002 — `type=service` 외부 호스트 알림을 평일 08-18 KST로 음소거; K8s/meta는 24/7 유지

**Status**: Accepted (2026-05-28)

## Context

PR #1(2026-05-27 머지) 이후 외부 fleet(`external_host` + `external_vm`) 약 50대가 in-cluster Prometheus의 스크레이프 대상이 되었고, 알림은 AlertManager → Power Automate Workflow → Teams 채널로 24/7 전송된다. 운영하면서 두 가지 noise 패턴이 드러났다:

1. **인프라/테스트 호스트의 야간·주말 노이즈.** `type=infra`(VM 호스트), `type=test-perf` / `test-func`(QA 워크로드 머신)는 새벽 시간대 디스크 풀, 부하 테스트 종료 후 일시 down 등 운영자가 즉시 대응할 필요가 없는 알림이 빈번하게 발생한다. (`monitoring-rules.yml` 주석 참고: "QA hosts legitimately push CPU >90% under perf/load tests".)
2. **`type=service` 호스트의 야간 자율 복구.** CI 빌드 서버(`build01~03`), 메시지 큐(`qa03`), R&D org 서버(`org01~02`), 프록시(`proxy01`) 같은 진짜 서비스 호스트도 새벽엔 호출 받을 인원이 없다. 인지하지 못한 채 자동 복구되는 경우가 다수.

기존 라우팅(PR #1 형태의 `monitoring-alertmanager.yml`)은 severity 기반(`critical 1h / warning 3h / info|none null`)이며 시간대·target 구분 없이 24/7 전송된다.

## Decision

**`scope=external` + `type=service`인 알림만** AlertManager `active_time_intervals`로 평일 08-18 `Asia/Seoul` 음소거 게이트를 적용한다. critical, warning 모두 동일하게 게이트를 통과시킨다. 다른 외부 호스트(`type=infra | test* | unassigned`)는 Teams로 보내지 않고 `null` receiver로 차단한다 — firing 자체는 Prometheus와 AlertManager UI에 남으므로 사후 가시성은 유지된다.

K8s 클러스터 default 알림(`scope` 라벨 없음)과 알림 파이프라인 자체 카나리(`scope=meta`)는 기존 24/7 정책을 유지한다.

라우팅 트리는 `monitoring-alertmanager.yml`의 `alertmanager_config_yaml.route.routes`에서 first-match-wins 순서로 표현된다:

```
1. alertname=Watchdog | InfoInhibitor | severity=info | severity=none  → null
2. scope=external + type!=service                                       → null
3. scope=external + type=service  (active_time_intervals: korea-workinghours)
                                                                        → teams-default
4. severity=warning / critical (K8s default + scope=meta 폴백)          → teams-default
```

discriminator는 **`scope` 라벨**을 채택한다. `scope=external`은 `monitoring-rules.yml`의 모든 외부 rule이 명시적으로 부착하고, `scope=meta`는 카나리 rule이 부착한다. K8s default 알림은 라벨이 없어 폴백 분기로 자연스럽게 흐른다. `job` 라벨(자동 부여) 대안 대비 의도가 매처에 그대로 드러나 라우팅 트리 가독성이 우월하다 — 단, **새 외부 rule을 추가할 때 `scope: external` 라벨을 반드시 명시한다는 컨벤션**이 유지되어야 한다.

## Consequences

**Benefits**

- `type=service` 호스트의 야간/주말 Teams 알림이 거의 0으로 떨어진다. 출근 시점에 firing 중인 알림만 그룹별로 일괄 수신.
- `type=infra` / `test*` 호스트의 false-positive성 noise가 Teams에서 완전히 사라진다 (사후 가시성은 Prometheus/AM UI에 보존).
- K8s 인프라 및 카나리(`scope=meta`)는 정책 변경 없음 — 알림 파이프라인 자체 모니터링은 24/7 유지.

**Costs**

- **`type=service`의 critical 누락 가능성 (의도적 수용).** AlertManager `active_time_intervals`는 음소거된 알림을 큐에 쌓아두지 않는다. 야간 02시에 `proxy01` 다운 → 04시에 자동 복구 → Teams 카드 0회 발송, resolve 카드도 0회 (한 번도 firing을 발송한 적이 없으므로 resolve도 발송되지 않음). 운영자는 다음 출근 시 Prometheus/Grafana로만 사후 인지 가능하다. 이 trade-off는 grilling round 2(2026-05-27)에서 명시적으로 확인됐다 — "서비스 호스트의 야간 자율 복구는 허용한다".
- **공휴일 미고려.** 평일 정의에는 한국 공휴일이 포함되지 않는다. 평일 공휴일(예: 어린이날, 광복절)에는 정상 출근일처럼 Teams 알림이 발송된다. 음력 기반 공휴일(설날·추석·부처님오신날)과 대체공휴일은 매년 양력 날짜가 변동되어 `mute_time_intervals`만으로 정적 표현이 불가능하다. follow-up 자동화(공공데이터 OpenAPI 호출 → Ansible 렌더링)는 별도 PR에서 다룬다.
- **`scope` 라벨 컨벤션 강제 부담.** 새 외부 rule을 추가하면서 `scope: external` 라벨을 빠뜨리면 K8s 폴백 경로로 흘러 24/7 발송된다. CONTEXT.md에 컨벤션을 명시했고, 머지 전 PR 리뷰에서 발견 가능한 수준.
- **외부 알림 트래픽 baseline 변동.** 음소거 기간 동안 발생한 외부 rule의 firing/resolve가 AM `notifications_total` 카운터에 거의 잡히지 않게 된다. AlertmanagerWebhookFailing 카나리는 `notifications_failed_total`만 보므로 영향 없음. 단, "야간엔 외부 fleet 알림 트래픽이 정상 ≈ 0"이라는 새 baseline을 운영팀이 인지해야 한다.

## Rollback

`monitoring-alertmanager.yml`의 이전 형태(PR #1)는 한 파일 변경이라 단순 git revert로 충분하다:

```
git revert <이 PR의 머지 커밋>
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml
```

playbook의 `Render alertmanager-config Secret` 태스크가 기존 24/7 라우팅 yaml로 Secret을 다시 렌더링하고 AlertManager가 새 config로 reload된다. CONTEXT.md / ADR-0002 자체 보정은 정책상 함께 revert해도 무방하나, "왜 ADR-0002 결정을 되돌렸는지" ADR-0003 형태로 후속 기록을 남기는 편이 미래 독자에게 친절하다.

## Alternatives considered

- **`type=service`도 critical은 24/7 유지, warning만 office hour 음소거.** 산업 표준 패턴. grilling round 2에서 명시적으로 제시·거부됨. 사용자 결정: "메시지 그대로 critical도 office hour". 새벽 자동복구 critical 누락을 수용함.
- **`type=infra` / `test*`도 부분 허용** (예: critical만 24/7). 거부. VM 호스트가 죽으면 그 위 게스트가 다 죽지만 PR #1 baseline 측정상 false-positive 빈도가 높아 시그널 가치가 낮다는 판단. 향후 노이즈 정리 후 재검토 가능.
- **공공데이터 OpenAPI 기반 한국 공휴일 자동 mute.** round 3에서 제시·연기. 첫 적용 PR은 단순함 우선, follow-up.
- **Workflow flow 측에서 시간대 필터.** round 1에서 제시. AlertManager 측이 발송은 하되 Flow가 Teams 게시만 보류. 누락 위험은 낮으나 (firing 이력은 AM에 남고 Flow 실행 로그에도 남음) 로직 분산 → 트레이드오프 가시성 저하. 거부.
- **`scope` 대신 `job=external-node-exporter` 매처.** 자동 부여로 누락 위험 0. round 4에서 제시·거부. 의미 표현이 약하고 향후 추가 외부 scrape job 시 매처 수정 필요.

## Related

- **ADR-0001** — 어댑터 폐기, Workflow 직접 path 결정. 본 ADR의 라우팅 변경은 ADR-0001의 receivers/webhook 구조를 그대로 사용한다.
- **PR #1** — 외부 fleet 모니터링 도입. 본 라우팅 변경의 baseline.
- **`monitoring-rules.yml`** — `scope: external` 라벨 컨벤션의 단일 진실 공급원. 새 외부 rule 추가 시 `scope` 라벨 필수.
- **`monitoring-alertmanager.yml`** — 본 라우팅 트리의 실제 yaml.
