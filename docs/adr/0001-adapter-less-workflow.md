# ADR-0001 — AlertManager → Teams 어댑터 제거; AlertManager를 Power Automate Workflow로 직접 연결

**Status**: Accepted (2026-05-15, round 6 — 2026-05-11 round 1-5의 '어댑터 유지' 결정을 대체)

## Context

기존 아키텍처에서는 AlertManager 웹훅을 클러스터 내 Python 어댑터(`roles/alertmanager-teams-adapter/`, 234줄 포워더 + Deployment / Service / ConfigMap / Secret)로 전달했다. 이 어댑터는 AM 페이로드를 Power Automate의 `Post adaptive card in chat or channel` 액션이 요구하는 AdaptiveCard 봉투 형식으로 변환한 뒤 Workflow 트리거로 포워딩했다.

해당 어댑터는 PR #1(round 1 + round 2 adversarial grill, 2026-05-12)에서 인라인 리뷰 지적 27건을 받았다. 지적 항목은 OOM, SIGTERM, NetworkPolicy, PDB 부재, 이미지 핀, systemd 하드닝, 임시 Secret 하이진 누수 등이다. Round 1-5(2026-05-11)에서는 OSS 포워더(prom2teams, prometheus-msteams)와 Power Automate flow-only 경로를 모두 거부하고 어댑터를 유지하는 결정을 내렸다.

Round 6(2026-05-15)에서는 프로덕션 helm 릴리스에 인플레이스 URL-swap PoC를 실행했다. AM 웹훅 URL을 어댑터 Service에서 Power Automate Workflow 트리거 URL로 전환하고, 직접 구성한 flow(`triggerBody → For each alerts → Compose AdaptiveCard JSON → Post adaptive card in chat or channel`)가 서버 측 변환을 담당하게 했다. flow 구성 버그 두 건(액션이 `PostAdaptiveCardToConversation` 대신 `PostCardToConversation`으로 선택되었던 문제, `messageBody`에 `@outputs('작성')` 대신 미평가된 `outputs('Compose')` 리터럴이 들어간 문제)을 수정한 후 네 가지 통과 기준을 모두 충족했다: 카드 도착 ≤ group_wait + 5s, M365 UPN owner_email 실 Teams 멘션 알림, AdaptiveCard 렌더링 동등성(FactSet/summary/description/severity 색상), AM `Notify success`.

## Decision

어댑터 role을 완전히 제거한다. AlertManager는 원시 `{"alerts":[...]}` 페이로드를 Power Automate Workflow 트리거 URL로 직접 POST한다. flow의 `For each alerts → Compose AdaptiveCard JSON → Post adaptive card in chat or channel` 체인이 Microsoft 서버 측에서 모든 변환을 처리한다.

bearer Workflow URL은 플레이북의 `Render alertmanager-config Secret` 태스크(`no_log: true`)가 생성하는 외부 Kubernetes Secret(`monitoring` ns의 `alertmanager-config`)에 보관된다. kube-prometheus-stack 차트는 `alertmanagerSpec.configSecret`을 통해 이 Secret을 참조하므로, URL은 helm 릴리스 values dict에 절대 기록되지 않는다.

flow JSON 정의는 `docs/flow-definitions/`에 커밋하여 변경이 PR 리뷰를 거치도록 한다. 이 규율 없이 Portal 측 편집이 이루어지면 AdaptiveCard 렌더링이 AM 측 오류 없이 조용히 退행할 수 있다(AM은 하위 액션 성공 여부와 무관하게 트리거에서 HTTP 200만 수신한다).

## Consequences

**Benefits**
- PR #1 round 1+2 인라인 지적 27건 중 약 20건이 자동 해소됨(어댑터 코드 제거).
- 운영 범위 축소: 유지 관리가 필요한 Python 파드 없음. replicas=1 SPOF, 이미지 핀, systemd 하드닝, 버스트 시 OOM, NetworkPolicy 인증, PDB 부재 우려 — 모두 무효화됨.
- AdaptiveCard 렌더링의 단일 진실 공급원이 `docs/flow-definitions/`의 flow JSON으로 이동함.
- `helm get values kube-prometheus-stack`에서 bearer URL이 더 이상 노출되지 않음.

**Costs**
- **Secret 보호는 부분적이며 일반적이지 않다.** URL이 정리된 것은 `helm get values`뿐이다. 다른 경로는 동등하거나 더 넓다:
  - `kubectl get secret alertmanager-config -o yaml`은 base64를 반환한다(이전과 동일한 수준)
  - `kubectl exec alertmanager-... -c alertmanager -- cat /etc/alertmanager/config/alertmanager.yaml`은 AM 파드 exec 권한이 있는 누구에게나 URL 평문을 반환한다
  - 새 경로는 접근 가능 대상을 "어댑터 파드 exec"에서 "AM 파드 exec"으로 확장한다 — 잠재적으로 더 넓은 모니터링 스택 관리자 집합이 해당됨
  따라서 이 ADR의 가치는 *어댑터 복잡도 제거*이지 일반적인 시크릿 하이진이 아니다. `helm get values` 정리는 부수적 이득으로 간주하고, 나머지는 AM 파드 exec/secret-read에 대한 K8s RBAC에 의존한다.
- **Flow 로직이 코드에 없다.** Compose 본문과 액션 파라미터가 Power Automate Portal에 존재한다. `docs/flow-definitions/`에 flow JSON 내보내기를 커밋하고 모든 flow 변경을 PR 커밋 대상으로 처리함으로써 완화한다. git 리뷰를 우회하는 Portal 편집은 AM 측 오류 없이 조용히 退행할 수 있다.
- **멘션은 M365 테넌트 내부로 한정된다.** `msteams.entities[].mentioned`는 `owner_email`이 해당 flow 테넌트 내 UPN일 때만 해석된다. Gmail / 크로스 테넌트 게스트 이메일은 `<at>...</at>` 토큰을 알림 없이 평문으로 렌더링한다. 이는 어댑터 경로의 제약과 동일하다.

## Rollback

이 PR의 `git revert`만으로는 **충분하지 않다** — vault의 `vault_teams_webhook_url` 값은 round 6 PoC sig-leak 처리 중 해당 URL이 교체·폐기되었으므로 사용 가능한 어댑터 테넌트 URL로 되돌릴 수 없다.

수동 롤백 절차:

1. Power Automate Portal: 어댑터가 포워딩할 새 Workflow 트리거 URL을 프로비저닝한다(또는 어댑터가 이미 변환한 `{type:"message",attachments:[…]}` 봉투를 수신하여 임베드된 카드를 게시하는 flow를 재구성한다).
2. `ansible-vault edit inventory/production/group_vars/all/vault.yml`에서 `vault_teams_webhook_url`을 새 URL로 업데이트한다.
3. `git revert <PR-#1-merge-commit>`(또는 이 ADR 커밋만 선택적으로 revert).
4. `ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml` — Play B가 어댑터 K8s 리소스를 재적용하고, helm upgrade가 인라인 `monitoring_alertmanager_values.config`를 복원한다.
5. 어댑터 파드 정상 여부, AM `Notify success`가 어댑터 Service로 전달되는지, Teams 카드 수신 여부를 확인한다.

어댑터 소스는 git 이력에 남아 있다(`git show c929c38`). 재도입이 필요한 경우 이력을 참고 자료로 활용하되, 문자 그대로 revert하지 않는다 — round 1+2 인라인 지적(OOM, SIGTERM, 하드닝 등)을 재배포 전에 반드시 해소해야 한다.

## One-time cleanup after rollout

어댑터 K8s 리소스는 `helm upgrade`로 정리되지 않는다(차트가 아닌 ansible role이 직접 적용했기 때문이다). 머지 후 첫 번째 `deploy-monitoring.yml` 실행이 끝나면 아래 명령을 한 번 실행한다:

```
kubectl -n monitoring delete deploy,svc,cm,secret -l app.kubernetes.io/name=alertmanager-teams-adapter
```

이 단계를 생략하면 네임스페이스에 수 MiB 메모리를 점유하는 유휴 Python 파드가 남아 `kubectl get all` 출력에 노이즈를 유발한다.

## Alternatives considered

- **prom2teams** (Python/Flask, idealista, 288★) — round 1-5 거부. msteams.entities 멘션 미지원 + Helm 차트가 웹훅 URL을 평문 ConfigMap에 기록(양쪽 경로보다 Secret 하이진이 더 나쁨).
- **prometheus-msteams** (Go, 567★) — round 1-5 거부. 엄격한 구조체 `MsTeams` JSON 역직렬화가 `entities` 필드를 조용히 제거하므로 `@mention`이 동작하지 않음.
- **어댑터 유지 후 round 1+2 인라인 지적 27건 전부 수정** — 실행 가능하나 이 접근 방식에서 약 20건이 사라진다. 이 ADR의 ~1일 대비 집중 작업 ~1-2주가 소요될 것으로 추정.
- **URL을 위한 External-secrets-operator + sealed-secrets** — 일부 비 helm 경로를 해소하겠지만 Secret 하나를 위해 오퍼레이터 의존성을 추가하게 된다. 과도한 엔지니어링으로 거부.
- **Smoke-test canary alert** — grill 1에서 조용한 flow 退행을 감지하는 방법으로 제안됨. 연기됨(`monitoring-rules.yml`에 severity=critical, repeat_interval=6h인 `WorkflowCanary` 규칙 추가 필요). 현장에서 flow 측 退행이 관찰되면 재검토한다.

## Related

- **PR #1** (`external-monitoring` 브랜치) — 최초 어댑터 도입 + round 1+2 인라인 리뷰(27건 지적).
- **Memory `project_msteams_adapter_decision.md`** — round 6 결정(이 ADR) 및 대체된 round 1-5 이력.
- **`docs/flow-definitions/`** (후속 커밋으로 추가) — Power Automate flow JSON 내보내기. Portal에서 flow를 변경할 때마다 업데이트한다.
