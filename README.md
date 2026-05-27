# circleci-k8s-ansible

kubespray 기반 Kubernetes 클러스터, kube-prometheus-stack 모니터링 스택 (클러스터 내부 + 외부 fleet), CircleCI self-hosted container runner를 프로비저닝하는 Ansible 자동화 도구다.

## 빠른 시작

```bash
git clone <repo> && cd circleci-k8s-ansible
git submodule update --init --recursive
python -m pip install -U -r requirements.txt

# 샘플 인벤토리를 복사하거나 production/staging을 직접 수정한다
vim inventory/production/hosts.ini
vim inventory/production/external-nodes.ini   # production only

# K8s + GlusterFS 빌드 캐시 프로비저닝
ansible-playbook -i inventory/production/hosts.ini playbooks/cluster-only.yml

# 클러스터 내부 모니터링 (Prometheus / Grafana / AlertManager) + Teams 알림 배포
# external-nodes.ini 도 함께 전달해야 외부 fleet scrape config가 채워진다
ansible-playbook -i inventory/production/hosts.ini -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring.yml --vault-password-file .vault-password

# (Production 전용) 외부 fleet에 node_exporter 배포 (두 인벤토리 모두 필요)
ansible-playbook -i inventory/production/hosts.ini -i inventory/production/external-nodes.ini \
  playbooks/deploy-external-monitoring.yml

# CircleCI runner 배포
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

사전 요구사항, 대상 노드 준비 및 검증 절차는 [docs/installation.md](docs/installation.md)에 있다.

## 배포 모드

| Playbook | Wraps (kubespray) | 용도 |
|----------|-------------------|------|
| `playbooks/cluster-only.yml` | `cluster.yml` | K8s 클러스터 + GlusterFS 빌드 캐시 |
| `playbooks/deploy-monitoring.yml` | — | 클러스터 내부 kube-prometheus-stack + AlertManager → Teams Secret |
| `playbooks/deploy-external-monitoring.yml` | — | `external_nodes`에 `node_exporter` 배포 (production 전용) |
| `playbooks/deploy-monitoring-full.yml` | — | 클러스터 내부 + 외부를 한 번에 실행 |
| `playbooks/deploy-circleci.yml` | — | `cubrid` 네임스페이스에 CircleCI `container-agent` Helm 릴리스 |
| `playbooks/add-node.yml` | `scale.yml` | 클러스터에 노드 추가 |
| `playbooks/remove-node.yml` | `remove-node.yml` | 노드 제거 |
| `playbooks/upgrade-cluster.yml` | `upgrade-cluster.yml` | 새 `kube_version`으로 롤링 업그레이드 |
| `playbooks/reset-cluster.yml` | `reset.yml` | 클러스터 해체 |

## 저장소 구조

```
.
├── ansible.cfg                  # 기본 인벤토리, vault 비밀번호 파일, roles_path
├── requirements.txt             # ansible 9.13, kubernetes >=31, 지원 라이브러리
├── 3rdparty/kubespray/          # v2.28.0에 고정된 서브모듈
├── inventory/
│   ├── production/              # 3노드 K8s + 142개 외부 모니터링 대상
│   └── staging/                 # 3노드 K8s, 외부 호스트 없음 (모니터링은 production에 심링크)
├── playbooks/                   # 플레이북 9개 (5개는 kubespray 플레이 래핑)
├── roles/
│   ├── circleci/                # Helm: `cubrid` 네임스페이스에 container-agent 배포
│   ├── external-monitoring/     # external_nodes에 node_exporter 1.8.2 설치
│   └── glusterfs/               # 복제 빌드 캐시 볼륨 + 정리 CronJob
└── docs/
    ├── installation.md          # 제어 머신 + 노드 준비 + 배포
    ├── monitoring.md            # 클러스터 내부 + 외부 + MS Teams 알림
    ├── circleci.md              # CircleCI runner 배포 + 운영
    ├── operations.md            # day-2 운영, 노드 수명 주기, vault, 백업
    ├── adr/
    │   └── 0001-adapter-less-workflow.md
    └── flow-definitions/        # Power Automate flow JSON 내보내기
```

## 문서

- [docs/installation.md](docs/installation.md) — 제어 머신 + K8s 및 외부 노드 준비 + 클러스터 배포
- [docs/monitoring.md](docs/monitoring.md) — kube-prometheus-stack, 외부 fleet `node_exporter`, AlertManager → MS Teams Workflow
- [docs/circleci.md](docs/circleci.md) — CircleCI runner Helm 릴리스, 빌드 캐시 연동, 운영
- [docs/operations.md](docs/operations.md) — 노드 수명 주기, vault, 백업, 트러블슈팅
- [docs/adr/0001-adapter-less-workflow.md](docs/adr/0001-adapter-less-workflow.md) — AlertManager가 Power Automate로 직접 라우팅하는 이유
- [CONTEXT.md](CONTEXT.md) — 용어 정의 (알림, 외부 fleet)
- [3rdparty/kubespray/docs/](3rdparty/kubespray/docs/) — 상위 kubespray 참조 문서

## 지원 환경

- **K8s 클러스터 노드**: Rocky Linux 8/9, CentOS 8/9, RHEL 8/9, AlmaLinux 8/9, Ubuntu 20.04/22.04
- **외부 모니터링 호스트**: CentOS 7, Rocky Linux 8 (production fleet)
- **아키텍처**: x86_64 (클러스터 내 혼합 아키텍처는 지원하지 않음)

## 자주 쓰는 명령

```bash
# 클러스터 설치 결과물로 생성된 kubectl 사용
inventory/production/artifacts/kubectl.sh get nodes
inventory/production/artifacts/kubectl.sh get pods -A

# 암호화된 vault 편집
ansible-vault edit inventory/production/group_vars/all/vault.yml \
  --vault-password-file .vault-password

# 커밋 전 플레이북 드라이런
ansible-playbook -i inventory/staging/hosts.ini playbooks/cluster-only.yml --check
```

그 외 모든 작업은 [docs/operations.md](docs/operations.md)에서 시작한다.
