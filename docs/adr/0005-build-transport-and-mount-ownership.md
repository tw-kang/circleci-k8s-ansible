# ADR-0005 — 빌드 전송 재설계: 병렬 download-build + CUBRID mount 소유권을 config.yml step으로 이관

**Status**: Proposed (2026-07-29). [ADR-0004](0004-release-debug-parallel-build-debug-test.md)의 2단계(dual-build GlusterFS 업로드)를 대체한다. cubrid `.circleci/config.yml` 변경과 세트이며, 배포 순서는 본 repo(postStart v2)가 먼저다.

## Context

현재 계약(ADR-0004에 명시): 본 repo의 `circleci-values.yaml.j2` postStart가
`builds/$CIRCLE_SHA1/CUBRID` 경로를 하드코딩하고, `CIRCLE_JOB = "download-build"`만 특별
분기하며, 빌드 출현을 최대 300초 폴링한 뒤 `/home/CUBRID`에 overlay 마운트한다. 즉 **경로
스킴과 job명이 config.yml과 본 repo 사이의 하드 계약**이다.

문제 (grilling 2026-07-29):

1. `download-build` job이 self-hosted slot 1개를 점유한다. 플랜(prepaid) 한도 50은 영업
   문의로도 상향 불가한 **하드 한도**라 slot이 귀하다.
2. ADR-0004 2단계(release+debug 동시 보관)는 경로 세그먼트 도입 때문에 **두 repo를 동시에**
   바꿔야 하는 교차-repo 변경이었다.
3. develop 머지 빌드의 GlusterFS 보존(에이전트 소비 목적)이 미구현 상태다. 요구사항은
   "파이프라인이 주도하는, 머지 커밋당 결정적(deterministic) 전송 — 단 테스트는 실행하지 않음".

제약(검증된 사실): 클러스터는 사설 IP만 있고 ingress/LB가 없어 **inbound 경로가 전무**하다.
따라서 GlusterFS에 쓸 수 있는 주체는 클러스터 내부에서 도는 것(self-hosted pod, K8s 워크로드)
뿐이고, 전송은 반드시 outbound pull이다. "download-build를 cloud runner로 이전"은 문자
그대로는 불가능하다.

## Decision

1. **PR 경로 — download-build 유지(requires 포함) + 신규 레이아웃/sentinel** *(재결정 이력:
   최초 안 "leader pod 다운로드" 기각(2026-07-29) → "병렬 시작(requires 제거)" 채택 →
   2026-07-30 보수 회귀 — Considered options 참조)*: `download-build` job과 `test_shell`의
   `requires` 선행 관계는 **현행대로 유지**한다. download-build는 debug 빌드를 신규 레이아웃
   (`builds/<SHA>/debug/CUBRID`)에 저장하고 **`.complete` sentinel**로 완료를 표시한다.
   test_shell 각 pod는 job step에서 sentinel을 확인한 뒤 overlay 마운트한다 — requires 덕에
   통상 즉시 통과하며, sentinel 확인은 rerun 동시 실행(tar 추출 중 race) 대비 안전벨트다.
   빈 split을 받은 pod는 **빌드 확인 전에** 조기 halt한다(rerun 발자국 최소화).
2. **develop 머지 경로**: develop 워크플로는
   build + build_debug 둘 다 패키징하고, `download-build`가 release·debug를 모두 GlusterFS에
   저장한다. 테스트는 실행하지 않는다.
   ~~download-build의 task 이미지는 작은 이미지로 지정한다~~ → **기각(2026-07-30, 아래 참조)**.
3. **레이아웃 통일**: `builds/<SHA>/{release,debug}/CUBRID` 단일 트리. PR은 debug만,
   develop 머지는 둘 다. GC CronJob 로직은 불변(builds/ 1-depth mtime), retention은
   `glusterfs_cleanup_retention_days: 7`로 연장.
4. **postStart v2 — mount 소유권 이관**: 본 repo postStart에서 CUBRID 경로 지식을 제거한다.
   v2 동작 = "구 flat 경로 `builds/<SHA>/CUBRID`가 존재하면 mount(구 config rerun 호환),
   없으면 즉시 exit 0". 대기 루프(300s)와 `CIRCLE_JOB=download-build` job명 분기는 삭제한다
   (빌드가 없으면 어차피 exit 0이므로 분기가 불필요해짐). 신규 레이아웃의 대기·마운트는
   config.yml step이 수행한다. 과도기 이후 postStart에는 testcases overlay만 남는다.
5. **배포 순서**: (1) 본 repo postStart v2 + retention 7일 → (2) cubrid config.yml 전환.
   v2는 구·신 config 양쪽과 호환되므로 한쪽만 배포된 상태에서도 깨지지 않는다.

## 검토한 대안 (Considered options)

- **leader pod 다운로드(download-build 제거)** — `test_shell`의 node 0이 step에서 직접
  다운로드해 slot 1개를 회수하는 안. 최초 채택했다가 같은 날(2026-07-29) 재결정으로 기각:
  (1) 50개 pod에 걸친 leader 선출·조율이 단일 job보다 복잡하고 리스크가 크며, (2) 전송
  실패가 50개 pod에 혼재되어 격리·가시성이 나쁘고(단일 job이면 빨간불 1개), (3) ADR-0006의
  rerun 빌드 수급, ADR-0007의 lane 배치, ADR-0003의 controller/worker placement 전제가 모두
  download-build job의 존재를 전제로 하는 편이 자연스럽고, (4) slot 1개(1/50) 회수는 그
  비용에 값하지 않는다. 병렬 시작(requires 제거)으로 직렬 지연 제거 효과는 동일하게 얻는다.
- **병렬 시작(requires 제거)** — download-build와 test_shell을 동시 시작하고 step의 sentinel
  대기를 checkout/split과 겹쳐 벽시계 1~3분을 은폐하는 안. 채택했다가 2026-07-30 기각:
  test step의 `no_output_timeout`이 45분으로 길어, download-build 실패·지연 시 50개 pod가
  sentinel 대기로 slot을 장시간 점유할 수 있다. 이득(1~3분)이 이 꼬리 리스크에 값하지 않아
  requires 유지로 회귀. step의 sentinel 확인 자체는 안전벨트로 존치.
- **download-build를 작은 task 이미지로 교체** — "단순한 전송 작업에 291MB 테스트 이미지는
  과하다"는 동기로 채택했다가 **2026-07-30 실측으로 기각**: 워커 노드에는
  `cubridci/cubridci:test_shell`(291.5MB)이 test_shell 때문에 **이미 캐시**되어 있고
  `imagePullPolicy: Always`는 digest 동일 시 manifest 확인만 하므로 **절감할 대역폭·시간이
  사실상 없다**(같은 job의 실소요 13분은 전부 아티팩트 다운로드 = ISP 제한 회선 몫).
  반대로 비용은 실재한다 — task pod의 postStart(러너 values 소유)가 `/bin/sh -l`·`mount`·
  `grep`·`cut`을 요구하고 스텝 기본 셸이 bash라, alpine은 `shell: /bin/sh` 전환 + curl→wget
  + busybox `mv -T` 미지원 대응이 필요하고 distroless·chainguard 계열은 셸이 없어 postStart가
  즉시 실패한다. config.yml 이미지 override 자체는 canary(#141878/#141879)로 검증됐으므로,
  **재개 조건**은 "postStart 계약이 사라지거나(ADR-0003 전환 후) 전송 job이 노드에 없는
  이미지를 쓰게 될 때"다.
- **in-cluster reconciler** — 상주 Deployment가 test pod의 `circle-sha1` label을 watch(PR)하고
  develop을 폴링(머지)해 빌드를 당겨옴. config.yml 변경이 최소지만, 실패가 클러스터 로그에
  숨고(50 pod가 postStart 300s 후 일괄 실패로 발현) SHA→아티팩트 역해석 API가 추가로 필요하며
  상주 컴포넌트 +1. 기각.
- **CronJob(develop 폴링)** — 커서 기반 파이프라인 열거로 누락 없이 저장은 가능하나 본질적으로
  비동기이고 실패가 커밋 상태에 보이지 않음. "파이프라인 주도·커밋당 결정적" 요구로 기각.
- **cloud job + inbound(kubectl/VPN/터널)** — inbound 부재. 신설은 보안 검토가 필요한 별도
  프로젝트라 기각.
- **rerun 전용 lane 분리(작은 resource class)** — 네이티브 "rerun failed tests"는 같은 job
  정의(resource class·parallelism 고정)로 재실행되므로 lane 라우팅이 구조적으로 불가. 커스텀
  rerun 경로는 [ADR-0003](0003-shell-controller-worker-runner.md) 착수 시 폐기 대상이고, 총합
  50 고정이라 lane 분할은 full-run wall-clock만 악화. 기각 — 줄서기의 근본 해결은 ADR-0003
  (controller/worker, 파이프라인당 task 1개)이며 게이트(migrate-jdk8 머지, PR #764)는 이미
  열렸다.
  **(재결정 2026-07-29: 기각 전제였던 "네이티브 rerun 유지"가 [ADR-0006](0006-plugin-free-split-and-custom-rerun.md)에서 폐기되면서, lane 분리는 [ADR-0007](0007-runner-pool-partition.md)로, 커스텀 rerun은 ADR-0006으로 채택됨 — CUBRIDQA-1471)**

## Consequences

- PR 경로의 job 구조(requires 직렬)는 현행 유지 — 직렬 지연(스핀업+다운로드 수 분)은 수용.
  slot은 PR당 1개를 계속 쓴다 — lane 배치는 [ADR-0007](0007-runner-pool-partition.md)의
  40/10 분할에서 재검토(ADR-0007의 "develop 머지 전용 download-build" 문구는 본 재결정으로
  낡음 — PR download-build도 존재).
- 경로 스킴 지식이 config.yml 한 곳에 모여 **ADR-0004 2단계의 교차-repo 커플링이 해소**된다.
  이후 레이아웃 변경은 cubrid repo 단독 변경이다.
- develop 머지마다 slot 1개 × 수 분 점유(수용), 전송 실패는 develop 커밋 상태에 빨간 표시로
  가시화.
- `.complete` sentinel이 기존의 "디렉토리 존재 체크 vs tar 추출 중" race(rerun 동시 실행 시)를
  제거한다. 소비자는 디렉토리가 아닌 sentinel을 기준으로 대기해야 한다.
- ADR-0003과 정합적: cubrid-testtools `shell-k8s-migration-placement.md`의 "download-build가
  builds/$SHA를 채운다" 전제가 그대로 유지된다(경로만 mode 세그먼트 포함으로 갱신하면 됨).
- retention 7일 + develop dual-build로 builds/ 사용량 증가(워커 디스크 여유 대비 미미).
  **실측(2026-07-31 예행연습):** 커밋당 release+debug 합계 **1.6GB**, 전송 소요 **20~30분**
  (모드당 ~83MB 다운로드 + GlusterFS FUSE 위 tar 해제가 지배적). PR 경로는 debug만이라 절반.
- **검증 1순위**: (1) container runner에서 config.yml executor image가 values의 image를
  override하는지 카나리 job으로 확인 — download-build "작은 이미지"의 전제.
  **→ 확인됨(2026-07-30, canary #141878/#141879, cubrid/staging 전용 release):** config.yml
  이미지(ubuntu:24.04)가 values 이미지를 override했고, postStart v2의 무빌드 즉시 기동·legacy
  flat 자동 마운트·작은 이미지의 GlusterFS 읽기/쓰기 모두 green. 단 **작은 이미지는 기본
  유저가 root여야 한다** — cimg/* 계열(circleci 유저)은 postStart의 overlay mount가 실패한다.
  (override 메커니즘은 이렇게 확보됐으나 **작은 이미지 채택 자체는 기각** — Considered options
  참조. 이 검증 결과는 재개 시 재사용한다.)
  (2) postStart v2 배포 후 구 config rerun(flat 레이아웃)이 정상 마운트되는지 확인
  **→ 확인됨(2026-07-30):** stage 2 배포 후 첫 자연 파이프라인 50 pod 전원
  FailedPostStartHook 0건 완주.
  (3) **step 컨텍스트 overlay mount 실측(2026-07-30, 라이브 task pod에서 exec 실험):**
  postStart와 step은 같은 privileged 컨테이너의 root 프로세스라 권한이 동일하며, emptyDir
  볼륨(`/build-rw`, xfs) 위에서 mount/umount 성공. 단 **upperdir/workdir가 컨테이너
  rootfs(overlayfs) 위면 커널이 거부**(overlay-on-overlay 불가) — step mount는 반드시
  emptyDir 볼륨을 사용해야 한다(config.yml step 구현 시 하드 제약).
- 에이전트 소비 계약(SHA 해석, readOnly, walk-back)은 circleci-refactor 세션의
  `design-merge-build-to-glusterfs.md` §5를 승계하되 경로가 `builds/<SHA>/release/CUBRID` 등
  mode 세그먼트 포함으로 바뀐다.
