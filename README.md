# CircleCI Kubernetes Self-Hosted Runner 자동화 프로젝트

> **Rocky Linux 8**에서 **Kubernetes 클러스터**를 자동으로 구축하고 **CircleCI self-hosted container runner**를 배포하는 완전 자동화 솔루션입니다.

## 🎯 프로젝트 개요

이 프로젝트는 **단 2개 파일만 수정**하고 **1개 명령어만 실행**하면 완전한 Kubernetes + CircleCI 환경을 구축할 수 있습니다.

### ✨ 주요 특징

- 🚀 **완전 자동화**: SSH 키 생성부터 클러스터 구축까지 모든 과정 자동화
- 🔧 **5가지 배포 모드**: 다양한 시나리오에 맞는 유연한 배포 옵션
- 🌐 **멀티 아키텍처**: x86_64/ARM64 자동 감지 및 최적화
- 🔐 **보안 강화**: Ansible Vault 기반 비밀 정보 관리
- 📱 **한국어 지원**: 모든 메시지와 가이드가 한국어로 제공
- 🔄 **완전한 롤백**: 3단계 롤백 시스템으로 안전한 복구

### 🎮 지원 환경

| 환경 | OS | 아키텍처 | CNI | 상태 |
|------|----|---------|----|------|
| **프로덕션** | Rocky Linux 8 | x86_64 | Calico | ✅ 완전 지원 |
| **개발/테스트** | Rocky Linux 8 | ARM64 | Flannel | ✅ 완전 지원 |
| **호환성** | CentOS 8, RHEL 8, AlmaLinux 8 | x86_64/ARM64 | 자동 선택 | ✅ 호환 |

## 🚀 빠른 시작 (5분 완성)

### 📋 사전 준비

#### 1. 하드웨어 요구사항
```
마스터 노드: 2 CPU, 4GB RAM, 20GB 디스크
워커 노드:   1 CPU, 2GB RAM, 10GB 디스크
```

#### 2. 모든 대상 노드에서 실행 (마스터 + 워커)
```bash
# 기본 패키지 설치
sudo dnf update -y && sudo dnf install -y epel-release python3 openssh-server

# SSH 서비스 시작
sudo systemctl enable --now sshd
```

#### 3. 개발장비(Ansible 관리 서버)에서 실행
```bash
# Ansible 및 관리 도구 설치
sudo dnf install -y ansible python3-kubernetes python3-openshift jq bind-utils expect
```

### 🎯 3단계 완성

#### 1단계: 프로젝트 다운로드
```bash
git clone <repository-url>
cd circleci-k8s-ansible
```

#### 2단계: 설정 파일 수정 (2개 파일만!)

**📝 `inventory/hosts.yml` - 노드 정보**
```yaml
all:
  children:
    k8s_cluster:
      children:
        k8s_masters:
          hosts:
            k8s-master-01:
              ansible_host: 192.168.1.10  # 👈 마스터 노드 IP 수정
              ansible_user: root
              node_role: master
        k8s_workers:
          hosts:
            k8s-worker-01:
              ansible_host: 192.168.1.11  # 👈 워커 노드 IP 수정
              ansible_user: root
              node_role: worker
```

**🔐 `group_vars/vault.yml` - 보안 설정**
```bash
# Vault 파일 편집
ansible-vault edit group_vars/vault.yml

# 다음 내용 입력:
vault_circleci_token: "your-actual-circleci-runner-token"
vault_ssh_password: "your-ssh-password"
```

#### 3단계: 실행! (5가지 모드 중 선택)
```bash
# 🎯 가장 많이 사용하는 모드
./scripts/setup-cluster.sh cluster-circleci

# 🔧 다른 모드들
./scripts/setup-cluster.sh cluster-only              # Kubernetes만
./scripts/setup-cluster.sh add-node --node-ip IP --node-name NAME  # 노드 추가
./scripts/setup-cluster.sh deploy-circleci           # CircleCI만 추가
./scripts/setup-cluster.sh add-node-circleci --node-ip IP --node-name NAME  # 노드+CircleCI
```

## 📚 상세 가이드

### 🔧 5가지 배포 모드 상세 설명

| 모드 | 설명 | 사용 시나리오 | 실행 시간 |
|------|------|---------------|-----------|
| `cluster-only` | Kubernetes 클러스터만 구축 | 클러스터만 먼저 구축하고 싶을 때 | ~10분 |
| `add-node` | 기존 클러스터에 노드 추가 | 클러스터 확장이 필요할 때 | ~5분 |
| `cluster-circleci` | Kubernetes + CircleCI 함께 구축 | **가장 일반적인 사용 사례** | ~15분 |
| `add-node-circleci` | 노드 추가 + CircleCI 배포 | 확장과 동시에 CircleCI 설정 | ~8분 |
| `deploy-circleci` | 기존 클러스터에 CircleCI만 추가 | 이미 클러스터가 있을 때 | ~3분 |

### 📖 모드별 사용 예제

#### 🎯 모드 1: `cluster-only` - Kubernetes만 구축
```bash
# 기본 실행
./scripts/setup-cluster.sh cluster-only

# 상세 출력과 함께
./scripts/setup-cluster.sh cluster-only --verbose

# 실제 실행 전 확인
./scripts/setup-cluster.sh cluster-only --dry-run
```

**완료 후 확인:**
```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes
kubectl get pods -A
```

#### 🔗 모드 2: `add-node` - 노드 추가
```bash
# 워커 노드 추가
./scripts/setup-cluster.sh add-node \
  --node-ip 192.168.1.12 \
  --node-name k8s-worker-02

# 마스터 노드 추가 (HA 구성)
./scripts/setup-cluster.sh add-node \
  --node-ip 192.168.1.13 \
  --node-name k8s-master-02 \
  --node-type master
```

**완료 후 확인:**
```bash
kubectl get nodes
kubectl describe nodes
```

#### 🎯 모드 3: `cluster-circleci` - 완전한 환경 구축 (추천)
```bash
# 가장 일반적인 사용 사례
./scripts/setup-cluster.sh cluster-circleci

# Vault 파일 지정
./scripts/setup-cluster.sh cluster-circleci \
  --vault-password ~/.ansible-vault-pass
```

**완료 후 확인:**
```bash
kubectl get nodes
kubectl get pods -n circleci
kubectl logs -n circleci -l app=circleci-runner
```

#### 🔗 모드 4: `add-node-circleci` - 노드 추가 + CircleCI
```bash
# 노드 추가와 동시에 CircleCI 설정
./scripts/setup-cluster.sh add-node-circleci \
  --node-ip 192.168.1.14 \
  --node-name k8s-worker-03
```

#### 🎯 모드 5: `deploy-circleci` - CircleCI만 추가
```bash
# 기존 클러스터에 CircleCI runner만 배포
./scripts/setup-cluster.sh deploy-circleci

# 기존 runner 업데이트
./scripts/setup-cluster.sh deploy-circleci --verbose
```

### 🔐 보안 설정 가이드

#### Ansible Vault 설정
```bash
# 1. Vault 파일 생성/편집
ansible-vault edit group_vars/vault.yml

# 2. 내용 입력
vault_circleci_token: "your-actual-token-here"
vault_ssh_password: "your-ssh-password-here"

# 3. Vault 비밀번호 파일 생성 (선택사항)
echo "your-vault-password" > ~/.ansible-vault-pass
chmod 600 ~/.ansible-vault-pass
```

#### CircleCI 토큰 발급
1. CircleCI 웹 콘솔 로그인
2. **Project Settings** → **Self-Hosted Runners**
3. **Create Resource Class** 클릭
4. **Runner Token** 복사
5. `group_vars/all.yml`에서 namespace와 resource_class 설정:
```yaml
circleci:
  runner:
    namespace: "your-namespace"        # 👈 실제 값으로 변경
    resource_class: "your-resource-class"  # 👈 실제 값으로 변경
```

### 🛠️ 고급 설정

#### 커스텀 설정 변경
**`group_vars/all.yml`에서 설정 가능한 항목들:**
```yaml
# Kubernetes 설정
kubernetes:
  version: "1.28.15"
  cluster_name: "my-custom-cluster"
  pod_network_cidr: "10.244.0.0/16"

# CircleCI 설정
circleci:
  runner:
    replicas: 3  # Runner 개수 조정
    image: "cimg/base:stable"

# 시스템 설정
system:
  timezone: "Asia/Seoul"
```

#### 방화벽 설정 (필요시)
```yaml
# group_vars/all.yml
network:
  firewall_enabled: true  # 방화벽 자동 설정 활성화
```

### 🔍 문제 해결

#### 일반적인 문제들

**1. SSH 연결 실패**
```bash
# SSH 키 수동 복사
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@target-node-ip

# SSH 연결 테스트
ssh -i ~/.ssh/id_ed25519 root@target-node-ip
```

**2. Ansible 실행 오류**
```bash
# Ansible 재설치
sudo dnf remove ansible
sudo dnf install ansible python3-kubernetes python3-openshift

# 연결 테스트
ansible all -i inventory/hosts.yml -m ping
```

**3. CircleCI Runner 연결 안됨**
```bash
# Runner 상태 확인
kubectl get pods -n circleci
kubectl logs -n circleci -l app=circleci-runner

# Runner 재시작
kubectl rollout restart deployment/circleci-runner -n circleci
```

**4. 클러스터 초기화 필요**
```bash
# 완전 롤백
./scripts/rollback.sh

# 부분 롤백
./scripts/rollback.sh --level partial
```

#### 로그 확인 방법
```bash
# Kubernetes 로그
journalctl -u kubelet -f
kubectl get events --sort-by='.lastTimestamp'

# CircleCI Runner 로그
kubectl logs -n circleci -l app=circleci-runner -f

# 시스템 로그
journalctl -u containerd -f
```

### 📊 성능 최적화

#### 리소스 할당 조정
```yaml
# group_vars/k8s_workers.yml
resources:
  system_reserved:
    cpu: "200m"      # 시스템용 CPU 예약
    memory: "1Gi"    # 시스템용 메모리 예약
  kube_reserved:
    cpu: "200m"      # Kubernetes용 CPU 예약
    memory: "1Gi"    # Kubernetes용 메모리 예약
```

#### CircleCI Runner 성능 조정
```yaml
# group_vars/all.yml
circleci:
  runner:
    replicas: 4  # 동시 실행 가능한 job 수
    resources:
      limits:
        cpu: "2"
        memory: "4Gi"
      requests:
        cpu: "1"
        memory: "2Gi"
```

## 🧪 테스트 및 검증

### 클러스터 기능 테스트
```bash
# 1. 노드 상태 확인
kubectl get nodes -o wide

# 2. 시스템 Pod 확인
kubectl get pods -A

# 3. DNS 테스트
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default

# 4. 네트워크 테스트
kubectl run test-net --image=nginx --rm -it -- curl -I http://kubernetes.default
```

### CircleCI Runner 테스트
```bash
# 1. Runner 상태 확인
kubectl get pods -n circleci

# 2. Runner 로그 확인
kubectl logs -n circleci -l app=circleci-runner

# 3. CircleCI 프로젝트에서 테스트 job 실행
# .circleci/config.yml 예제:
```
```yaml
version: 2.1
jobs:
  test-runner:
    resource_class: your-namespace/your-resource-class
    steps:
      - run:
          name: "Self-hosted Runner 테스트"
          command: |
            echo "🎉 Self-hosted runner에서 실행 중!"
            uname -a
            kubectl get nodes
workflows:
  test:
    jobs:
      - test-runner
```

## 📁 프로젝트 구조

```
circleci-k8s-ansible/
├── 📁 scripts/                    # 실행 스크립트
│   ├── setup-cluster.sh          # 🎯 메인 설치 스크립트 (5가지 모드)
│   └── rollback.sh               # 🔄 롤백 스크립트
├── 📁 playbooks/                 # Ansible 플레이북
│   ├── cluster-only.yml          # Kubernetes만 설치
│   ├── add-node.yml              # 노드 추가
│   ├── cluster-circleci.yml      # Kubernetes + CircleCI
│   ├── add-node-circleci.yml     # 노드 추가 + CircleCI
│   ├── deploy-circleci.yml       # CircleCI만 배포
│   └── rollback.yml              # 시스템 롤백
├── 📁 inventory/                 # 인벤토리 설정
│   └── hosts.yml                 # 🔧 노드 정보 (수정 필요)
├── 📁 group_vars/                # 변수 설정
│   ├── all.yml                   # 공통 설정
│   ├── vault.yml                 # 🔐 보안 설정 (수정 필요)
│   ├── k8s_masters.yml           # 마스터 노드 설정
│   └── k8s_workers.yml           # 워커 노드 설정
├── 📁 roles/                     # Ansible 역할
├── 📁 templates/                 # 설정 템플릿
├── ansible.cfg                   # Ansible 설정
└── 📚 문서들
    ├── README.md                 # 🎯 이 파일
    ├── SECURITY_SETUP.md         # 보안 설정 가이드
    └── WORKER_NODE_SETUP.md      # 워커 노드 설정 가이드
```

## 🎓 사용 시나리오별 가이드

### 시나리오 1: 개발 환경 구축
```bash
# 1. 단일 노드로 시작
./scripts/setup-cluster.sh cluster-circleci

# 2. 나중에 워커 노드 추가
./scripts/setup-cluster.sh add-node --node-ip 192.168.1.12 --node-name k8s-worker-02
```

### 시나리오 2: 프로덕션 환경 구축
```bash
# 1. 먼저 클러스터만 구축하고 테스트
./scripts/setup-cluster.sh cluster-only

# 2. 테스트 완료 후 CircleCI 추가
./scripts/setup-cluster.sh deploy-circleci

# 3. HA를 위한 마스터 노드 추가
./scripts/setup-cluster.sh add-node --node-ip 192.168.1.13 --node-name k8s-master-02 --node-type master
```

### 시나리오 3: 기존 클러스터 확장
```bash
# 워커 노드 추가와 동시에 CircleCI 설정
./scripts/setup-cluster.sh add-node-circleci --node-ip 192.168.1.14 --node-name k8s-worker-03
```

## 🔄 유지보수 및 업데이트

### 정기 유지보수
```bash
# 1. 시스템 업데이트 (모든 노드에서)
sudo dnf update -y

# 2. CircleCI Runner 재시작
kubectl rollout restart deployment/circleci-runner -n circleci

# 3. 클러스터 상태 점검
kubectl get nodes
kubectl get pods -A
```

### 설정 변경 시
```bash
# 1. group_vars/all.yml 수정 후
./scripts/setup-cluster.sh deploy-circleci

# 2. 또는 특정 태그만 실행
ansible-playbook -i inventory/hosts.yml playbooks/deploy-circleci.yml --tags circleci
```

## 🆘 지원 및 문의

### 문제 발생 시 체크리스트
- [ ] 모든 노드에서 SSH 접근 가능한가?
- [ ] `inventory/hosts.yml`의 IP 주소가 정확한가?
- [ ] `group_vars/vault.yml`의 토큰이 유효한가?
- [ ] 방화벽이 필요한 포트를 차단하고 있지 않은가?
- [ ] 인터넷 연결이 정상인가?

### 로그 수집 방법
```bash
# 문제 발생 시 다음 로그들을 수집하세요
kubectl get events --sort-by='.lastTimestamp' > k8s-events.log
kubectl logs -n circleci -l app=circleci-runner > circleci-logs.log
journalctl -u kubelet --since "1 hour ago" > kubelet.log
```

---

## 📈 버전 정보

- **Kubernetes**: v1.28.15
- **containerd**: v1.7.27  
- **Ansible**: 9.0+
- **지원 OS**: Rocky Linux 8, CentOS 8, RHEL 8, AlmaLinux 8
- **지원 아키텍처**: x86_64, ARM64 (aarch64)

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

---

**🎯 이제 시작하세요!** 위의 3단계만 따라하면 완전한 Kubernetes + CircleCI 환경이 구축됩니다!