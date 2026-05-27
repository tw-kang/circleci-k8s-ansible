# Operations

Day-2 운영 가이드. 클러스터/모니터링 초기 설치는 `docs/installation.md`, 모니터링 세부는
`docs/monitoring.md`, CircleCI 는 `docs/circleci.md` 를 참조.

---

## 모드 매트릭스

| 시나리오 | ansible-playbook 명령 | 위임 kubespray playbook |
|---|---|---|
| cluster-only | `ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml --vault-password-file .vault-password` | `cluster.yml` |
| deploy-monitoring | `ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml --vault-password-file .vault-password` | — |
| deploy-monitoring-full | `ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring-full.yml --vault-password-file .vault-password` | — |
| deploy-external-monitoring | `ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-external-monitoring.yml --vault-password-file .vault-password` | — |
| deploy-circleci | `ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-circleci.yml --vault-password-file .vault-password` | — |
| add-node | `ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml --vault-password-file .vault-password` | `scale.yml` |
| remove-node | `ansible-playbook -i inventory/production/hosts.ini playbooks/remove-node.yml --vault-password-file .vault-password --extra-vars "node=NAME"` | `remove-node.yml` |
| upgrade-cluster | `ansible-playbook -i inventory/production/hosts.ini playbooks/upgrade-cluster.yml --vault-password-file .vault-password` | `upgrade-cluster.yml` |
| reset-cluster | `ansible-playbook -i inventory/production/hosts.ini playbooks/reset-cluster.yml --vault-password-file .vault-password` | `reset.yml` |

add-node / remove-node / reset-cluster 는 GlusterFS 처리를 kubespray 위임 전후에 인라인으로
수행한다. 각 playbook 이 `roles/glusterfs` 안의 특정 task 파일을
`tasks_from:` 으로 직접 dispatch 한다 (`add-node.yml` → `install.yml` + `add_node.yml`,
`remove-node.yml` → `remove_node.yml`, `reset-cluster.yml` → `reset.yml`).

---

## kubectl 접근 (kubespray artifacts)

kubespray 배포 후 `inventory/production/artifacts/` 에 생성된다.

```bash
# wrapper 스크립트 사용 (kubeconfig 내장)
inventory/production/artifacts/kubectl.sh get nodes

# 또는 바이너리를 PATH 에 추가
sudo cp inventory/production/artifacts/kubectl /usr/local/bin/kubectl
mkdir -p ~/.kube
cp inventory/production/artifacts/admin.conf ~/.kube/config
kubectl get nodes
```

`admin.conf` 는 `inventory/production/artifacts/admin.conf` 에 위치한다. reset-cluster
실행 시 `artifacts/` 디렉터리 전체가 삭제되므로 별도 보관이 필요하다.

---

## 노드 수명 주기

### 노드 추가

1. `inventory/production/hosts.ini` 의 `[kube_node]` 섹션에 신규 노드 추가.
2. playbook 실행:
   ```bash
   ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml \
     --vault-password-file .vault-password
   ```
   내부 순서: bind mount 생성(`/home/containerd-data`, `/home/kubelet-data`, `/home/tc-repo`)
   → kubespray `scale.yml` → GlusterFS `install.yml` + `add_node.yml`.
3. external-monitoring 레이블 갱신이 필요한 경우 deploy-external-monitoring 도 실행.
4. 검증:
   ```bash
   inventory/production/artifacts/kubectl.sh get nodes
   inventory/production/artifacts/kubectl.sh get nodes -o wide
   df -h /home/build-cache   # GlusterFS 마운트 확인 (신규 노드에서)
   ```

### 노드 제거

1. 대상 노드를 cordon/drain:
   ```bash
   inventory/production/artifacts/kubectl.sh drain NODE_NAME \
     --ignore-daemonsets --delete-emptydir-data
   ```
2. playbook 실행:
   ```bash
   ansible-playbook -i inventory/production/hosts.ini playbooks/remove-node.yml \
     --vault-password-file .vault-password \
     --extra-vars "node=NODE_NAME"
   ```
   내부 순서: GlusterFS `remove_node.yml` → kubespray `remove-node.yml` → bind mount
   해제 + 데이터 디렉터리 삭제(`/home/containerd-data`, `/home/kubelet-data`, `/home/tc-repo`).
3. `inventory/production/hosts.ini` 에서 해당 노드 항목 제거.
4. 검증:
   ```bash
   inventory/production/artifacts/kubectl.sh get nodes
   gluster peer status   # 제거한 노드에서 실행
   ```

### 클러스터 업그레이드

1. `inventory/production/group_vars/all/kubespray.yml` 의 `kube_version` 값을 목표 버전으로
   변경 (현재: `1.31.9`).
2. etcd 스냅샷 등 백업을 먼저 완료.
3. playbook 실행:
   ```bash
   ansible-playbook -i inventory/production/hosts.ini playbooks/upgrade-cluster.yml \
     --vault-password-file .vault-password
   ```
   kubespray `upgrade-cluster.yml` 에 위임한다.
4. 검증:
   ```bash
   inventory/production/artifacts/kubectl.sh version
   inventory/production/artifacts/kubectl.sh get nodes
   inventory/production/artifacts/kubectl.sh get pods -A
   ```

### Reset cluster (파괴적 작업)

모든 Kubernetes 컴포넌트, 컨테이너 데이터, 클러스터 설정, GlusterFS 볼륨이 삭제된다.
이 작업은 되돌릴 수 없다.

```bash
ansible-playbook -i inventory/production/hosts.ini playbooks/reset-cluster.yml \
  --vault-password-file .vault-password
```

내부 순서: GlusterFS `reset.yml` → kubespray `reset.yml` → `/opt/circleci`, bind mount
디렉터리 삭제 → `artifacts/` 디렉터리 삭제.

완료 후 노드 재부팅을 권장한다.

---

## GlusterFS (build cache)

| 항목 | 값 |
|---|---|
| 볼륨 이름 | `build-cache` |
| replica count | 2 |
| brick 경로 | `/home/gluster/brick1` |
| 마운트 포인트 | `/home/build-cache` (worker 노드) |
| builds 디렉터리 | `/home/build-cache/builds` |

**자동 cleanup CronJob** (`roles/glusterfs/templates/build-cache-cleanup-cronjob.yaml.j2`)

| 항목 | 값 |
|---|---|
| namespace | `kube-system` |
| schedule | `0 3 * * *` (매일 03:00 KST, `timeZone: Asia/Seoul`) |
| retention | 3일 (`-mtime +3`) |
| image | `busybox:1.36` |
| nodeSelector | `node-role.kubernetes.io/worker: ""` |
| concurrencyPolicy | `Forbid` |

`defaults/main.yml` 에서 조정 가능한 변수:

```yaml
glusterfs_cleanup_cronjob_enabled: true      # CronJob 배포 여부
glusterfs_cleanup_schedule: "0 3 * * *"      # cron 표현식
glusterfs_cleanup_retention_days: 3          # 보관 일수
glusterfs_replica_count: 2                   # GlusterFS replica 수
```

**Playbook → GlusterFS task 디스패치** (각 playbook 이 `tasks_from:` 으로 직접 호출):

| Playbook | `roles/glusterfs/tasks/` 호출 |
|---|---|
| `cluster-only.yml` | role 기본 진입 (`main.yml`, `glusterfs_action: install` 기본값) |
| `add-node.yml` | `install.yml` + `add_node.yml` |
| `remove-node.yml` | `remove_node.yml` |
| `reset-cluster.yml` | `reset.yml` |

`glusterfs_action` 변수는 `main.yml` 의 dispatch 분기에만 쓰이며, 위 playbook 들은 이를
거치지 않고 task 파일을 직접 호출한다. 별도 액션 변수를 사용자에게 노출하지 않는다.

GlusterFS 상태 확인:

```bash
gluster peer status
gluster volume info build-cache
gluster volume status build-cache
```

---

## Vault 관리

`inventory/production/group_vars/all/vault.yml` 은 AES256 암호화되어 있다.
**vault 값을 평문으로 출력하거나 커밋하지 않는다.**

```bash
# 신규 생성
ansible-vault create inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password

# 편집
ansible-vault edit inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password

# 비밀번호 변경
ansible-vault rekey inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password

# 내용 확인 (터미널에서만)
ansible-vault view inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password
```

**production vault 키 목록** (값 아님):

- `vault_circleci_token` — CircleCI self-hosted runner 등록 토큰
- `vault_grafana_admin_password` — Grafana admin 계정 비밀번호
- `vault_teams_webhook_url` — MS Teams Power Automate Workflow trigger URL

staging vault (`inventory/staging/group_vars/all/vault.yml`) 는 현재 암호화되지 않은
plaintext placeholder 다 (파일 헤더에 `# This file should be encrypted with ansible-vault`
주석 포함). staging 에 vault 키가 필요해지면 `ansible-vault encrypt` 로 먼저 암호화한
뒤 위 `ansible-vault edit` 워크플로를 사용한다.

---

## 백업

### etcd 스냅샷 (컨트롤 플레인 노드에서 실행)

```bash
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-snapshot-$(date +%Y%m%d%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 스냅샷 유효성 검증
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-snapshot-*.db
```

### 설정 백업

```bash
tar czf circleci-k8s-config-$(date +%Y%m%d).tar.gz \
  inventory/production/group_vars/ \
  inventory/production/hosts.ini \
  inventory/production/artifacts/
```

`artifacts/admin.conf` 에는 클러스터 접근 자격증명이 포함되므로 안전한 위치에 보관한다.

---

## 인증서 관리

```bash
# 인증서 만료일 확인 (컨트롤 플레인 노드)
kubeadm certs check-expiration

# 인증서 갱신
kubeadm certs renew all

# kubelet 재시작 (갱신 반영)
systemctl restart kubelet

# 갱신 후 확인
kubeadm certs check-expiration
```

---

## 로그와 진단

```bash
# 노드 데몬 로그
journalctl -u kubelet -f
journalctl -u containerd -f

# 컨트롤 플레인 컴포넌트 로그
kubectl logs -n kube-system -l component=kube-apiserver --tail=100
kubectl logs -n kube-system -l component=kube-controller-manager --tail=100
kubectl logs -n kube-system -l component=kube-scheduler --tail=100

# 클러스터 이벤트 (최신순)
kubectl get events --sort-by='.metadata.creationTimestamp' -A

# cleanup CronJob 로그 (Pod 라벨이 없으므로 이름으로 조회)
kubectl get pods -n kube-system | grep build-cache-cleanup
kubectl logs -n kube-system <pod-name> --tail=50
```

---

## DNS 트러블슈팅

`resolvconf_mode: none` 설정(`inventory/production/group_vars/k8s_cluster/k8s-cluster.yml:209`)
으로 인해 kubespray 가 `/etc/resolv.conf` 를 관리하지 않는다. NetworkManager 가 DNS 를
관리한다.

NodeLocalDNS 가 활성화되어 있다(`enable_nodelocaldns: true`, IP `169.254.25.10`).
kube-proxy 는 ipvs 모드로 동작한다.

```bash
# 노드 외부 DNS 확인
cat /etc/resolv.conf
nslookup kubernetes.default.svc.cluster.local 169.254.25.10

# CoreDNS 상태
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# NodeLocalDNS 상태
kubectl get pods -n kube-system -l k8s-app=node-local-dns
kubectl logs -n kube-system -l k8s-app=node-local-dns --tail=50

# pod 내부 DNS 디버그
kubectl run dns-debug --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local
```

---

## 자주 발생하는 문제

### node NotReady

```bash
kubectl describe node NODE_NAME
systemctl status kubelet
journalctl -u kubelet -n 50 --no-pager
```

### Calico CNI 이상

```bash
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50
kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers
```

### service discovery / kube-proxy

kube-proxy 는 ipvs 모드로 동작한다. 메트릭 엔드포인트는 `0.0.0.0:10249`
(`kube_proxy_metrics_bind_address` 설정 — `kubespray.yml:170`).

```bash
kubectl get pods -n kube-system -l k8s-app=kube-proxy
ipvsadm -ln   # IPVS 규칙 확인 (노드에서)
```

### 디스크 압박

containerd 데이터는 `/home/containerd-data` → `/var/lib/containerd` bind mount 로 관리된다.
`/home` 파티션 여유 공간 확인이 우선이다.

```bash
df -h /home
mount | grep containerd      # bind mount 상태
mount | grep kubelet         # kubelet bind mount 상태
du -sh /home/containerd-data /home/kubelet-data /home/build-cache
```

CronJob 이 정상 실행되지 않는 경우 수동으로 오래된 build 삭제:

```bash
find /home/build-cache/builds -mindepth 1 -maxdepth 1 -type d -mtime +3 -print
# 확인 후 삭제
find /home/build-cache/builds -mindepth 1 -maxdepth 1 -type d -mtime +3 -exec rm -rf {} \;
```

---

## 사전 점검

playbook 실행 전 아래 순서로 연결 및 설정을 검증한다.

```bash
# 전체 호스트 ping
ansible all -i inventory/production/hosts.ini -m ping

# 인벤토리 파싱 확인
ansible-inventory -i inventory/production/hosts.ini --list

# dry-run (변경 없이 계획 확인)
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-monitoring.yml \
  --vault-password-file .vault-password --check

# 특정 태그만 dry-run
ansible-playbook -i inventory/production/hosts.ini playbooks/add-node.yml \
  --vault-password-file .vault-password --check --tags verification
```

---

## 참고

- Kubespray 문서: `3rdparty/kubespray/docs/`
- Kubespray operations 가이드: `3rdparty/kubespray/docs/operations/`
- GlusterFS 기본값: `roles/glusterfs/defaults/main.yml`
- Production k8s 클러스터 설정: `inventory/production/group_vars/k8s_cluster/k8s-cluster.yml`
- Kubespray 공통 변수: `inventory/production/group_vars/all/kubespray.yml`
