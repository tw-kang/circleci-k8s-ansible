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

### 실측 보강 (2026-07-30, CUBRIDQA-1475 검증 중 규명) — 본 ADR의 가치를 상향

CircleCI self-hosted task 디스패치를 실측한 결과, 단순 큐잉이 아니라 **gang scheduling +
head-of-line blocking** 이었다:

- 큐 순서는 `usage_queued_at` **FIFO**이고, `parallelism: 50` job은 **50 slot이 전부 빌 때까지
  대기했다가 한 번에 전부** 점유한다(부분 시작 없음).
- 그 대기 동안 **뒤에 줄 선 runner 작업 전부가 함께 멈춘다** — 실측: 빈 slot 49개 상태에서
  agent claim이 `no work`를 받고 2분짜리 `download-build` 5건이 동반 정지. 큐 선두의 50-way
  job이 pool 완전 배수를 기다리는 것이 원인(서버가 의도적으로 offer하지 않음).
- 결과적으로 shell 파이프라인 1건이 pool을 ~30–50분 독점하고 그 뒤 모든 파이프라인의 **작은
  job까지 직렬화**된다. 같은 날 오전의 장시간 정체도 이 메커니즘으로 설명된다.

함의:

1. lane 분리의 이득은 "rerun 응답성"보다 크다 — 별도 release/resource class의 작은 lane은
   full run의 head-of-line blocking에서 **구조적으로 면역**이 된다.
2. **미결 항목**: 본 ADR은 작은 lane 용도를 "rerun + develop 전용 download-build"로 적었으나,
   PR 경로의 `download-build`(2분, parallelism 1)도 현재는 full run 대기에 갇힌다. 구현 시
   PR download-build를 작은 lane으로 보낼지 재검토할 것.
3. [ADR-0003](0003-shell-controller-worker-runner.md)(controller/worker, 파이프라인당 task 1개)은
   gang scheduling 자체를 소멸시켜 이 병리를 근본 제거한다 — slot 회계 절감보다 이 효과가 크다.

### develop 전송 job 표본 (2026-08-03 집계, n=7)

CUBRIDQA-1476이 도입한 `store-build-develop`(parallelism 1)은 develop 머지마다 정확히 1건씩
돌아, 위 2번 미결 항목("작은 job을 작은 lane으로")의 비용을 반복 측정할 수 있는 표본이 됐다.
2026-07-31 첫 머지부터 08-03까지 7건 전부 success:

| build | rev | slot 대기 | 실행 |
|---|---|---|---|
| 142494 | `ac9bd45b4` | 67.8분 | 24.4분 |
| 142534 | `05a6b066f` | 18.3분 | 29.2분 |
| 142549 | `d7ff1bd15` | 9.9분 | 26.3분 |
| 142572 | `fa448de5a` | **114.5분** | 22.2분 |
| 142760 | `0888ccb94` | 26.2분 | 25.2분 |
| 142825 | `79e2a5196` | 22.0분 | 32.2분 |
| 142830 | `a74fdf2e9` | 14.8분 | 32.4분 |
| **평균** | | **39.1분** | **27.4분** |

측정 기준: slot 대기 = v1.1 API의 `usage_queued_at → start_time`, 즉 `requires`가 모두 끝나
슬롯을 기다리기 시작한 시점부터 실제 시작까지 — gang scheduling으로 잃는 시간 그 자체다.
(`queued_at`은 디스패치 직전에 찍혀 start와 0.2~0.5분 차이뿐이라 대기 측정에 쓸 수 없다.
초판에 적었던 "75.6분"은 파이프라인 생성 시각부터 잰 값이라 build 2건의 소요 ~7.8분이
포함돼 있었다.)

읽는 법: parallelism 1짜리 작은 job이 **실행시간(27.4분)보다 긴 시간(39.1분)을 대기**하고,
최악에는 실행의 5배(114.5분)를 기다린다. 작은 lane에 두면 이 대기는 구조적으로 0에 가까워진다.

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
- **작은 lane 안에서 develop 전송과 rerun이 서로를 막을 수 있다(구현 시 결정 필요).** 위 표본
  기준 develop 전송은 slot 1개를 **27.4분** 물고 있고, rerun은 p=10으로 lane을 정확히 채운다.
  전송이 먼저 들어가면 rerun이 최대 ~27분 밀리고, rerun이 먼저면 전송이 rerun 시간만큼 밀린다
  (전송은 지연에 둔감하니 후자는 무해). 본 ADR을 쓸 당시엔 전송을 "2분짜리 작은 job"으로
  가정했는데 dual-build가 되면서 틀렸다 — 39/11 분할이나 lane 내 우선순위가 필요한지
  CUBRIDQA-1471에서 판단할 것.
- [ADR-0003](0003-shell-controller-worker-runner.md)(controller/worker, 파이프라인당 task
  1개) 착수 시 task 수 회계가 근본적으로 바뀌므로 본 분할은 **재평가 대상**이다(그 시점엔
  maxConcurrentTasks가 곧 동시 파이프라인 수가 된다).
- helm release가 2개가 되므로 배포·업그레이드 시 두 release를 함께 관리해야 한다
  (chart 버전 불일치 방지).
