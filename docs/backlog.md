# Backlog

운영 중 확인된 후속 작업 목록. 항목이 착수되면 ADR/티켓으로 승격하고 여기서 지운다.

## staging 검증 체계 일원화 — 코드 두벌 금지, canary resource class 방식

**방향 (2026-07-30 결정)**: staging 검증은 인벤토리/클러스터/코드를 두 벌로 유지하지 않는다.
**production 클러스터 위에 별도 CircleCI resource class**(예: `cubrid/staging`)를 만들어
canary lane으로 검증한다. CUBRIDQA-1474 stage 1(postStart v2를 staging class에 먼저 배포 후
canary job으로 검증)이 이 방식의 첫 적용 사례다.

**배경 (2026-07-30 확인된 사실)**:

- `inventory/staging/`은 별도 클러스터가 아니라 **production과 동일한 호스트**
  (master 192.168.1.48, worker 192.168.2.15/16)를 가리키는 stale 복사본이다.
  production `hosts.ini`조차 "Staging environment inventory" 헤더 주석을 그대로 갖고 있다.
- staging 인벤토리로 `deploy-circleci.yml`을 실행하면 **같은 helm release**
  (`container-agent`, ns `cubrid`)를 staging group_vars(메모리 limit 16Gi)로 덮어쓴다 —
  즉 잘못된 값으로 하는 production 배포다.
- `inventory/staging/group_vars/all/vault.yml`은 vault 암호화조차 되어 있지 않다.
- 임시 가드: `staging_token`을 production 인벤토리에만 정의해 두어, staging 인벤토리
  배포는 템플릿 렌더 단계에서 undefined 변수로 즉시 실패한다 (CUBRIDQA-1474 stage 1).

**할 일**:

1. `inventory/staging/` 제거 또는 명시적 무력화(README 경고 + hosts.ini 비우기). 제거 시
   `docs/*.md`의 staging 표·배포 절, `inventory/staging` 심링크 구조도 함께 정리.
2. `circleci-values.yaml.j2`의 `cubrid/staging` resource class block을 "canary lane"
   용도로 주석 문서화. 두 class의 podSpec/postStart가 장기적으로 갈라지지 않도록
   전환 완료 후(CUBRIDQA-1477) 공통화(Jinja macro 등) 검토.
3. ADR-0007(runner pool 40/10 분할, 별도 helm release) 구현 시 canary lane의 배치
   (기존 release 유지 vs rerun release 쪽)를 함께 결정.
