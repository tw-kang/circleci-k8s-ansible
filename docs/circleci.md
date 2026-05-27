# CircleCI self-hosted runner

## 개요

CircleCI container runner는 공식 `container-agent/container-agent` Helm chart를
`https://packagecloud.io/circleci/container-agent/helm` 에서 가져와 Kubernetes Deployment로 배포한다.

- **Helm release name**: `container-agent`
- **Namespace**: `cubrid` (`circleci` 아님)
- **Resource class**: `cubrid/ramdisk`
- **의존성**: 동작 중인 K8s 클러스터(`docs/installation.md` 참조),
  `vault.yml`에 암호화된 `vault_circleci_token`, 그리고 워커 노드에 마운트된
  `/home/build-cache` (GlusterFS, `cluster-only.yml`이 구성)

---

## 사전 요구사항

1. K8s 클러스터가 프로비저닝되어 있고 `inventory/{env}/artifacts/kubectl.sh`를 통해
   kubectl 접근이 가능해야 한다. `deploy-circleci.yml` pre-tasks(10~19번 줄)가 자동으로 검증한다.
2. `vault_circleci_token`이 `vault.yml`에 ansible-vault로 암호화되어 있어야 한다.
   플레이북이 22~36번 줄에서 다음과 같이 검증한다:

   ```yaml
   # deploy-circleci.yml:22-36
   - name: Validate CircleCI configuration
     assert:
       that:
         - circleci_namespace is defined
         - resource_class is defined
         - token is defined

   - name: Check if CircleCI token is encrypted
     fail:
       msg: "CircleCI token must be encrypted with ansible-vault."
     when:
       - token is defined
       - not token.startswith('$ANSIBLE_VAULT')
       - token != "{{ vault_circleci_token }}"
   ```

3. `/home/build-cache`가 모든 워커 노드에 마운트되어 있어야 한다. 이는 `cluster-only.yml`이
   구성하는 GlusterFS 복제 볼륨으로, `glusterfs` role이 `kube_node` 호스트에서 `glusterfs`
   태그로 실행된다.

---

## 설정

변수는 `inventory/{env}/group_vars/circleci/runner.yml`에 위치한다.

| 변수 | Production | Staging |
|---|---|---|
| `circleci_namespace` | `cubrid` | `cubrid` |
| `circleci_config_path` | `/opt/circleci/config` | `/opt/circleci/config/staging` |
| `resource_class` | `ramdisk` | `ramdisk` |
| `replicas` | `1` | `1` |
| `maxConcurrentTasks` | `50` | `50` |
| `image` | `cubridci/cubridci:test_shell` | `cubridci/cubridci:test_shell` |
| `resources.requests.cpu` | `2` | `2` |
| `resources.requests.memory` | `4Gi` | `4Gi` |
| `resources.limits.cpu` | `8` | `8` |
| `resources.limits.memory` | `32Gi` | `16Gi` |
| `token` | `{{ vault_circleci_token }}` | `{{ vault_circleci_token }}` |

---

## 템플릿

`roles/circleci/tasks/main.yml`이 `roles/circleci/templates/circleci-values.yaml.j2`를
렌더링하여 배포 시 사용하는 Helm values를 생성한다. 템플릿에는 아래에서 설명하는 GlusterFS
build-cache postStart 로직이 포함된다.

---

## Pod 구조

각 태스크 Pod(`cubrid/ramdisk`)는 단일 `primary` 컨테이너를 실행하며 다음 설정을 적용한다:

- **Security context**: `privileged: true` (overlay 마운트에 필요)
- **Node selector**: `node-role.kubernetes.io/worker: ""`
- **Topology spread**: 호스트명 기준 `maxSkew: 1`, `ScheduleAnyway`
- **`shareProcessNamespace: true`**

### Volume

| 이름 | 타입 | 마운트 경로 | 비고 |
|---|---|---|---|
| `goat-ephemeral` | `emptyDir` | `/runner-init` | init 임시 공간 |
| `repo-ro` | `hostPath` `/home/tc-repo/cubrid-testcases-private-ex` | `/ro` | 읽기 전용 테스트케이스 |
| `overlay-rw` | `emptyDir` Memory | `/rw` | 테스트케이스 overlay upper+work; production sizeLimit 16Gi, staging 8Gi |
| `build-cache` | `hostPath` `/home/build-cache` | `/home/build-cache` | GlusterFS 기반 빌드 캐시 |
| `build-overlay-rw` | `emptyDir` | `/build-rw` | CUBRID overlay upper+work; production medium 없음, staging Memory 2Gi |
| `podinfo` | `downwardAPI` labels | `/etc/podinfo` | postStart에서 Pod 레이블 참조 |

### postStart hook

`postStart` exec는 네 단계로 실행된다:

1. 테스트케이스 overlay 마운트: `lowerdir=/ro` → `/home/cubrid-testcases-private-ex`
2. `/etc/podinfo/labels`에서 `CIRCLE_JOB`과 `CIRCLE_SHA1` 추출
3. job이 `download-build`이거나 CUBRID가 이미 `/home/CUBRID/bin/cubrid`에 존재하면
   조기 종료 (legacy workspace 방식)
4. GlusterFS 방식: `/home/build-cache/builds/$CIRCLE_SHA1/CUBRID` 대기 후
   `/home/CUBRID`에 overlay로 마운트

`circleci-values.yaml.j2:117-121`의 대기 루프:

```sh
# circleci-values.yaml.j2:117-121
RETRY=0
MAX_WAIT=300
INTERVAL=5
while [ ! -d "$BUILD_DIR/CUBRID" ] && [ $RETRY -lt $((MAX_WAIT / INTERVAL)) ]; do
  [ $((RETRY % 12)) -eq 0 ] && echo "$LOG Waiting for build... ($((RETRY * INTERVAL))s / ${MAX_WAIT}s)"
  sleep $INTERVAL
  RETRY=$((RETRY + 1))
done
```

최대 대기 시간은 300초(폴링 간격 5초)다. 300초 내에 빌드 디렉토리가 나타나지 않으면
컨테이너가 non-zero로 종료되어 Pod가 실패한다.

---

## 배포

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

staging의 경우:

```bash
ansible-playbook \
  -i inventory/staging/hosts.ini \
  playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

플레이북(`deploy-circleci.yml`) 실행 흐름:

1. **pre_tasks**: kubespray 아티팩트 존재 확인, CircleCI 설정 변수 검증, 토큰이
   vault 암호화되어 있는지 검증, 클러스터에 노드가 최소 하나 이상인지 확인.
2. **tasks**: `include_role: circleci` — Helm repo 추가, namespace가 없으면 생성,
   템플릿에서 `values.yaml` 작성, `helm install/upgrade` 실행(`wait: false`).
3. **post_tasks**: `deployment/container-agent`의 readyReplicas를 조회하고 요약을 출력.

`cluster-only.yml`은 K8s 클러스터(Kubespray)와 GlusterFS 빌드 캐시를 프로비저닝하지만
CircleCI runner는 배포하지 **않는다**. `cluster-only.yml`에는 `circleci_enabled` 플래그가
없다.

---

## 검증

```bash
# kubespray kubectl wrapper 사용
inventory/production/artifacts/kubectl.sh get pods -n cubrid
inventory/production/artifacts/kubectl.sh logs -n cubrid deployment/container-agent

# 또는 표준 kubeconfig 사용
kubectl get pods -n cubrid
kubectl describe pod -n cubrid -l app=container-agent
```

CircleCI 웹 콘솔의 **Self-Hosted Runners → `cubrid/ramdisk`** 에서 runner가 **ONLINE** 상태인지
확인한다.

---

## 운영

### 확장

`inventory/{env}/group_vars/circleci/runner.yml`의 `replicas`를 수정한 후 배포 플레이북을
재실행한다. Helm chart가 Deployment를 조정한다.

Ansible 없이 즉시 확장하는 경우:

```bash
kubectl scale deployment container-agent -n cubrid --replicas=2
```

주의: 다시 줄이려면 `values.yaml`에 변경을 영구 반영하기 위해 재배포가 필요하다.

### 재시작

```bash
kubectl rollout restart deployment/container-agent -n cubrid
```

### 토큰 갱신

```bash
ansible-vault edit vault.yml   # update vault_circleci_token
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

### resource class 또는 이미지 갱신

`runner.yml`의 `resource_class`, `image`, `resources.*`를 수정한 후 배포 플레이북을 재실행한다.
인플레이스 패치 경로는 없으며, Helm이 전체 `values.yaml` diff를 적용한다.

---

## 문제 해결

**Pod가 시작되지 않는 경우**

```bash
kubectl describe pod -n cubrid <pod-name>
kubectl get events -n cubrid --sort-by=.lastTimestamp
```

주요 원인:
- 배포 시 토큰 검증 실패 (pre-task assert, `deploy-circleci.yml:22-36`)
- Node selector `node-role.kubernetes.io/worker: ""`에 매칭되는 노드 없음

**postStart 실패 (Pod가 `Init` 상태에서 멈추거나 `OOMKilled`)**

```bash
kubectl logs -n cubrid <pod-name> --previous
```

확인 사항:
- `/home/build-cache`가 워커 노드에 마운트되어 있는지
- `/home/build-cache/builds/<SHA1>/CUBRID`가 job 시작 후 300초 내에 나타나는지
- `overlay-rw` memory emptyDir이 소진되지 않았는지 (production 16Gi, staging 8Gi)

**빌드 캐시 미스**

```bash
ls /home/build-cache/builds/
```

테스트 job이 postStart 4단계에 도달하기 전에 `download-build` CircleCI job이 완료되어야 한다.
디렉토리가 비어 있다면 upstream에서 `download-build` job이 실패한 것이다.

**리소스 부족**

```bash
kubectl top nodes
kubectl top pods -n cubrid
```

워커 노드는 동시 태스크 Pod 당 requests(2 CPU, 4Gi RAM)를 처리할 여유가 있어야 한다.
`maxConcurrentTasks: 50`은 CircleCI 측 제한이며, 실제 제약은 K8s 스케줄링이다.
