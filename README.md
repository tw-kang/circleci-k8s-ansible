# CircleCI Kubernetes Cluster with Self-Hosted Runners

이 프로젝트는 Ansible을 사용하여 Rocky Linux 8에서 Kubernetes 클러스터를 자동으로 설치하고 CircleCI self-hosted container runner를 배포하는 완전 자동화된 솔루션입니다.

## 🎯 지원 환경

- **프로덕션**: Rocky Linux 8 x86_64 (Intel/AMD CPU)
- **개발/테스트**: Rocky Linux 8 ARM64 (aarch64)
- **호환성**: CentOS 8, RHEL 8, AlmaLinux 8

## 🚀 퀵 스타트

### 1. 모든 노드에서 (마스터 + 워커)
```bash
# 시스템 업데이트 및 기본 설정
sudo dnf update -y && sudo dnf install -y epel-release
sudo dnf install -y python3 git openssh-server

# SSH 서비스 시작 및 활성화
sudo systemctl enable --now sshd
```

### 2. 마스터 노드에서만
```bash
# Ansible 및 관리 도구 설치
sudo dnf install -y ansible python3-kubernetes python3-openshift jq bind-utils

# 프로젝트 설정
git clone <repository-url> && cd circleci-k8s-ansible
vi inventory/hosts.yml  # 노드 정보 입력
ansible-vault edit group_vars/all/vault.yml  # CircleCI 토큰 설정

# 클러스터 배포
./scripts/setup-cluster.sh
```

## 🚀 주요 기능

- **완전 자동화된 Kubernetes 클러스터** (kubeadm 기반)
- **CircleCI self-hosted container runner 배포**
- **멀티 아키텍처 지원** (x86_64/ARM64 자동 감지)
- **스마트 CNI 선택** (Calico/Flannel)
- **새로운 노드 추가 자동화**
- **완전한 롤백 시스템** (3단계 복구)
- **Ansible Vault 보안**

## 📋 시스템 요구사항

### 하드웨어
- **마스터 노드**: 2 CPU, 4GB RAM, 20GB 디스크
- **워커 노드**: 1 CPU, 2GB RAM, 10GB 디스크

### 소프트웨어
- **모든 노드**: Python 3.8+, SSH 서버, 네트워크 연결
- **마스터 노드만**: Ansible 9.0+, 클러스터 관리 도구

## 🛠️ 설치 및 설정

### 1. 노드별 패키지 설치

#### 모든 노드에서 (마스터 + 워커)
```bash
# 기본 시스템 패키지만
sudo dnf update -y && sudo dnf install -y epel-release
sudo dnf install -y python3 git openssh-server

# SSH 서비스 시작 및 활성화
sudo systemctl enable --now sshd
```

#### 마스터 노드에서만 (관리 도구)
```bash
# Ansible 및 클러스터 관리 도구
sudo dnf install -y ansible python3-kubernetes python3-openshift jq bind-utils

# 설치 확인
ansible --version && python3 -c "import kubernetes; print('OK')"
```

**마스터 노드 전용 도구:**
- **ansible**: 클러스터 자동화 (워커 노드 불필요)
- **python3-kubernetes/openshift**: Ansible k8s 모듈
- **jq**: JSON 처리 (스크립트용)
- **bind-utils**: DNS 조회 (관리용)

### 2. 인벤토리 구성

#### 전체 클러스터 (마스터 + 워커)
`inventory/hosts.yml`:
```yaml
all:
  children:
    k8s_cluster:
      children:
        k8s_masters:
          hosts:
            k8s-master-01:
              ansible_host: 192.168.1.10
              ansible_user: root
        k8s_workers:
          hosts:
            k8s-worker-01:
              ansible_host: 192.168.1.11
              ansible_user: root
```

#### 마스터 노드만 (단일 노드 클러스터)
`inventory/hosts.yml`:
```yaml
all:
  children:
    k8s_cluster:
      children:
        k8s_masters:
          hosts:
            k8s-master-01:
              ansible_host: 192.168.1.10
              ansible_user: root
        k8s_workers:
          hosts: {}  # 빈 워커 노드 섹션
```

### 3. CircleCI 설정

```bash
# CircleCI 토큰 설정
ansible-vault edit group_vars/all/vault.yml
```

내용:
```yaml
vault_circleci_token: "your-actual-circleci-runner-token"
```

`group_vars/all.yml`에서 CircleCI 설정:
```yaml
circleci:
  runner:
    namespace: "your-namespace"
    resource_class: "your-resource-class"
    token: "{{ vault_circleci_token }}"
    replicas: 2
```

## 🚀 사용 방법

### 마스터 노드만 설치 (Single Node)

**단일 노드 클러스터 구성 시:**
```bash
# 1. 인벤토리에서 k8s_workers를 빈 섹션으로 설정
# 2. 마스터 노드만 설치
./scripts/setup-cluster.sh -p k8s-cluster.yml --tags "common,master"

# 3. 마스터 노드에서 Pod 스케줄링 활성화 (자동 적용됨)
kubectl get nodes  # STATUS가 Ready인지 확인
```

**참고**: 마스터 노드만 설치하면 해당 노드에서 애플리케이션 Pod도 실행됩니다.

### 기본 명령어

```bash
# 전체 클러스터 + CircleCI runner 설치
./scripts/setup-cluster.sh

# Kubernetes만 설치
./scripts/setup-cluster.sh -p k8s-cluster.yml

# 마스터 노드만 설치 (단일 노드 클러스터)
./scripts/setup-cluster.sh -p k8s-cluster.yml --tags "common,master"

# CircleCI runner만 배포
./scripts/setup-cluster.sh -p circleci-runner.yml

# 새 노드 추가
./scripts/add-node.sh

# 시스템 롤백
./scripts/rollback.sh
```

### 스크립트 옵션

```bash
# Vault 비밀번호 파일 사용
./scripts/setup-cluster.sh --vault-password ~/.ansible-vault-pass

# Dry run (변경사항 미리 확인)
./scripts/setup-cluster.sh --dry-run

# 특정 태그만 실행
./scripts/setup-cluster.sh --tags "k8s-install,circleci-deploy"
```

## 📁 스크립트 가이드

| 스크립트 | 크기 | 설명 |
|---------|------|------|
| `setup-cluster.sh` | 5.6KB | 전체 클러스터 초기 설정 |
| `add-node.sh` | 15.4KB | 새 노드 자동 추가 |
| `prepare-worker-node.sh` | 11.7KB | 수동 노드 준비 |
| `rollback.sh` | 9.7KB | 3단계 시스템 롤백 |

## 🔧 문제 해결

### 마스터 노드 문제
```bash
# Ansible 설치 오류
sudo dnf remove python3-ansible ansible-core
sudo dnf install -y ansible python3-kubernetes python3-openshift

# SSH 연결 문제 (모든 노드와 통신)
ssh-keygen -t rsa -b 4096
ssh-copy-id root@target-node
```

### 모든 노드 공통 문제
```bash
# SSH 서비스 문제 - "Unit file sshd.service does not exist" 오류
sudo dnf install -y openssh-server
sudo systemctl enable --now sshd
sudo systemctl status sshd

# Container Runtime 문제
sudo systemctl status containerd
sudo journalctl -u containerd -f
```

## 🧪 테스트 환경

**검증 완료:**
- **OS**: Rocky Linux 8.10 ARM64
- **Kubernetes**: v1.28.15
- **Container Runtime**: containerd 1.7.27
- **CNI**: Flannel
- **Ansible**: 9.2.0 시스템 패키지
- **클러스터**: 마스터 1개 + 워커 1개

**테스트 결과:**
- ✅ 멀티 노드 클러스터 구축 성공
- ✅ CircleCI runner 배포 완료
- ✅ DNS 및 네트워킹 정상 작동
- ✅ 모든 시스템 Pod 안정 실행

## 📈 버전 히스토리

### v2.1 (2025-06-11) - 최적화 및 안정성 개선
- 멀티 노드 클러스터 테스트 완료
- Python 패키지 최소화 (16MB 절약)
- 네이티브 도구 활용 (jq, bind-utils, curl, ipcalc)
- requirements.yml 제거 (시스템 collections 사용)
- 문제 해결 가이드 강화

### v2.0 - 아키텍처 호환성 개선
- ARM64/x86_64 자동 감지
- 에러 처리 강화
- 스크립트 자동화 완성

## 🤝 기여 및 지원

문제가 발생하거나 개선 사항이 있으면 GitHub Issues를 통해 알려주세요.

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.