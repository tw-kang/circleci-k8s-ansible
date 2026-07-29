# ADR-0007 — self-hosted runner pool 40/10 분할 (full run lane / rerun lane)

**Status**: Accepted (2026-07-29). [ADR-0005](0005-build-transport-and-mount-ownership.md)의
"rerun 전용 lane 분리 기각"을 전제 변경으로 재결정한다. [ADR-0006](0006-plugin-free-split-and-custom-rerun.md)과
세트이며 구현 스펙은 CUBRIDQA-1471이다.

## Context

self-hosted slot 50은 플랜(prepaid) 하드 한도다(ADR-0005에서 확인). 단일 풀에서는 full run
50-way가 풀을 가득 채우는 동안 failed-only rerun([ADR-0006](0006-plugin-free-split-and-custom-rerun.md))과
develop 머지 전용 download-build(ADR-0005)가 뒤에 줄을 선다 — rerun의 존재 이유가 "빠른
재확인"이므로 수십 분 대기는 목적 자체를 훼손한다.

ADR-0005는 lane 분리를 기각했었는데, 근거는 "네이티브 rerun은 같은 job 정의(resource
class·parallelism 고정)로 재실행되어 lane 라우팅이 구조적으로 불가"였다. ADR-0006이
네이티브 rerun을 폐기하고 **파라미터로 resource class를 받는 별도 파이프라인**으로
대체하면서 이 전제가 사라졌다.

container-agent helm chart(101.x)의 `agent.maxConcurrentTasks`는 설치(release) 단위
전역값이고 resource class별 한도는 존재하지 않음을 확인했다 — 분할은 release 분리로만
가능하다.

## Decision

1. CircleCI resource class **`cubrid/rerun`** 을 신설한다. 용도: failed-only
   rerun(parallelism 10) + develop 머지 전용 download-build.
2. **별도 k8s namespace에 두 번째 container-agent helm release**를 배포한다
   (`maxConcurrentTasks: 10`, task pod spec은 기존과 동일 — testcases overlay 포함).
   기존 release(`cubrid/ramdisk`)는 `maxConcurrentTasks: 50 → 40`.
3. full run(test_shell)의 parallelism을 **50 → 40** 으로 낮춰 40-lane을 한 웨이브로
   정확히 채운다(50이면 40+10 두 웨이브 큐잉).

## 검토한 대안 (Considered options)

- **resource class별 동시실행 한도** — chart가 지원하지 않음. 기각.
- **같은 namespace에 release 추가** — configmap 등 리소스 이름 충돌을 fullnameOverride로
  피해야 하고 GC·모니터링 경계가 흐려짐. 별도 namespace가 명확해 기각.
- **45/5 분할** — full run 손실은 10%로 줄지만 rerun(p=10)이 두 웨이브가 되고 develop
  download-build와 겹치면 대기 발생. 응답성 우선으로 40/10 채택.
- **분할 없이 단일 풀 큐잉** — 구성은 단순하나 rerun이 full run 뒤에서 최대 수십 분 대기.
  기각.

## Consequences

- full run 벽시계 시간 ~25% 증가를 수용한다(케이스가 40개 노드로 재분배). ADR-0005가
  "lane 분할은 full-run wall-clock만 악화"라 했던 비용을 rerun 응답성과 맞바꾼 것이다.
- 40 + 10 = 50으로 플랜 한도와 정확히 일치해야 한다 — 어느 한쪽 상향은 반드시 다른 쪽
  하향과 동시에.
- [ADR-0003](0003-shell-controller-worker-runner.md)(controller/worker, 파이프라인당 task
  1개) 착수 시 task 수 회계가 근본적으로 바뀌므로 본 분할은 **재평가 대상**이다(그 시점엔
  maxConcurrentTasks가 곧 동시 파이프라인 수가 된다).
- helm release가 2개가 되므로 배포·업그레이드 시 두 release를 함께 관리해야 한다
  (chart 버전 불일치 방지).
