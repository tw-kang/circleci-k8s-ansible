# roles/arc — GitHub Actions 러너 (ARC)

`CUBRID/cubrid` 의 `gha-ci.yml` 을 태우는 self-hosted 러너를 띄운다.
Actions Runner Controller 의 `gha-runner-scale-set` 차트를 쓴다.

CUBRIDQA-1537 이 만들었다. 그 전에는 `kubectl` 과 `helm` 을 손으로 쳤고
원본 파일이 연구용 스크래치 디렉토리에만 있었다.

## 무엇을 만드는가

lane 하나마다 이렇게 만든다.

| 자원 | 이름 |
|---|---|
| namespace | `{{ arc_namespace }}` / fork `{{ arc_fork_namespace }}` |
| secret | `{{ arc_release }}-gh-app` |
| ConfigMap | `{{ arc_release }}-pod-template` · `{{ arc_release }}-job-hook` |
| helm 릴리스 | `{{ arc_release }}` |

lane 과 별개로, **산출물 열람 서버**를 하나 만든다 (아래 절).

| 자원 | 이름 |
|---|---|
| ConfigMap | `{{ arc_artifact_server_name }}-nginx` |
| Deployment | `{{ arc_artifact_server_name }}` |
| Service (NodePort) | `{{ arc_artifact_server_name }}` |

렌더한 파일은 master 의 `{{ arc_config_path }}` 에 남는다 (fork 는 그 아래 `fork/`).

ARC 컨트롤러(`arc-controller`)는 **이 role 이 소유하지 않는다.** 지금 설치 상태를
`controller-values.yaml` 로 받아 적기만 한다. `arc_controller_manage: true` 로 바꿔야
helm 이 돈다.

## 쓰는 법

```bash
ansible-playbook playbooks/deploy-arc.yml                    # production (ns gha-ci)
ansible-playbook playbooks/deploy-arc.yml --tags arc_fork    # fork       (ns default)
ansible-playbook playbooks/deploy-arc.yml --tags arc_render  # 렌더만. 클러스터를 안 건드린다
ansible-playbook playbooks/deploy-arc.yml --tags arc_artifacts  # 산출물 서버만
```

⚠ **태그 없는 실행은 production 만 띄운다.** `roles/circleci` 는 태그가 없으면 lane 둘을
함께 띄우지만 여기는 다르다. 두 lane 이 **릴리스 이름을 공유**하므로 이동 순서를 지켜야
한다 (아래). 그래서 fork lane 에 `never` 태그를 걸었다.

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
| GlusterFS 루트 | `CI_ROOT=/home/build-cache/gha-ci` | hostPath + 보관 CronJob 의 `glusterfs_cleanup_dirs` | 발행물이 영구 누적 |
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

⚠ **3 단계 전에 워커에서 한 줄이 필요하다.** hostPath 가 `type: Directory` 라 없으면 pod 이
안 뜬다. gluster 볼륨이라 워커 한 대에서 하면 복제된다.

```bash
mkdir -p /home/build-cache/_fork
```

심링크는 만들지 마라. `_fork/cubrid-mirror -> ../cubrid-mirror` 는 **호스트에서만** 풀린다.
fork pod 안에서는 `_fork` 만 `/home/build-cache` 로 마운트되므로 `..` 가 bind mount 경계에서
멈추고 `/home/cubrid-mirror` 를 가리킨다. 그런 경로는 없다 (2026-08-24 실측).
그래서 pod template 이 미러를 제 경로에 겹쳐 마운트한다 — `mirror_hostpath` 를 봐라.

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
http://192.168.1.48:30080/runs/<run_id>/          결과·실패 증거
http://192.168.1.48:30080/logs/<run_id>-build.log 빌드 로그
```

정한 것 다섯이다.

1. **nginx `autoindex` + hostPath 읽기 전용 + NodePort.** 웹 UI 를 만들지 않는다.
2. **pod 는 워커에 뜨고, URL 은 마스터 IP 다.** GlusterFS 는 `kube_node` 만 마운트한다
   (`playbooks/cluster-only.yml`). NodePort 는 모든 노드 IP 에서 답하므로, 사람들이 이미
   Grafana(32000)로 쓰는 `192.168.1.48` 을 URL 에 쓴다. 워커의 192.168.2.x 를 노출하지 않는다.
3. **서빙 루트는 `gha-ci` 하위다.** `arc_fork_build_cache_root`(`_fork`)는 바깥 기여자의
   PR 이 쓰는 자리라 서빙하지 않는다. fork PR 은 빌드만 하므로 summary 자체를 안 만든다.
4. **인증이 없다.** 사내망·읽기 전용이다. 외부에서는 VPN 을 탄다.
5. **`.xml` · `.log` · `.data` · `.list` · `.tsv` 는 `text/plain`** 으로 내보내 브라우저에서
   바로 읽힌다. 나머지는 `application/octet-stream` 이라 내려받는다.
   `runs/*/testtools/` 는 404 다 — 실패 run 하나당 59MB 짜리 CTP seed 라 읽을 사람이 없다.

⚠ **링크의 수명은 보관 정책이 정한다.** `roles/glusterfs` 의 `glusterfs_cleanup_dirs` 가
`gha-ci/runs` 를 7 일 뒤 지운다. **2026-09-04 확인: 클러스터에 배포된 CronJob 에는 그
항목이 없다.** role 기본값에는 있는데 매니페스트를 재적용하지 않았다 — 그래서 지금은
아무것도 안 지워진다. `--tags glusterfs_cleanup` 재적용이 그것을 고친다.

⚠ **kube-proxy 가 ipvs 모드라 loopback 으로는 NodePort 가 안 열린다.** 노드에서 확인할 때
`127.0.0.1:30080` 이 아니라 노드 IP 를 써라. 이것은 Grafana 도 마찬가지다.

## 검증 — 골든 파일 대조

Ansible 에 테스트 프레임워크가 없다. **골든 파일 하나가 성공 기준이다.**

> role 이 렌더한 4개 파일이 지금 클러스터에 적용된 것과 **바이트 동일**해야 한다.
> 일부러 갈라 놓은 것은 아래 표에 적는다.

```bash
ansible-playbook playbooks/deploy-arc.yml --tags arc_render   # 클러스터를 안 건드린다
ansible arc -m fetch -a "src=/opt/arc/config/pod-template.yaml dest=/tmp/g/ flat=yes"
diff /tmp/g/pod-template.yaml <path>/ARC-1526-pod-template.yaml
```

⚠ **대조는 `--check` 로 하지 않는다.** `--check` 에서는 `template` 모듈이 파일을 쓰지
않으므로 견줄 대상이 안 생긴다. `--tags arc_render` 가 그 자리를 대신한다 —
namespace·secret·ConfigMap·helm 을 전부 건너뛴다. `--check` 는 배포 직전 예행 연습에 쓴다.

`--tags arc_render` 는 master 에 **11 파일**을 쓴다. lane 마다 5 파일이고, lane 밖의
`artifact-server.yaml` 이 하나다 (골든 없음 — 2026-09-04 에 새로 들어왔다). lane 5 파일은 —
`values.yaml` · `controller-values.yaml` · `pod-template.yaml` · `job-hook.sh` ·
`job-hook-policy` (production 은 `/opt/arc/config`, fork 는 `/opt/arc/config/fork`).
`controller-values.yaml` 은 2026-09-01 부터 **lane 별**이다 (결정 27). 전역 판은 없다.
fork lane 은 `never` 태그를 달고 있으나,
`arc_render` 를 이름으로 지정하면 그것이 풀린다. 그러니 한 번 돌리면 두 lane 을 다
대조할 수 있다.

⚠ **`.j2` 안의 `#` 주석을 고치기 전에 이 절을 읽어라.** 그 주석은 골든 파일이 만들어진
때의 근거이고, 렌더 결과에 그대로 들어간다. 한 글자만 고쳐도 ConfigMap 이 바뀌고 골든
대조가 갈린다. 그래도 고쳐야 하면 **아래 표에 무엇이 갈렸는지 적어라.**
`DECISIONS-1537-naming-and-layout.md` §7 예외표에도 같이 적는다. 적지 않으면 다음
사람이 대조 실패를 회귀로 읽는다. role 에 필요한 설명은 `{# #}` 로 넣는다 — 렌더 결과에
나오지 않으므로 대조를 갈라 놓지 않는다.

ConfigMap 에 들어가는 값도 같은 템플릿을 쓴다 (`lookup('template', ...)`). 디스크의
파일과 ConfigMap 의 값이 바이트 동일한 것을 2026-08-24 에 확인했다.

2026-08-24 대조 결과다. 그 뒤에 일부러 갈라 놓은 것도 같이 적었다.

| 파일 | 골든 | 결과 |
|---|---|---|
| `pod-template.yaml` | `ARC-1526-pod-template.yaml` | `#` 주석 4곳만 다르다 (아래) |
| `job-hook.sh` | `ARC-1528-job-hook.sh` | 바이트 동일 |
| `job-hook-policy` | `ARC-1526-job-hook-policy.env` | 바이트 동일 |
| `values.yaml` | `ARC-1526-values.yaml` | 아래 둘만 다르다 |
| `controller-values.yaml` | 없다 | 지금 상태를 받아 적은 것이다 |

`values.yaml` 이 일부러 다르게 나오는 것 둘이다.

1. `githubConfigSecret` 이 `cubridqa-1528-gh-app` → `cubrid-arc-gh-app`. 이름에서 티켓
   번호를 뺐다
2. `topologySpreadConstraints` **와 그것이 고르는 pod 라벨**을 되살렸다. PoC 판에는
   있었고 `ARC-1526-values.yaml` 에서 빠졌다. 러너 pod 의 requests 가 작아
   (cpu 100m / mem 256Mi) 스케줄러가 한 워커에 몰아 배치할 수 있고, 훅이 job pod 를
   `spec.nodeName` 으로 끌고 간다.

   ⚠ **둘은 한 덩어리다.** `arc-values.yaml.j2:92-94` 가 `template.metadata.labels` 에
   `{{ arc_lane.release }}-runner: "true"` 를 더하고, `:100-102` 의 `labelSelector.
   matchLabels` 가 그것을 고른다. 라벨이 없으면 제약이 아무 pod 도 못 고른다. 골든
   `ARC-1526-values.yaml` 의 `template:` 아래에는 `metadata:` 블록 자체가 없으므로,
   대조하면 **주석이 아니라 실제 렌더 줄 셋이 늘어난 것**으로 보인다. 그것이 맞다.

`pod-template.yaml` 이 일부러 다르게 나오는 것 다섯이다. **넷은 `#` 주석만 갈렸고,
`$job` 의 `env` 하나가 값이 갈린다.** 자리는 `roles/arc/templates/arc-pod-template.yaml.j2`
기준이다. 줄 번호는 밀릴 수 있으므로 옆에 적은 앵커로 찾아라.

| 자리 | 무엇이 갈렸나 | 왜 |
|---|---|---|
| `:91` — `$job` 컨테이너의 `imagePullPolicy` 근거 주석 | 이미지 태그 이름을 `:rl8.10`·`:test_shell` → `:build_rl8.10`·`:test_rl8.10` 로 | 골든이 적은 두 태그를 워크플로가 안 쓴다. 틀린 이름이 근거로 남아 있었다 (커밋 `959700d`) |
| `:96-99` — 같은 주석 블록 | `:build_rl8.10` 의 내용이 하루 안에 바뀐 실측 4줄을 더했다 (digest `cff928900b68` → `7f2969dde863`) | `imagePullPolicy: Always` 가 왜 필요한지의 실제 근거다. 태그 이름은 판을 고정하지 않는다 (커밋 `959700d`) |
| `:214-218` — `arc_tmpfs_testcases` 위 주석 | `/rw` tmpfs `sizeLimit` 근거를 fork full run 실측으로 바꿨다 | 골든의 `0.92GiB` 는 CircleCI 워크로드의 동시 평균이다. `sizeLimit` 이 걸리는 pod 당 최대가 아니다. 실측은 pod 당 최대 21,612MB = 32Gi 의 66% 다 (커밋 `5739dcc`) |
| `:229-238` — `arc_tmpfs_build` 위 주석 | `/build-rw` tmpfs `sizeLimit` 근거와 후속 확인 방법을 실측으로 바꿨다 | 같은 이유다. 후속 확인은 `gha-ci.yml` 의 `Publish results for collect` 가 매 run 찍는 `/rw (peak)`·`/build-rw (peak)` 를 읽는다 (커밋 `5739dcc`) |
| **`$job` 의 `env` (`securityContext` 바로 아래)** — `LOGNAME: root` **새로 추가** | 골든에는 `$job` 에 `env` 블록 자체가 없다. **이것은 주석이 아니라 값이 갈리는 항목이다.** 대조하면 렌더 줄 셋이 늘어난 것으로 보인다 — 그것이 맞다 | Actions 의 `shell: bash` 기본값이 `--noprofile --norc` 라 `/etc/profile` 이 안 돌고 `LOGNAME` 이 빈 값이 된다. 운영 CircleCI 는 entrypoint 를 `bash -le` 로 불러서 `LOGNAME=root` 다. `tbl_enc_06` 이 그 변수로 grep 패턴을 만들어 gha 에서만 실패했다 (5회 재현, 2026-09-02 CircleCI 대조로 확정). 두 lane 다 적용한다 — fork lane 도 같은 이미지·같은 셸이다 |
| **`values.yaml:67`** — `controllerServiceAccount.namespace` | 골든은 `default` 다. production lane 은 이제 `gha-ci` 를 쓴다 | lane 마다 컨트롤러가 자기 namespace 에 하나씩 있다 (결정 27). fork lane 은 `default` 그대로라 갈리지 않는다 |
| **`values.yaml:63-65`** — 그 위 주석 3줄 | 왜 lane namespace 인지, 차트가 그 SA 에 무슨 RoleBinding 을 만드는지 적었다 | 값만 바뀌면 다음 사람이 골든과의 차이를 회귀로 읽는다 |

⚠ **`nodeSelector` 는 pod template 에 넣지 마라.** 훅이 job pod 를 러너와 같은 노드에
`spec.nodeName` 으로 고정한다. nodeName 과 nodeSelector 가 어긋나면 kubelet 이 거부한다.

## 자격증명

두 lane 다 **GitHub App** 으로 등록한다. PAT 는 쓰지 않는다.
role 이 vault 에서 secret 을 만들고 그 태스크에 `no_log: true` 가 걸려 있다.

| lane | vault 변수 | App |
|---|---|---|
| production | `vault_arc_gh_app_*` | `cubrid-arc-runner-bot` → `CUBRID/cubrid` |
| fork | `vault_arc_fork_gh_app_*` | `cubrid-arc-fork-runner-bot` → `tw-kang/cubrid` |

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
