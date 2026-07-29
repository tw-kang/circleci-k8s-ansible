# ADR-0003 — Shell controller/worker fan-out을 위한 러너 RBAC·노드 증설 배치

**Status**: Proposed (2026-06-02). cubrid-testtools [ADR-0001](https://github.com/CUBRID/cubrid-testtools/blob/develop/docs/adr/0001-shell-controller-worker-on-k8s.md)에 종속. 착수는 `tw-kang:migrate-jdk8` 머지 이후.

## Context

현재 `test_shell` job(`cubrid/.circleci/config.yml`)은 self-hosted 러너(`cubrid/ramdisk`)에서
`parallelism: 50`으로 돈다. 50개 pod가 각자 **local 모드** CTP를 실행하므로 CircleCI의
50-task 예산(`maxConcurrentTasks: 50`)을 그대로 소진한다.

cubrid-testtools ADR-0001은 이를 **1 controller + 50 worker** 구조로 바꾸기로 결정했다:
controller pod(=유일한 CircleCI task)의 entrypoint가 `kubectl`로 worker pod 50개를 생성하고
SSH로 fan-out한 뒤 teardown한다. worker는 CircleCI parallelism에 잡히지 않는다.

ADR-0001의 책임 경계(결정 #9): **worker Pod manifest와 controller/worker entrypoint 로직은
cubridci 이미지가 소유**하고, **raw 인프라(파드 생성 RBAC, 노드, 공유 저장소)는 본 repo가
소유**한다. 본 ADR은 그 인프라 조각이 `circleci-k8s-ansible`의 *어디에* 위치하는지 확정한다.

전제(검증된 사실): worker 노드는 192 vCPU / 496GiB 가용(노드당 pod 상한 110), build-cache는
GlusterFS로 이미 마운트, `download-build` job이 `/home/build-cache/builds/$CIRCLE_SHA1/CUBRID`를
채운다. 즉 CPU/메모리는 제약이 아니며 실제 천장은 pod 개수다.

## Decision — 배치 맵

### 1. 파드 생성 RBAC (controller task pod에 부여)
- **신규** `roles/circleci/templates/shell-controller-rbac.yaml.j2`:
  - `ServiceAccount` `shell-controller` (ns `{{ circleci_namespace }}` = `cubrid`)
  - `Role` `shell-controller` (ns `cubrid`): `apiGroups: [""]`, `resources: [pods]`,
    `verbs: [create, delete, get, list, watch]` (디버깅용 `pods/log`는 선택)
  - `RoleBinding` (SA → Role)
- **신규** `roles/circleci/tasks/rbac.yml`: glusterfs `tasks/k8s_cleanup.yml`과 동일 패턴
  (`set_fact` manifest_dir=`artifacts/manifests` → `template` 렌더 → `kubectl.sh apply -f`,
  `delegate_to: localhost`, `run_once: true`).
- **수정** `roles/circleci/tasks/main.yml`: 위 `rbac.yml`을 **helm 배포(`Deploy CircleCI
  container runner`) 이전에** `include_tasks`. (SA가 먼저 존재해야 task pod가 참조 가능.)
- **신규 변수** `inventory/{env}/group_vars/circleci/runner.yml`: `shell_controller_sa: "shell-controller"`
  (RBAC 템플릿과 values 템플릿이 공유).
- 근거: worker는 `cubrid` ns에만 생성되므로 **namespaced Role**로 최소 권한. ClusterRole 불필요.

### 2. controller task pod에 serviceAccountName 지정
- **수정** `roles/circleci/templates/circleci-values.yaml.j2`: `resourceClasses."{{ circleci_namespace }}/{{ resource_class }}".spec`
  레벨(=`containers`/`nodeSelector`/`shareProcessNamespace`와 형제)에
  `serviceAccountName: {{ shell_controller_sa }}` 추가. staging도 controller를 돌리면
  `cubrid/staging` spec에도 동일 추가.
- **검증 1순위(미해결 리스크)**: container-agent helm chart가 resourceClass podSpec의
  `serviceAccountName`을 task pod로 전달하는지 확인. 전달 안 되면 fallback —
  task pod가 실제 사용하는 SA(`kubectl get pod <task> -o jsonpath='{.spec.serviceAccountName}'`)에
  RoleBinding을 건다. worker는 API를 쓰지 않으므로 **자기 SA 불필요**(default SA +
  `automountServiceAccountToken: false` 권장); RBAC는 **controller에만** 필요.

### 3. worker 노드 +2 (같은 스펙)
- **수정** `inventory/production/hosts.ini` `[kube_node]`에
  `k8s-worker-03`, `k8s-worker-04` 추가(`ansible_host=… ansible_user=root`).
- **실행** `playbooks/add-node.yml` — `/home/tc-repo`·`/home/containerd-data`·`/home/kubelet-data`
  디렉토리 + bind mount 생성, kubespray `scale.yml`, 신규 노드 GlusterFS install+add_node로
  **`/home/build-cache` 마운트**까지 자동 처리. worker 라벨(`node-role.kubernetes.io/worker`)은
  `group_vars/kube_node/kube_node.yml`의 `node_labels`로 자동 부여. 리소스 예약도 group_vars
  레벨이라 **host_vars 신규 작성은 선택**.

### 4. (선택) 동시성 천장 상향
- 4노드 × 110 = 440 pod 슬롯 → 51 pod/파이프라인 기준 동시 ~7–8개가 자연 한도. 그 이상이
  필요하면 **수정** `inventory/{env}/group_vars/k8s_cluster/k8s-cluster.yml`의
  `kubelet_max_pods`(현재 미설정=기본 110; pod CIDR `/24`이므로 최대 254까지 상향 가능).

### 5. 본 repo가 소유하지 않는 것 (경계)
- worker Pod manifest/템플릿, controller/worker entrypoint role → **cubridci 이미지** (`origin/test_shell`).
- `test_shell` job의 `parallelism: 50 → 1` 및 split 제거 → **cubrid/.circleci/config.yml** (`origin/develop`).
- CTP(Java) → **변경 없음**.

네 repo 전체의 파일 단위 배치는 cubrid-testtools `docs/shell-k8s-migration-placement.md`에 통합되어 있다.

## Consequences

- 본 repo 신규/변경은 최소다: 템플릿 1 + 태스크 1 + `main.yml` include 1 + values
  `serviceAccountName` 1줄 + 변수 1 + 인벤토리 노드 2(+ `add-node.yml` 실행).
- `download-build` job, build-cache GlusterFS, 정리 CronJob, tc-repo 마운트는 **그대로 재사용**.
- `tc-repo` *콘텐츠* 채움은 기존 out-of-band 메커니즘에 의존(현 `test_shell`도 동일). 신규 노드의
  `/home/tc-repo`는 `add-node.yml`이 디렉토리/마운트만 만들므로, 콘텐츠 동기화 메커니즘이
  신규 노드까지 커버하는지 확인 필요.
- 실패 아티팩트(core·db 백업)는 ADR-0001 결정대로 worker teardown 시 손실(요약만 보존).
