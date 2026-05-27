# 설치

## 사전 요구사항

**제어 머신**

- Python 3.10+, Ansible 9.13+, git, ssh

**대상 Kubernetes 노드**

- OS: Rocky 8/9, CentOS 8/9, AlmaLinux 8/9, RHEL 8/9, Ubuntu 20.04/22.04
- 노드당 최소 RAM 2 GB
- 루트 SSH 접근 (공개 키 전용)
- Python 인터프리터는 `/opt/miniconda3/bin/python` 에 설치되어 있어야 한다 — `ansible.cfg` 가 모든 관리 노드 플레이에 `interpreter_python` 을 이 경로로 지정한다

**외부 호스트 (프로덕션 전용)**

- sudo SSH 접근이 가능한 CentOS 7 또는 Rocky 8
- node_exporter 스크레이핑용 포트 9100 개방

---

## 제어 머신 설정

```bash
git clone <repo-url> circleci-k8s-ansible
cd circleci-k8s-ansible
git submodule update --init --recursive
```

Python 의존성을 설치한다:

```bash
pip install -r requirements.txt
```

`requirements.txt` 고정 버전: `ansible==9.13.0`, `kubernetes>=31.0.0,<32.0.0`, `cryptography`, `jmespath`, `netaddr`, `PyYAML`.

SSH 공개 키를 모든 노드(K8s 노드 및 외부 호스트)에 배포한다:

```bash
ssh-copy-id root@<node-ip>
```

**Vault 패스워드 파일 (프로덕션 전용)**

`ansible.cfg` 에 `vault_password_file = .vault-password` 가 설정되어 있다. vault 암호화 실행 전에 파일을 생성한다:

```bash
echo '<your-vault-password>' > .vault-password
chmod 600 .vault-password
```

---

## K8s 대상 노드 준비

플레이북 실행 전 노드마다 한 번씩 수행하는 절차다.

### Python 3.10+ (Miniconda)

`ansible.cfg` 는 `interpreter_python = /opt/miniconda3/bin/python` 으로 고정되어 있다. 모든 노드에 해당 경로로 Miniconda를 설치한다:

```bash
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p /opt/miniconda3
```

### firewalld

```bash
systemctl disable --now firewalld
```

### DNS

`k8s-cluster.yml` 에 `resolvconf_mode: none` 이 설정되어 있어 Kubespray 가 `/etc/resolv.conf` 를 관리하지 않는다. 클러스터 배포 전에 NetworkManager 또는 `/etc/resolv.conf` 직접 편집을 통해 DNS를 수동으로 설정한다.

### SSD 쓰기 캐시 (선택)

노드가 SSD를 사용하는 경우 전원 손실 시 데이터 손실을 방지하기 위해 쓰기 캐시를 비활성화한다:

```bash
hdparm -W 0 /dev/sdX
```

### 테스트 리포 사전 클론 (워커 노드, 선택)

CircleCI 워커 노드는 sparse-checkout 테스트 리포를 `/home/tc-repo/cubrid-testcases-private-ex` 에 사전 클론할 수 있다:

```bash
mkdir -p /home/tc-repo
git -C /home/tc-repo clone --filter=blob:none --no-checkout <repo-url> cubrid-testcases-private-ex
git -C /home/tc-repo/cubrid-testcases-private-ex sparse-checkout set <paths>
git -C /home/tc-repo/cubrid-testcases-private-ex checkout
```

> **참고:** containerd 및 kubelet 바인드 마운트(`/home/containerd-data` → `/var/lib/containerd`, `/home/kubelet-data` → `/var/lib/kubelet`)는 `playbooks/cluster-only.yml` 이 자동으로 생성한다. 수동 마운트 설정은 불필요하다.

---

## 외부 호스트 준비 (프로덕션 전용)

각 외부 호스트에 다음이 갖춰져 있어야 한다:

- Rocky 8 또는 CentOS 7 OS
- `root@authorized_keys` 에 컨트롤러의 SSH 공개 키
- Prometheus 파드 hostIP 에서 포트 9100 접근 가능

각 호스트를 `inventory/production/external-nodes.ini` 의 `[external_host]` (베어메탈) 또는 `[external_vm]` (가상 머신) 아래에 추가한다. 호스트별 필수 변수:

```ini
hostname  ansible_host=<ip>  distribution=<centos7|rocky8> \
          ansible_python_interpreter=<path> \
          type=<test|service|infra>  category=<sub-tag> \
          owner_email_primary=<UPN>  owner_email_secondary=<UPN>
```

`owner_email_secondary` 는 선택 사항으로, 단일 소유자 호스트에서는 생략한다. `type` 과 `category` 모두 Prometheus 레이블로 내보내어 Teams 알림 카드에 표시된다.

`[external_nodes]` 그룹은 `external_host` 와 `external_vm` 의 합집합이며 `external-monitoring` 역할이 이를 소비한다.

---

## 인벤토리 설정

### hosts.ini

Kubespray 및 CircleCI 플레이북에 필요한 그룹:

```ini
[kube_control_plane]
k8s-master-01  ansible_host=<ip>  ansible_user=root

[etcd:children]
kube_control_plane

[kube_node]
k8s-worker-01  ansible_host=<ip>  ansible_user=root
k8s-worker-02  ansible_host=<ip>  ansible_user=root

[k8s_cluster:children]
kube_control_plane
kube_node

[circleci:children]
kube_control_plane
```

### external-nodes.ini (프로덕션 전용)

그룹: `external_host`, `external_vm`, `external_nodes`. 스테이징 파일은 실제 호스트가 없는 스텁이다.

### group_vars 구성

| 파일 | 범위 |
|------|------|
| `group_vars/all/vars.yml` | 사이트 전역 변수 |
| `group_vars/all/kubespray.yml` | Kubernetes 버전(`1.31.9`), kubelet 튜닝, 축출 임계값 |
| `group_vars/all/containerd.yml` | containerd 런타임 설정 |
| `group_vars/all/monitoring-external.yml` | Prometheus 외부 스크레이프 설정 |
| `group_vars/all/vault.yml` | Vault 암호화 시크릿 (Vault 섹션 참조) |
| `group_vars/k8s_cluster/k8s-cluster.yml` | 네트워크 플러그인(calico), `resolvconf_mode: none`, 서비스/파드 CIDR |
| `group_vars/k8s_cluster/addons.yml` | Kubespray 애드온 플래그 |
| `group_vars/k8s_cluster/monitoring.yml` | kube-prometheus-stack 차트 버전 및 값 |
| `group_vars/k8s_cluster/monitoring-alertmanager.yml` | AlertManager 라우팅 설정 |
| `group_vars/k8s_cluster/monitoring-rules.yml` | 커스텀 PrometheusRule 정의 |
| `group_vars/circleci/runner.yml` | CircleCI 네임스페이스(`cubrid`), resource_class, 레플리카 수 |

**스테이징 차이점:** `inventory/staging/group_vars/k8s_cluster/` 아래의 `monitoring.yml`, `monitoring-alertmanager.yml`, `monitoring-rules.yml` 은 프로덕션 파일의 심볼릭 링크다. 스테이징 vault 파일에는 플레이스홀더 값이 들어 있으며 `vault_teams_webhook_url` 은 주석 처리되어 있다.

---

## Vault 설정 (프로덕션 전용)

프로덕션에는 vault 키 세 개가 필요하다. vault 파일을 생성한다:

```bash
ansible-vault create inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password
```

필수 키:

```yaml
vault_circleci_token: "<token>"
vault_grafana_admin_password: "<password>"
vault_teams_webhook_url: "<url>"
```

`vault_teams_webhook_url` 은 Power Automate Workflow 트리거 URL이어야 한다. 플레이북은 배포 시(`deploy-monitoring.yml:35`) 다음 정규식으로 이를 검증한다:

```
^https://[a-z0-9-]+(...).logic.azure.com|api.powerplatform.com/.../workflows/.../triggers/manual/paths/invoke?...sig=...
```

URL은 `/triggers/manual/paths/invoke?api-version=…&sig=…` 로 끝나야 한다. 기존 vault 파일을 편집하려면:

```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password
```

---

## 클러스터 배포

플레이북 실행 전 연결 상태를 확인한다:

```bash
ansible all -m ping
```

### Step 1 — Kubernetes 클러스터

```bash
ansible-playbook playbooks/cluster-only.yml
```

Kubespray 의 `cluster.yml` 을 실행하고, containerd/kubelet 바인드 마운트를 설정하며, 워커 노드에 GlusterFS를 구성한다. 완료되면 `kubectl` 아티팩트가 `inventory/production/artifacts/` 에 생성된다.

### Step 2 — 모니터링 (클러스터 내부)

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring.yml
```

`alertmanager-config` 시크릿(vault의 Teams 웹훅 URL 포함)을 렌더링한 뒤 Helm으로 `kube-prometheus-stack` v75.6.2를 배포한다.

### Step 3 — 외부 모니터링 (프로덕션 전용)

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-external-monitoring.yml
```

외부 플리트(4랙에 걸친 142개 호스트)에 `node_exporter` 를 설치한다. 기본 배치 크기는 10개 호스트이며 카나리 롤아웃에는 `-e external_serial=1` 을 사용한다.

Step 2와 Step 3은 함께 실행할 수 있다:

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring-full.yml
```

> 클러스터 내부 단계가 외부 단계보다 먼저 완료되어야 한다 — `deploy-monitoring-full.yml` 이 이 순서를 강제한다.

### Step 4 — CircleCI 러너

```bash
ansible-playbook playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

CircleCI 컨테이너 에이전트를 `cubrid` 네임스페이스에 배포한다. 클러스터가 가동 중이어야 하며 `vault_circleci_token` 이 설정되어 있어야 한다.

---

## 검증

**클러스터 노드:**

```bash
inventory/production/artifacts/kubectl.sh get nodes
```

**모니터링 파드:**

```bash
inventory/production/artifacts/kubectl.sh get pods -n monitoring
```

**외부 node_exporter** — 각 외부 호스트에서 HTTP 200 응답을 확인한다:

```bash
curl -s http://<external-host-ip>:9100/metrics | head -5
```

**CircleCI 러너:**

```bash
inventory/production/artifacts/kubectl.sh get deployment container-agent -n cubrid
```

---

## 다음 단계

- 클러스터 내부 모니터링, 외부 플리트, Teams 알림 라우팅 — `docs/monitoring.md`
- CircleCI 러너 설정 및 리소스 클래스 — `docs/circleci.md`
- Day-2 운영(업그레이드, 인증서 갱신, 스케일링) — `docs/operations.md`
