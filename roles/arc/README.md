# roles/arc — GitHub Actions 러너 (ARC)

`CUBRID/cubrid` 의 `gha-ci.yml` 을 태우는 self-hosted 러너를 띄운다.
Actions Runner Controller 의 `gha-runner-scale-set` 차트를 쓴다.

CUBRIDQA-1537 이 만들었다. 그 전에는 `kubectl` 과 `helm` 을 손으로 쳤고
원본 파일이 연구용 스크래치 디렉토리에만 있었다.

## 무엇을 만드는가

lane 은 넷이다. 릴리스 이름이 곧 러너 라벨이고, 같은 라벨의 두 lane 은 namespace 로 갈린다.

| lane | namespace | 릴리스 = 라벨 | 상한 | 태그 |
|---|---|---|---|---|
| production | `{{ arc_namespace }}` | `cubrid-arc` | `arc_max_runners` | (없음) · `arc_production` |
| production light | `{{ arc_namespace }}` | `cubrid-arc-light` | `arc_light_max_runners` | (없음) · `arc_production` · `arc_light` |
| fork | `{{ arc_fork_namespace }}` | `cubrid-arc` | `arc_fork_max_runners` | `arc_fork` |
| fork light | `{{ arc_fork_namespace }}` | `cubrid-arc-light` | `arc_fork_light_max_runners` | `arc_fork` |

경량 lane 둘은 CUBRIDQA-1501 결정 62 가 더했다. 5분 이하 job(plan · collect ·
rerun shard · medium shard)이 다른 run 의 shard 50개 뒤에 서지 않게 한다.

lane 하나마다 이렇게 만든다. `<릴리스>` 는 위 표의 릴리스 이름이다.

| 자원 | 이름 |
|---|---|
| namespace | 위 표 |
| secret | `<릴리스>-gh-app` |
| ConfigMap | `<릴리스>-pod-template` · `<릴리스>-job-hook` |
| helm 릴리스 | `<릴리스>` |

lane 과 별개로, **산출물 열람 서버**를 하나 만든다 (아래 절).

| 자원 | 이름 |
|---|---|
| ConfigMap | `{{ arc_artifact_server_name }}-nginx` |
| Deployment | `{{ arc_artifact_server_name }}` |
| Service (NodePort) | `{{ arc_artifact_server_name }}` |

렌더한 파일은 master 의 `{{ arc_config_path }}` 에 남는다 — fork 는 그 아래 `fork/`,
경량 lane 둘은 각자 그 아래 `light/` 다.

ARC 컨트롤러(`arc-controller`)는 2026-09-18(티켓 68)부터 이 role 이 helm 으로 올린다.
production 인벤토리가 `arc_controller_manage: true` 를 준다. 그 전에는
`controller-values.yaml` 을 받아 적기만 했다.

### 어느 pod 이 어느 노드에 뜨나

| pod | 노드 | 무엇이 정하나 |
|---|---|---|
| 컨트롤러 (lane 마다 하나, 둘) | 제어면 | `arc-controller-values.yaml.j2` 의 `nodeSelector`·`tolerations` |
| 리스너 (lane 마다 하나, 넷) | 제어면 | `arc-values.yaml.j2` 의 `listenerTemplate` |
| 산출물 서버 · repo seed | 워커 | 각 템플릿의 `nodeSelector: worker` |
| 러너 pod | 워커 | `topologySpreadConstraints` 로 두 워커에 고른다 |
| job pod | 러너와 같은 노드 | 훅이 `spec.nodeName` 을 박는다 |

⚠ **산출물 서버와 repo seed 는 제어면으로 못 옮긴다. 이유가 서로 다르다.**
산출물 서버는 `{{ arc_artifact_server_root }}` 를 hostPath 로 잡는데 GlusterFS 는
`kube_node` 에만 마운트한다 (`playbooks/cluster-only.yml`) — 제어면에 얹으면 pod 이
hostPath 를 못 찾아 기동에 실패한다. repo seed 는 DaemonSet 이고 하는 일이 **워커마다의
노드 사본**(`{{ arc_repo_seed_root }}`)을 채우는 것이라, 옮긴다는 말 자체가 성립하지 않는다.

그래서 워커의 상시 pod 은 컨트롤러 둘 · 리스너 넷 · 산출물 서버 하나 · seed 가 워커마다
하나다. 제어면으로 가는 것은 **앞의 여섯**이다.

## 쓰는 법

```bash
ansible-playbook playbooks/deploy-arc.yml                    # production + light (ns gha-ci)
ansible-playbook playbooks/deploy-arc.yml --tags arc_fork    # fork + fork light  (ns default)
ansible-playbook playbooks/deploy-arc.yml --tags arc_light   # 경량 lane 만. 본 풀 리스너는 안 재시작한다
ansible-playbook playbooks/deploy-arc.yml --tags arc_render  # 렌더만. 클러스터를 안 건드린다
ansible-playbook playbooks/deploy-arc.yml --tags arc_artifacts  # 산출물 서버만
ansible-playbook playbooks/deploy-arc.yml --tags arc_repo_seed  # 노드 seed DaemonSet 만
```

⚠ **태그 없는 실행은 production 쪽 lane 둘만 띄운다.** `roles/circleci` 는 태그가 없으면
lane 을 다 띄우지만 여기는 다르다. 같은 라벨의 두 lane 이 **릴리스 이름을 공유**하므로 이동
순서를 지켜야 한다 (아래). 그래서 fork 쪽 lane 둘에 `never` 태그를 걸었다. `arc_light` 는
production light 에만 걸려 있다 — fork 까지 걸면 `--tags arc_light` 가 fork 의 `never` 를
풀어 버린다.

⚠ **리스너 pod 은 lane 마다 따로 뜬다.** 지금은 넷이고, 이름은
`<릴리스>-<해시>-listener` 다. helm 이 도는 lane 의 리스너만 재시작하므로, 그 lane 으로
가는 dispatch 만 5분 막으면 된다. 다른 lane 은 그 동안 그대로 돈다.

```bash
kubectl get pod -A -l app.kubernetes.io/component=runner-scale-set-listener
```

⚠ **함정 — 이미 lane 이 있는 namespace 에 lane 을 더하면 새 리스너가 낡은 ERS 를 가리킬 수 있다.**
컨트롤러가 EphemeralRunnerSet 을 만들고 AutoscalingListener 를 그 이름으로 만드는데, 그 사이에
ERS 가 다시 만들어지면 AutoscalingListener 에 옛 이름이 남는다. 그러면 리스너 pod 이 6초마다
죽고 다시 뜬다. **컨트롤러는 pod 만 다시 만들고 그 이름을 다시 읽지 않으므로 저절로 낫지 않는다.**
2026-09-14 `default` 의 `cubrid-arc-light` 에서 실제로 났다.

증상은 리스너 로그의 마지막 줄이다.

```
Application returned an error: handling initial message failed:
could not patch ephemeral runner set , error:
ephemeralrunnersets.actions.github.com "<옛 이름>" not found
```

대조하고 고치는 법이다. AutoscalingListener 를 지우면 컨트롤러가 현재 ERS 로 다시 만든다.
helm 은 건드리지 않는다.

```bash
kubectl get autoscalinglistener -n <ns> <릴리스>-<해시>-listener -o jsonpath='{.spec.ephemeralRunnerSetName}'
kubectl get ephemeralrunnerset -n <ns>          # 위 이름과 다르면 이 함정이다
kubectl delete autoscalinglistener -n <ns> <릴리스>-<해시>-listener
```

fork lane 은 별도 inventory 를 쓰지 않는다. 값은 production 값 파일
`inventory/production/group_vars/arc/runner.yml` 안에 `arc_fork_*` 로 나란히 있다.

`--tags arc_production` 도 있다. **평소에는 쓸 일이 없다** — 태그 없는 실행이 이미
production 만 띄우기 때문이다. 두 가지에만 쓴다. 첫째, `arc_fork` 와 짝을 맞춰 어느 lane 을
돌리는지 명령줄에 드러내고 싶을 때다. 둘째, **컨트롤러 values 파일을 건드리지 않고**
production lane 만 다시 돌리고 싶을 때다 — `controller-values.yaml` 을 쓰는 태스크는
`arc_render` 태그만 달고 있으므로 이 태그로는 안 돈다.

## ⚠ 계약면 — 워크플로와 IaC 가 양쪽에서 지켜야 하는 값

**어긋나면 에러가 아니다.** 무반응이거나 정지다. 이관 중 겪은 사고가 전부 이 종류였다.

| 계약 | 워크플로 (`gha-ci.yml`) | IaC (이 role) | 어긋나면 |
|---|---|---|---|
| 러너 라벨 | `runs-on: cubrid-arc` | helm 릴리스 이름 = `arc_release` | job 이 영구 대기 |
| pod template key | — | ConfigMap key `content` ↔ `ACTIONS_RUNNER_CONTAINER_HOOK_TEMPLATE=/home/runner/pod-template/content` | job pod 에 마운트가 없다 |
| job hook key | — | ConfigMap key `hook.sh` · `policy` ↔ `hook.sh` 가 `POLICY_FILE=/opt/job-hook/policy` 를 `.` 로 읽는다 | 훅이 기본값으로 돈다 |
| secret key | — | `github_app_id` · `github_app_installation_id` · `github_app_private_key` | 러너가 등록되지 않는다 |
| 마운트 경로 | `mount -t overlay` 의 `/ro` `/rw` `/build-rw` | pod template 의 `volumeMounts` | overlay 마운트 실패 |
| GlusterFS 루트 | `CI_ROOT` | pod template 의 hostPath + 보관 CronJob 의 `glusterfs_cleanup_dirs` | 발행물이 영구 누적 |
| 노드 사본·공유 루트 (티켓 72) | `CI_ROOT=/home/ci/shared` · overlay lowerdir `/home/ci/seed/…` · `BUILD_MIRROR=/home/ci/seed/build` · `CCACHE_DIR=/home/ci/cache/…` (cubrid PR B 부터) | `arc_shared_root`·`arc_seed_root`·`arc_cache_root` + `roles/glusterfs` 의 `glusterfs_extra_mounts` | seed 가 비면 첫 git 명령이 죽고, shared 마운트가 없으면 pod 이 안 뜬다 |
| 산출물 서빙 루트 | summary 의 링크는 `CI_ROOT` 상대 경로다 | `arc_artifact_server_root` | 링크가 전부 404 |
| PID 1 | shard 의 `ps -p 1` 검사 | pod template 의 `shareProcessNamespace: true` | 실패가 아니라 120분 정지 |
| overlay 권한 | `mount -t overlay` | pod template 의 `privileged: true` | 마운트 거부 |
| 이벤트 허용 | `on:` 트리거 | `arc_allowed_events` | 러너가 job 을 거부 |
| 이미지 신선도 | `container.image` 태그 | pod template 의 `imagePullPolicy: Always` | 옛 이미지로 조용히 돈다 |
| 동시 용량 | `parallelism` 입력 | `arc_max_runners` | pod Pending |
| tmpfs 상한 | `df /rw` `df /build-rw` 보고 | `arc_tmpfs_testcases` · `arc_tmpfs_build` | 노드 OOM |
| 산출물 URL | `ARTIFACT_URL_BASE` | `arc_artifact_server_node_port` | summary 의 링크가 전부 죽는다 |

⚠ secret 의 key 이름 셋은 **ARC 차트가 정한다.** 우리 선택이 아니다.

## ⚠ `arc_` 접두어는 취향이 아니라 필수다

그룹 `arc` 와 그룹 `circleci` 가 **둘 다 `kube_control_plane` 을 가리킨다.**
그래서 두 group_vars 가 같은 호스트에 함께 로드된다.

`group_vars/circleci/runner.yml` 이 이미 쓰는 이름이다.

```
token   replicas   image   resources   maxConcurrentTasks
```

접두어 없이 `resources` 를 쓰면 **조용히 덮인다.** 그룹 이름 알파벳 순 병합이라
`circleci` 가 `arc` 를 이긴다. 러너 limits 가 CircleCI 값으로 뜨고 에러는 안 난다.

## ⚠ 컨트롤러 lane 분리 — 순서가 반대다

2026-09-01 부터 컨트롤러도 lane 마다 하나다 (결정 27). **아직 클러스터에 적용되지
않았다.** 지금은 `default` 의 컨트롤러 하나가 모든 namespace 를 본다.

### 왜 하나로는 안 되나

컨트롤러는 AutoscalingListener 를 **자기 namespace** 에 만든다. 차트 0.14.2 의
`manager_listener_role.yaml` 이 pods · secrets · serviceaccounts 권한 Role 을
`.namespace` 에 만들고, 그것은 `flags.watchSingleNamespace` 와 **무관하게 무조건**
렌더된다. 2026-09-01 실측 —

```
NS       NAME                          GITHUB URL                          RUNNERSET NS
default  cubrid-arc-59957d7f-listener  https://github.com/CUBRID/cubrid    gha-ci     <- 어긋난다
default  cubrid-arc-95cf96c6-listener  https://github.com/tw-kang/cubrid   default
```

`gha-ci/cubrid-arc-gha-rs-manager` RoleBinding 의 subject 도 `default` 의 컨트롤러
SA 다. 즉 운영 lane 이 두 namespace 에 걸쳐 있다.

### ⚠ 순서는 fork 먼저다. 위의 "이동 순서" 와 반대다

scale set 이동은 릴리스 이름이 겹쳐서 production 이 먼저 비켜야 했다. 컨트롤러는
그 반대다 — **`default` 컨트롤러를 먼저 좁히지 않으면 두 컨트롤러가 같은 scale set 을
동시에 reconcile 한다.**

```
0. 조용한 창을 잡는다. 도는 run 이 없어야 한다
1. --tags arc_fork          default 컨트롤러에 watchSingleNamespace=default 가 붙는다
2. 운영 리스너의 고아를 치운다 (아래 함정)
3. untagged (production)    gha-ci 에 컨트롤러가 서고, scale set 의
                            controllerServiceAccount 가 gha-ci 로 올라간다
4. 리스너가 gha-ci 에 떴는지 본다. 5분 기다린 뒤 작은 dispatch 로 확인한다
```

### ⚠ 함정 — 고아 리스너는 finalizer 로 굳는다

`AutoscalingListener` 는 `autoscalinglistener.actions.github.com/finalizer` 를 달고
있고, **그 finalizer 를 떼는 것은 그것을 watch 하는 컨트롤러뿐이다.** 1번으로
`default` 컨트롤러를 좁히면 운영 리스너(`default` 에 있고 scale set 은 `gha-ci`)를
아무도 안 본다. 그 상태에서 지우면 **delete 가 Terminating 으로 굳는다.**

**깨끗한 재생성으로 정했다** (사용자 결정, 2026-09-01. 결정 27). 제자리 좁히기는
운영 리스너를 고아로 만드는 창이 생긴다. 재생성은 그 창이 아예 없다 — 운영 scale set 을
**`default` 컨트롤러가 아직 그것을 볼 때** 걷어내므로 finalizer 가 정상적으로 걷힌다.

### 절차 — 이 순서를 지켜라

```
0. 조용한 창
   gh run list --repo CUBRID/cubrid --workflow gha-ci.yml --status in_progress   -> 0
   kubectl get pods -n gha-ci                                                    -> 러너 pod 0

1. 운영 lane 을 비우고 걷어낸다   ⚠ default 컨트롤러를 아직 좁히지 않은 상태여야 한다
   maxRunners=0  ->  러너 pod 0 확인  ->  helm uninstall cubrid-arc -n gha-ci
   게이트: kubectl get autoscalingrunnerset,autoscalinglistener -A
           gha-ci 의 scale set 과 그 리스너가 사라져야 한다.
           Terminating 으로 남아 있으면 여기서 멈춘다 — 2번을 하면 영구히 굳는다

2. default 컨트롤러를 default 로 좁힌다  (fork lane)
   arc_controller_manage=true
   ansible-playbook playbooks/deploy-arc.yml --tags arc_fork
   확인: kubectl -n default get deploy arc-controller-gha-rs-controller \
           -o jsonpath='{.spec.template.spec.containers[0].args}' | grep watch-single-namespace
   ⚠ fork 리스너가 재시작한다. 아래 "띄운 직후에 dispatch 하지 마라" 가 여기에도 걸린다

3. gha-ci 에 컨트롤러 + 운영 scale set 을 세운다
   ansible-playbook playbooks/deploy-arc.yml        (untagged = production)
   role 이 컨트롤러를 먼저, scale set 을 나중에 돌린다 — scale set 의
   `<release>-gha-rs-manager` RoleBinding 이 그 컨트롤러 SA 를 가리키기 때문이다

4. 확인 — 넷 다 gha-ci 여야 한다
   kubectl get autoscalinglistener -A          리스너의 NS 가 gha-ci
   kubectl get autoscalingrunnerset -A         gha-ci/cubrid-arc, MAX 102
   kubectl get pods -n gha-ci                  컨트롤러 + 리스너
   kubectl -n gha-ci get rolebinding cubrid-arc-gha-rs-manager -o jsonpath='{.subjects}'
                                               subject namespace 가 gha-ci

5. 5분 기다린 뒤 작은 dispatch 로 확인한다 (-f parallelism=1 -f limit=5)
```

⚠ **1번의 "비우고" 를 건너뛰지 마라.** 아래 "릴리스를 먼저 지우지 마라" 와 같은 함정이다 —
`maxRunners=0` 과 러너 pod 0 확인이 `helm uninstall` 의 전제다. 순서를 지키면 uninstall
자체는 이미 문서화된 절차다(위 "이동 순서" 1·2 단계가 같은 모양이다).

⚠ **2번과 3번 사이에 운영 lane 은 러너가 없다.** job 은 큐에 쌓이고 사라지지는 않는다.
두 pass 를 붙여서 돌려 창을 짧게 하라.

⚠ `arc_controller_manage` 는 기본 `false` 다. 그 값이 `true` 가 되기 전에는 이 절의 어떤
단계도 helm 을 돌리지 않는다. 렌더만 된다.

## ⚠ 이동 순서 — 릴리스 이름이 겹친다

러너 라벨 = scale set 이름 = **helm 릴리스 이름**이다. 워크플로는 `runs-on: cubrid-arc` 다.
helm 은 릴리스 이름을 바꾸지 못한다. 그리고 **한 namespace 에 같은 릴리스 이름은 하나뿐이다.**

```
1. production  cubrid-arc : default -> gha-ci
     maxRunners=0  ->  러너 pod 0 확인  ->  helm uninstall  ->  ansible-playbook (production)
2. fork  cubridqa-1503-poc 제거
     maxRunners=0  ->  러너 pod 0 확인  ->  helm uninstall
3. fork  cubrid-arc 설치
     ansible-playbook --tags arc_fork
```

⚠ **1 이 끝나기 전에는 3 을 할 수 없다.** role 이 그것을 막는다. 1 을 건너뛰고 3 을 하면
`default` 에는 아직 production 의 `cubrid-arc` 가 있고, helm 이 이름만 보고 **upgrade** 로
처리해 그 scale set 을 `tw-kang/cubrid` 로 돌려 버린다. 조용히 깨지는 쪽이다.
`Refuse to repoint another lane's scale set` 가 그 전에 멈춘다.

⚠ 반대로 **1 이 끝난 뒤에는 두 lane 이 같은 이름으로 공존한다.** 그것이 정상이다 —
helm 은 (이름, namespace) 로 릴리스를 가르고, 러너 라벨은 등록된 GitHub 저장소 범위다.
`gha-ci/cubrid-arc` 와 `default/cubrid-arc` 는 서로 다른 저장소를 본다.

⚠ **3 단계 전에 워커에서 `_fork` 디렉토리가 있어야 한다.** hostPath 가 `type: Directory`
라 없으면 pod 이 안 뜬다. `roles/glusterfs` 의 `glusterfs_volumes[].dirs` 가 만들고,
gluster 볼륨이라 워커 한 대에서 만들면 복제된다.

⚠ **릴리스를 먼저 지우지 마라.** ARC 가 `cleanup-protection` finalizer 를 건다. 릴리스가
먼저 사라지면 ServiceAccount 가 종료 대기로 굳고 모든 job 이 `HttpError` 로 죽는다.

⚠ **띄운 직후에 dispatch 하지 마라.** helm 이 리스너 pod 을 재시작하고, 그 틈에 큐로 들어간
job 의 배정 메시지는 죽은 세션으로 가 영원히 사라진다. 폴링 재개(`Getting next message`)를
확인해라. 실측 주기 50.5초이므로 창을 5분으로 잡는다.

## 산출물 열람 서버

`gha-ci.yml` 의 run summary 마지막 줄은 `/home/build-cache/gha-ci/runs/<run_id>` 였다.
워커 노드에서만 뜻이 있는 경로다. 그것을 브라우저로 여는 링크로 바꾸려고 이 서버를 둔다
(CUBRIDQA-1501 티켓 34).

```
http://192.168.1.48:30080/runs/<run_id>/                        결과·실패 증거
http://192.168.1.48:30080/runs/<run_id>/build/<mode>/build.log 빌드 로그 (mode = release | debug)
http://192.168.1.48:30080/builds/<ns>/<sha>/debug/build.log    발행된 빌드 옆의 사본. summary 가 이것을 링크한다
```

정한 것 다섯이다.

1. **nginx `autoindex` + hostPath 읽기 전용 + NodePort.** 웹 UI 를 만들지 않는다.
2. **pod 는 워커에 뜨고, URL 은 마스터 IP 다.** GlusterFS 는 `kube_node` 만 마운트한다
   (`playbooks/cluster-only.yml`). NodePort 는 모든 노드 IP 에서 답하므로, 사람들이 이미
   Grafana(32000)로 쓰는 `192.168.1.48` 을 URL 에 쓴다. 워커의 192.168.2.x 를 노출하지 않는다.
3. **서빙 루트는 볼륨 루트(`arc_artifact_server_root` = `arc_shared_root`)다.** `CI_ROOT` 와 같은 값이어야 한다 —
   summary 의 링크가 그 상대 경로다. fork lane 이 그 하위(`_fork`)에 들어오므로 nginx 가
   `/_fork` 를 404 로 막는다. 바깥 기여자의 PR 이 쓰는 자리다.
4. **인증이 없다.** 사내망·읽기 전용이다. 외부에서는 VPN 을 탄다.
5. **`.xml` · `.log` · `.data` · `.list` · `.tsv` 는 `text/plain`** 으로 내보내 브라우저에서
   바로 읽힌다. 나머지는 `application/octet-stream` 이라 내려받는다.
   `runs/*/plan/testtools/` 와 `runs/*/testtools/` 는 404 다 — 실패 run 하나당 59MB 짜리
   CTP seed 라 읽을 사람이 없다. 앞이 run 디렉토리 재배치 뒤 자리, 뒤가 그 전 자리다.

⚠ **링크의 수명은 보관 정책이 정한다.** `roles/glusterfs` 의 `glusterfs_cleanup_dirs` 가
`gha-ci/runs` 를 7 일 뒤 지운다. **2026-09-04 확인: 클러스터에 배포된 CronJob 에는 그
항목이 없다.** role 기본값에는 있는데 매니페스트를 재적용하지 않았다 — 그래서 지금은
아무것도 안 지워진다. `--tags glusterfs_cleanup` 재적용이 그것을 고친다.

⚠ **kube-proxy 가 ipvs 모드라 loopback 으로는 NodePort 가 안 열린다.** 노드에서 확인할 때
`127.0.0.1:30080` 이 아니라 노드 IP 를 써라. 이것은 Grafana 도 마찬가지다.

## 노드 seed — DaemonSet `gha-node-seed`

job 이 읽는 저장소를 워커마다 제 디스크에 둔다 (CUBRIDQA-1501 티켓 72). 볼륨은
`CUBRID.tar.gz` 전달·결과 적재·timings·nginx 열람만 맡는다.

```
/home/ci/
├── shared/   gha-ci 볼륨의 유일한 클라이언트. roles/glusterfs 의 glusterfs_volumes
│             (lru-limit=0,invalidate-limit=64)
├── seed/     DaemonSet 이 채운다. build/ = cubrid worktree + 서브모듈 미러 (BUILD_MIRROR),
│             test/ = 테스트 repo 3 + CTP 의 미러·worktree. pod 에 ro
└── cache/    ccache. build 가 쓴다. pod 에 rw
```

- 워커마다 pod 하나가 상주하며 정각마다(`arc_repo_seed_period_seconds`) `seed.sh` 를 돈다.
  락도 deadline 도 없다 — 한 노드에 실행이 하나뿐이다. 두 노드는 같은 시각에 같은 origin 을
  fetch 하므로 같은 커밋에 수렴한다.
- 스크립트는 매 회 ConfigMap 에서 다시 읽는다. 스크립트만 고쳤으면 `--tags arc_repo_seed`
  재적용으로 끝나고 pod 은 재시작하지 않는다.
- 지금 갱신하려면 그 노드의 pod 을 지운다 — 새 pod 이 뜨면서 바로 한 번 돈다.
  `kubectl exec` 로 `seed.sh` 를 따로 돌리지 마라. 루프와 겹친다.
- 첫 채움은 노드당 약 4.4 GB 다. 두 노드가 회선(30 Mbps)을 나눠 쓰므로 약 40 분이다.
- `/home/ci/seed` 는 kubelet 이 만든다(`DirectoryOrCreate`). 노드를 더하면 DaemonSet 이 따라가
  스스로 채운다. `/home/ci/cache` 는 첫 job pod 이 만든다.
- ⚠ 옛 볼륨 seed(`gha-repo-seed` CronJob·ConfigMap·Secret, ns `gha-ci`)는 이 role 이 더
  관리하지 않는다. 워크플로가 `/home/ci` 로 옮길 때까지 그대로 돌고, 티켓 25 가 지운다.

## 검증 — 골든 파일 대조

Ansible 에 테스트 프레임워크가 없다. **골든 기준선과의 대조가 유일한 성공 기준이다.**

> role 이 렌더한 22 파일이 지금 클러스터에 적용된 것과 **바이트 동일**해야 한다.
> 일부러 갈라 놓은 것은 아래 표에 적는다.

```bash
ansible-playbook playbooks/deploy-arc.yml --tags arc_render   # 클러스터를 안 건드린다
rsync -a root@192.168.1.48:/opt/arc/config/ /tmp/g/
diff -r /tmp/g <맵 archive>/ARC-2026-0922-arc-render
```

⚠ **기준선을 2026-09-22 에 다시 떴다 (CUBRIDQA-1501 티켓 47).** 옛 기준 `ARC-1526-*`
(2026-08-24)과 그 예외표 10 항목은 폐기했다. 템플릿의 주석을 전부 지워 렌더 결과가 통째로
갈렸고, 예외표가 뜻을 잃었기 때문이다. 새 기준은 `ARC-2026-0922-arc-render/` 22 파일이고
lane 넷을 다 담는다. **예외표는 비어 있다** — 다음에 일부러 가르는 것부터 여기 적어라.

| 파일 | 무엇이 갈렸나 | 왜 |
|---|---|---|
| — | — | — |

⚠ **대조는 `--check` 로 하지 않는다.** `--check` 에서는 `template` 모듈이 파일을 쓰지
않으므로 견줄 대상이 안 생긴다. `--tags arc_render` 가 그 자리를 대신한다 —
namespace·secret·ConfigMap·helm 을 전부 건너뛴다. `--check` 는 배포 직전 예행 연습에 쓴다.

⚠ **기준선을 다시 뜰 때는 클러스터의 것을 덮지 마라.** `-e arc_config_path=<빈 디렉토리>` 를
주면 렌더가 그 디렉토리로 간다. `/opt/arc/config` 는 그대로 남는다.

`--tags arc_render` 는 master 에 **22 파일**을 쓴다. lane(넷) 마다 5 파일이고, lane 밖의 것이
둘이다 — `artifact-server.yaml` (2026-09-04) 과 `node-seed.yaml` (2026-09-08 의 `repo-seed.yaml`,
2026-09-18 부터 DaemonSet). lane 5 파일은 —
`values.yaml` · `controller-values.yaml` · `pod-template.yaml` · `job-hook.sh` ·
`job-hook-policy` (production 은 `/opt/arc/config`, fork 는 `/opt/arc/config/fork`).
`controller-values.yaml` 은 2026-09-01 부터 **lane 별**이다 (결정 27). 전역 판은 없다.
fork lane 은 `never` 태그를 달고 있으나, `arc_render` 를 이름으로 지정하면 그것이 풀린다.
그러니 한 번 돌리면 lane 넷을 다 대조할 수 있다.

⚠ **템플릿에 주석을 다시 넣지 마라 (2026-09-22, 티켓 47).** `.j2` 안의 `#` 은 렌더 결과에
그대로 들어가 ConfigMap 을 가른다. 값의 근거는 아래 "값의 근거" 절에 적는다. role 자신에
대한 설명이 꼭 필요하면 `{# #}` 를 쓴다 — 렌더 결과에 나오지 않는다.

ConfigMap 에 들어가는 값도 같은 템플릿을 쓴다 (`lookup('template', ...)`). 디스크의
파일과 ConfigMap 의 값이 바이트 동일한 것을 2026-08-24 에 확인했다.

## 값의 근거

템플릿에는 주석이 없다. 왜 이 값인지를 여기 적는다. 계약(워크플로와 IaC 가 양쪽에서
지켜야 하는 것)은 위 "계약면" 표가 맡는다 — 여기는 근거만 적는다.

### `arc-pod-template.yaml.j2`

| 자리 | 값 | 근거 |
|---|---|---|
| `spec.shareProcessNamespace` | `true` | PID 1 이 `/pause` 가 되어 좀비를 거둔다. 없으면 훅이 띄운 `tail -f /dev/null` 이 PID 1 인데 그것은 `wait(2)` 를 안 한다. CUBRID 서버는 double fork 로 떠서 PPID 가 1 이므로 좀비가 쌓이고 `cubrid server stop` 이 무한 대기한다 (2026-08-13 실물, 케이스 `bug_cubridsus2018` 6분 정지, 좀비 3) |
| `$job.imagePullPolicy` | `Always` | 태그가 `:latest` 가 아니라(`:build_rl8.10`·`:test_rl8.10`) k8s 기본값이 `IfNotPresent` 다. **태그 이름은 판을 고정하지 않는다** — 같은 태그의 digest 가 하루 안에 갈린 실측이 있다 (2026-08-24 `cff928900b68` → `7f2969dde863`) |
| `$job.command`·`args` | `sleep` 사본 `arc-keepalive` | 훅 기본값 `tail -f /dev/null` 은 테스트의 `xkill tail` 이 죽인다 (CUBRIDQA-1519, 2026-08-14 실증 — shell suite 의 해당 케이스 2건과 죽은 shard 2건이 일치). `sleep infinity` 도 안 된다 — `pkill sleep` 케이스가 있다 (`_01_utility/_38_csql/_enhance_csql03`). 이름으로 죽이는 호출 69개의 인자 36종 중 `arc-keepalive` 의 부분문자열은 없다. 훅의 `mergeContainerWithOptions` 가 `name`·`image` 만 보호하므로 이 값이 이긴다 |
| `$job.securityContext.privileged` | `true` | overlay `mount(2)` 에 필요하다. 운영 CircleCI job pod 도 privileged 다 |
| `$job.env.LOGNAME` | `root` | Actions 의 `shell: bash` 기본값이 `--noprofile --norc` 라 `/etc/profile` 이 안 돌고 값이 빈다. 운영 CircleCI 는 entrypoint 를 `bash -le` 로 불러서 `root` 다. `tbl_enc_06` 이 그 값으로 grep 패턴을 만들어 gha 에서만 실패했다 (5회 재현, 2026-09-02 CircleCI 대조로 확정). 영향은 그 케이스 하나다 (2026-09-03 전수). 훅은 `env` 만 뒤에 잇고 이름이 겹치면 나중 것이 이긴다 |
| `$job.resources.limits` | requests 와 짝 | limits 가 없으면 job pod 이 Burstable 이 되어 상한이 노드 전체다. 폭주하는 shard 하나가 같은 노드의 다른 shard 를 끌어내린다. 벽시계는 최장 shard 로 정해지므로 그것이 곧 손해다. 스케줄링은 requests 로만 정해진다 |
| `overlay-rw` (`/rw`) tmpfs `sizeLimit` | `arc_tmpfs_testcases` | 2026-08-24 fork full run 실측(shard 50) pod 당 최대 21,612MB = 32Gi 의 66%. 넘긴 pod 는 없다. ⚠ tmpfs 는 swap 이 없어 넘치면 축출이 아니라 노드 OOM 이다 |
| `build-overlay-rw` (`/build-rw`) | tmpfs, `arc_tmpfs_build` | 운영 CircleCI 는 여기가 디스크(`emptyDir: {}`)다. 테스트가 만드는 DB·로그·conf 가 이 층에 쌓이므로 디스크로 두면 최장 shard 가 늘어난다. 같은 실측에서 pod 당 최대 2,197MB = 16Gi 의 13.4%. ⚠ 그 실측은 shell 판이다 — sql·medium 은 DB 하나가 shard 내내 산다 (티켓 14, 2026-09-18). 이 값을 다시 잡을 때는 `gha-ci.yml` 의 `Publish results for collect` 가 매 run 찍는 `/rw (after CTP)`·`/build-rw (after CTP)` 를 읽어라 |
| `shared` 볼륨 `type` | `Directory` | 마운트가 없으면 결과를 노드 디스크에 흘리는 것보다 pod 이 안 뜨는 쪽이 낫다. `seed`·`cache` 는 `DirectoryOrCreate` 다 — 비면 워크플로가 첫 git 명령에서 죽는다 |
| `shared`·`seed`·`cache` 마운트 셋 | 따로 건다 | 부모 `/home/ci` 하나로 묶지 마라. FUSE 마운트는 bind 를 따라오지 않아 `shared` 가 빈 디렉토리로 보인다 |
| `metadata.labels` 의 `gha-ci.cubrid.org/lane` | lane 이름 | 훅이 이 labels 를 job pod 에 병합한다. job pod 을 lane 별로 가르는 유일한 칸이다 (티켓 17). 짝은 `monitoring.yml` 의 `metricLabelsAllowlist` — 한쪽만 적용하면 지표가 안 갈린다. ⚠ 이 파일은 정적이다(훅이 `yaml.load` 만 한다). job 마다 갈리는 값은 못 담는다 |
| `nodeSelector` | 두지 않는다 | 훅이 job pod 를 러너와 같은 노드에 `spec.nodeName` 으로 고정한다. nodeName 과 nodeSelector 가 어긋나면 kubelet 이 거부한다 |

### `arc-values.yaml.j2` · `arc-controller-values.yaml.j2`

| 자리 | 값 | 근거 |
|---|---|---|
| `controllerServiceAccount.namespace` | lane 의 namespace | lane 마다 컨트롤러가 자기 namespace 에 하나씩 있다 (결정 27). 차트가 이 SA 에 `<release>-gha-rs-manager` RoleBinding 을 그 namespace 안에 만든다 |
| `maxRunners` | `arc_max_runners` (inventory) | 동시 **job** 수다. ARC 는 job 1건에 pod 2개(러너 + job)를 쓴다 — CircleCI 는 1개다. ⚠ 지금 값과 그 재측정은 티켓 62 T2 가 맡는다 |
| `listenerTemplate` | 제어면에 못 박는다 | 리스너가 워커 pod 예산을 쓰면서 job 은 안 돌린다. 워커를 cordon 하는 동안에도 폴링이 이어져야 한다 (티켓 68). `containers: [- name: listener]` 는 장식이 아니라 CRD 의 필수 항목이다 — 이름이 `listener` 여야 컨트롤러가 사이드카가 아니라 리스너 컨테이너로 병합한다 |
| `template.metadata.labels` + `topologySpreadConstraints` | 한 덩어리다 | 러너 pod 의 requests 가 작아(cpu 100m / mem 256Mi) 스케줄러가 한 워커에 몰 수 있고, 훅이 job pod 를 따라 끌고 간다. 라벨이 없으면 제약이 아무 pod 도 못 고른다. ⚠ 이 제약을 job pod template 에는 넣지 마라 — 훅이 이미 노드를 정한다 |
| `flags.watchSingleNamespace` | lane 의 namespace | 컨트롤러는 AutoscalingListener 를 **자기 namespace** 에 만든다. 차트의 `manager_listener_role.yaml` 이 이 플래그와 무관하게 Role 을 `.namespace` 에 만들기 때문이다. 하나로 두 lane 을 관리하면 리스너가 둘 다 컨트롤러 namespace 로 몰린다 (2026-09-01 실측) |
| 컨트롤러의 `nodeSelector`·`tolerations` | 제어면 | 리스너와 같은 이유다 (티켓 68). 그 밖의 차트 기본값은 우리가 바꾸지 않는다 |
| CRD 4종(`*.actions.github.com`) | 손대지 않는다 | 클러스터 범위다. 차트가 처음 설치할 때 만들고 그 뒤 릴리스를 더 깔아도 다시 만들지 않는다 |

### `arc-job-hook.sh.j2` · `arc-job-hook-policy.j2`

| 자리 | 값 | 근거 |
|---|---|---|
| `MODE` | `enforce` | `observe` 는 기록만 하고 항상 통과시킨다. `deny-all` 은 거부 메커니즘이 실제로 도는지 보는 시험용이다 |
| `ALLOWED_EVENTS` | `arc_allowed_events` | `issue_comment` 를 허용하면 문지기가 러너(인프라)에서 워크플로(코드)로 옮겨 간다 — `gha-ci.yml` 의 gate 가 `author_association` 으로 판정한다. 그 판정이 서는 근거 = `issue_comment` 도 **기본 브랜치의 워크플로만** 실행한다 (2026-08-19 실측). `pull_request` 는 쓰기 권한을 요구하지 않는 유일한 항목이고, 전제는 저장소 설정 `Require approval for all external contributors` 다. `repository_dispatch` 는 뺐다 — develop 에서 그것을 쓰는 워크플로가 `runs-on: ubuntu-latest` 라 이 훅을 안 만난다. ⚠ 남는 위험 = 코멘트 하나가 러너 50개를 잡는다 |
| 모드 변경 | ConfigMap 만 갈아 끼운다 | helm 을 건드리지 않는다. 러너가 ephemeral 이라 다음 job pod 가 새 값을 마운트한다 |
| `hook.sh` | 순수 bash | 훅에 타임아웃 설정이 없다 — 스크립트가 스스로 짧게 끝나야 한다. `continue-on-error` 는 이 스크립트에 안 먹는다. ⚠ 이것이 깨지면 **모든 job 이 죽는다**. 되돌리는 길은 ConfigMap 을 고치는 것 하나다 |

### `arc-artifact-nginx.conf.j2` · `arc-artifact-server.yaml.j2` · 노드 seed

| 자리 | 값 | 근거 |
|---|---|---|
| `user root` | | 기본 사용자 `nobody` 로는 못 읽는 파일을 shard 가 남긴다 |
| `mime.types` | include 하지 않는다 | include 하면 `xml` 이 겹쳐 파싱이 깨진다. 그래서 `types` 를 직접 적는다 |
| `sendfile` | `off` | FUSE(GlusterFS) 위에서 믿을 수 없다 |
| Deployment 의 `checksum/config` 애너테이션 | nginx.conf 의 sha1 | nginx 는 실행 중에 설정을 다시 안 읽는다. ConfigMap 만 갱신하면 도는 nginx 는 옛 설정 그대로다 |
| 미러의 refspec | `+refs/heads/*` · `+refs/tags/*` | `clone --bare` 는 refspec 을 안 남겨 `remote update` 가 무동작이다. **`--mirror` 는 쓰지 마라** — GitHub 이 광고하는 `refs/pull/*` 수천 개까지 받는다 |
| 기본 브랜치 물어보기 | `HEAD` 로 묻지 마라 | `cubrid-testcases` 에 `refs/heads/HEAD` 라는 브랜치가 있어 미러에서 그 이름이 모호하다 |
| worktree 세대 | 로컬 미러에서 clone | 같은 디스크라 git 이 객체를 하드링크한다. ⚠ 세대의 `origin` 은 GitHub URL 이어야 한다 — pod 의 정렬 단계가 `origin` 으로 fetch 하는데 로컬 미러 경로면 상류를 못 본다 |

## 자격증명

두 lane 다 **GitHub App** 으로 등록한다. PAT 는 쓰지 않는다.
role 이 vault 에서 secret 을 만들고 그 태스크에 `no_log: true` 가 걸려 있다.

| lane | vault 변수 | App |
|---|---|---|
| production | `vault_arc_gh_app_*` | `cubrid-arc-runner-bot` → `CUBRID/cubrid` |
| production light | `vault_arc_gh_app_*` | 같은 App. secret 만 lane 마다 따로 만든다 |
| fork | `vault_arc_fork_gh_app_*` | `cubrid-arc-fork-runner-bot` → `tw-kang/cubrid` |
| fork light | `vault_arc_fork_gh_app_*` | 같은 App. secret 만 lane 마다 따로 만든다 |

디스크의 PEM 은 지웠다. **vault 가 유일한 사본이다.**

## kubeconfig

이 role 은 `inventory/<env>/artifacts/kubectl.sh` 를 **쓰지 않는다.** master 위에서
`kubernetes.core` 로 클러스터를 부르고, 그때 master 자신의 `/root/.kube/config` 를 쓴다.
`roles/circleci` 와 같은 방식이다. 그래서 artifacts 의 클라이언트 인증서 만료와 무관하다.

## 관련 파일

| 무엇 | 어디 |
|---|---|
| 값 | `inventory/production/group_vars/arc/runner.yml` |
| 자격증명 | `inventory/production/group_vars/all/vault.yml` |
| playbook | `playbooks/deploy-arc.yml` |
| 산출물 보관 | `roles/glusterfs` 의 `glusterfs_cleanup_dirs` |
| 노드 seed | `tasks/repo_seed.yml` · `templates/arc-repo-seed-daemonset.yaml.j2` · `templates/arc-repo-seed.sh.j2` |
| 볼륨의 둘째 클라이언트 | `roles/glusterfs` 의 `glusterfs_extra_mounts` |
