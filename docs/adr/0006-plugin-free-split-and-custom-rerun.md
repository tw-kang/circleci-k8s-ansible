# ADR-0006 — plugin 없는 테스트 분배 + 코멘트 트리거 failed-only rerun

**Status**: Accepted (2026-07-29). [ADR-0005](0005-build-transport-and-mount-ownership.md)의
"커스텀 rerun 경로 기각"을 전제 변경으로 재결정한다. 구현 스펙: CUBRIDQA-1471
(선행: CUBRIDQA-1470). cubrid `.circleci/config.yml` + `.github/workflows` 변경과 세트다.

## Context

ISP 회신(2026-07-29)으로 사무실 회선의 해외 인바운드 트래픽 제한이 일시 장애가 아니라
**영구 제약**임이 확정됐다(IDC가 무제한으로 잘못 설정했던 것을 정정). 이 환경에서:

1. `circleci tests run`(테스트 분배 + 네이티브 "rerun failed tests only"의 구현체)은 잡마다
   `circleci-tests-plugin-cli`(11MB)를 미국 S3에서 내려받는다. 2026-07-26~29에 50-way
   fan-out 다운로드가 agent의 고정 deadline을 구조적으로 초과해 test_shell이 전멸했고,
   한동안 split 실패가 "빈 할당"으로 오인되어 **테스트 0건을 돌리고도 초록불**(silent skip)
   이 되는 사고가 있었다.
2. 임시조치로 plugin을 이미지에 pre-install했지만(compressed/gzip 함정 포함), plugin 버전은
   CircleCI가 API로 내려주는 값이라 **버전이 오르는 순간 캐시가 무효**가 되고, 캐시
   경로·sha256 검증은 문서화되지 않은 내부 동작이라 예고 없이 깨질 수 있다.
3. 사내 미러로의 우회는 불가함을 확인했다 — plugin 다운로드 URL은 agent에 하드코딩(미러
   설정은 CircleCI Server 전용)이고 HTTPS라 DNS 우회도 성립하지 않는다.
4. plugin의 유일한 차별 기능은 "rerun failed tests only"뿐이다 — timing 기반 분배는 agent
   내장 `circleci tests split`도 동일하게 제공한다. 실패 케이스 목록은 CircleCI tests API가
   glob과 동일한 경로 형식(`file` 필드)으로 제공함을 실데이터로 검증했다.

## Decision

1. **전 suite(shell/sql/medium)의 분배를 `circleci tests split`(agent 내장)으로 전환**한다.
   외부 바이너리 다운로드가 있는 잡이 없어진다. plugin pre-install 층은 전환 안정화 후
   이미지에서 철거한다.
2. **failed-only rerun을 자체 구현**한다: PR 코멘트 `/rerun <suite>` → GitHub Actions가
   PR head SHA의 최근 실패 잡을 자동 탐색하고 가드(SHA 일치, 실패 목록 ∩ 현재 glob이 비어
   있지 않음)를 통과하면 파라미터(suite, 기준 잡번호, build 잡번호)와 함께 CircleCI
   파이프라인을 트리거한다. rerun은 tests API의 실패 목록으로 필터한 뒤 tests split으로
   분배한다. 접수·거부 모두 봇 코멘트로 안내하며, 가드 실패 시 암묵적 풀런 전환은 하지
   않는다.
3. **머지 의미론 수용**: rerun 성공이 같은 SHA·같은 status context를 갱신해 머지가 풀린다.
   보장 수준은 "모든 케이스가 해당 SHA에서 1회 이상 통과"로, 네이티브 rerun failed tests
   only와 동일하다(통과 케이스 별도 기록은 하지 않기로 결정).
4. 빌드는 재생성하지 않는다: GlusterFS(`builds/<SHA>/…` + sentinel, ADR-0005) 우선, 없으면
   파라미터로 받은 build 잡번호의 CircleCI 아티팩트에서 수급한다.

## 검토한 대안 (Considered options)

- **plugin 유지 + pre-install 상시화** — 버전 범프마다 이미지 재빌드가 필요하고 비공식
  경로·checksum 계약에 의존. 회선 제약이 영구인 이상 구조적 리스크가 남아 기각.
- **하이브리드(tests run 1차 + tests split fallback + 자체 rerun 병행)** — 재실행 경로가
  3개가 되어 복잡도 최대. 자체 rerun이 생기면 plugin의 차별 기능이 없어 기각.
- **awk 라운드로빈 fallback만 추가** — timing 분배를 잃고 rerun 문제는 그대로라 기각.
- **plugin 사내 미러** — URL 하드코딩 + TLS로 기술적으로 불가. 기각.

## Consequences

- 네이티브 "rerun failed tests only" 버튼은 실패 필터를 전달받을 tests run이 없어 **사실상
  풀런으로 동작**하게 된다. 공식 재실행 경로는 `/rerun` 코멘트로 일원화하고 안내한다.
- CUBRIDQA-1470의 네이티브 rerun 전제 user story(빈 배정 pod 조기 종료 등)는 본 결정으로
  대체된다(1470 설명에 반영 완료). 조기 halt 로직 자체는 과도기 안전장치로 유지한다.
- CircleCI 쪽 변경(plugin 버전·계약·deadline)에 영향받는 지점이 CI에서 사라진다.
- [ADR-0003](0003-shell-controller-worker-runner.md)(controller/worker) 착수 시 테스트
  분배·재실행은 controller 소유가 되므로 **본 rerun 경로는 controller 로직으로 흡수·재조정
  대상**이다. ADR-0005가 이 이유로 커스텀 rerun을 기각했으나, ADR-0003은 시기 미정이고
  plugin 리스크 제거는 즉시 필요하므로 지금 구현하고 ADR-0003 착수 시 이관한다.
- 트리거는 기존 `CIRCLECI_TOKEN` repo secret(cubridci 서비스 계정)을 재사용한다.
