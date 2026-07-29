# ADR-0004 — release/debug 병렬 빌드 + debug 빌드 테스트, 향후 dual-build GlusterFS 업로드

**Status**: Proposed (2026-07-07). cubrid PR [#7248](https://github.com/CUBRID/cubrid/pull/7248) (CUBRIDQA-1412)이 `cubrid/.circleci/config.yml`에서 1단계를 구현. **2단계는 [ADR-0005](0005-build-transport-and-mount-ownership.md)(2026-07-29)로 대체됨** — 경로 스킴·postStart 수정 방향이 "mount 소유권의 config.yml step 이관"으로 재설계되었다.

## Context

`cubrid/.circleci/config.yml`은 setup workflow가 continuation config(`continue.yml`)를 동적으로 생성하는 구조다. 종전에는 `build` job 하나(release)만 두고, PR 트리거 시 그 아티팩트로 sql/medium/shell 테스트를 돌렸다.

CUBRIDQA-1412 요구: **빌드는 release·debug 두 모드를 모두 통과해야 하고(둘 중 하나라도 실패하면 테스트 금지), 테스트는 debug 빌드로만 수행**한다. debug 빌드 회귀(assert abort 등)를 CI에서 상시 잡기 위함이다.

본 repo가 소유한 인프라 계약(검증된 사실, `roles/circleci/templates/circleci-values.yaml.j2:110`, `..._with_glusterfs:172`):
- self-hosted 러너 pod의 postStart가 `BUILD_DIR="/home/build-cache/builds/$CIRCLE_SHA1"`를 하드코딩하고 `$BUILD_DIR/CUBRID`를 `/home/CUBRID`에 overlay 마운트한다. 즉 **SHA1당 CUBRID 디렉토리는 정확히 하나**만 존재 가능하다.
- postStart는 `CIRCLE_JOB = "download-build"` job만 특별 분기(마운트 생략)하고, 그 외 모든 job에는 위 경로를 마운트한다. 따라서 **job명 `download-build`와 경로 `builds/$SHA1/CUBRID`는 config.yml과 본 repo 사이의 하드 계약**이다. build job 이름(`build`/`build_debug`)은 러너가 참조하지 않는다.

## Decision

### 1단계 (cubrid PR #7248, config.yml만 변경 — 본 repo 무변경)

- `build`(release) job = **컴파일 게이트**: release 빌드 + 로그 수집만, 아티팩트 생성/persist 없음.
- `build_debug` job 신설: `-m debug` 빌드 → 아티팩트 패키징 + workspace에 `BUILD_NUM_DEBUG` persist. **테스트 job이 내려받는 유일한 빌드.**
- 두 job 사이에 `requires` 없음 → **동시 병렬 시작**(CircleCI: requires 없는 job은 concurrent). `test_medium`/`test_sql`/`download-build`는 `requires: [build, build_debug]` → 두 빌드 모두 성공해야 진입, 실행 바이너리는 debug.
- ccache 키 분리: release=`ccache-global-v1`(develop 웜캐시 재사용), debug=`ccache-debug-v1`.
- **인프라 무변경으로 성립**: `download-build`가 debug 빌드를 기존 경로 `builds/$SHA1/CUBRID`에 그대로 올리므로 러너 postStart는 손대지 않는다. develop 머지(default trigger) 시엔 두 빌드 모두 로그 후 `step halt` — 아티팩트/업로드 없음(오늘 develop 동작과 동일 + debug 게이트 추가).

### 2단계 (별도 PR — develop 머지 시 release·debug 둘 다 GlusterFS 업로드)

1단계는 debug 단일 업로드라 SHA1당 CUBRID 하나 가정을 지킨다. 2단계에서 **두 빌드를 동시에 보관**하려면 아래 3개 지점을 함께 바꿔야 한다(이 중 2·3이 본 repo/트리거 소유):

1. **경로에 빌드 모드 세그먼트 도입** (`cubrid/.circleci/config.yml`): `builds/$SHA1/{release,debug}/CUBRID`. `download-build-to-glusterfs` 명령의 `BUILD_DIR`와 업로드 대상 수정.
2. **러너 postStart 수정** (본 repo `circleci-values.yaml.j2:110`, `_with_glusterfs:172`): `$BUILD_DIR/CUBRID` 단일 마운트 가정을 해제하고, 소비 job이 어느 모드를 마운트할지(테스트=debug) 선택하도록 `builds/$SHA1/debug/CUBRID` 등으로 경로 확장. **1단계 경로(`builds/$SHA1/CUBRID`)와 하위호환 유지 여부**를 결정해야 함(과도기).
3. **default-trigger `step halt` 제거** (`config.yml` build·build_debug): 두 빌드 모두 패키징 후 GlusterFS 업로드하도록. 업로드에 필요한 `BUILD_NUM_RELEASE`도 release job에서 persist(1단계에서 debug만 `BUILD_NUM_DEBUG`로 분리해 둔 것과 대칭 — workspace path 충돌 방지).

### 본 repo가 1단계에서 소유하지 않는 것 (경계)

- config.yml의 job/워크플로 구조 → **cubrid repo** (`origin/develop`).
- 1단계는 러너·RBAC·노드·저장소 계약을 **그대로 재사용**하며 본 repo 파일을 바꾸지 않는다.

## Consequences

- 1단계는 인프라 무변경으로 즉시 성립하며, debug 컴파일 게이트가 PR·develop 머지 양쪽에 적용된다. 병렬 실행이라 벽시계 비용은 거의 불변이고 러너/빌드 슬롯만 2개로 는다.
- `BUILD_NUM` → `BUILD_NUM_DEBUG` 개명은 2단계에서 `BUILD_NUM_RELEASE`가 추가될 때 workspace persist 경로 충돌(동일 파일명 병렬 persist는 CircleCI 오류)을 사전 차단한다.
- 2단계의 경로 세그먼트 도입은 **config.yml과 본 repo postStart를 동시에** 바꿔야 하는 교차-repo 변경이다. 한쪽만 머지되면 test_shell이 빌드를 못 찾아 파이프라인이 깨지므로, **배포 순서(인프라 먼저 하위호환 경로 지원 → config 전환)** 를 PR에서 조율해야 한다.
