# CircleCI Kubernetes Cluster with Self-Hosted Runners

이 프로젝트는 Ansible을 사용하여 **Rocky Linux 8 x86_64** 프로덕션 환경에서 Kubernetes 클러스터를 자동으로 설치하고 CircleCI self-hosted container runner를 배포하는 완전 자동화된 솔루션입니다.

## 🎯 **주 사용 환경**: x86_64 Intel CPU 프로덕션
- **개발 환경**: ARM64 (aarch64) - 테스트 및 개발용
- **프로덕션 환경**: x86_64 Intel CPU - 실제 배포용

## 🚀 Rocky Linux 8 x86_64 퀵 스타트

```bash
# 1. 모든 x86_64 노드에서 기본 설정
sudo dnf update -y && sudo dnf install -y python3 python3-pip git

# 2. 마스터 노드에서 프로젝트 설정
git clone <repository-url> && cd circleci-k8s-ansible
sudo dnf install -y epel-release  # EPEL 저장소 활성화
sudo dnf install -y ansible python3-kubernetes python3-openshift jq bind-utils  # 최소 필수 패키지만
ansible-galaxy collection install -r requirements.yml

# 3. 인벤토리 및 설정 파일 수정
vi inventory/hosts.yml  # x86_64 프로덕션 노드 정보 입력
ansible-vault edit group_vars/all/vault.yml  # CircleCI 토큰 설정

# 4. 프로덕션 클러스터 배포
./scripts/setup-cluster.sh
```

## 🚀 주요 기능

- **완전 자동화된 Kubernetes 클러스터 설치** (kubeadm 기반)
- **x86_64 Intel CPU 프로덕션 환경 최적화** 🎯
- **ARM64 개발 환경 지원** (자동 감지 및 호환성 조정)
- **CircleCI self-hosted container runner 배포**
- **마스터 노드에서 pod 스케줄링 지원** (single-node 또는 hybrid 구성)
- **새로운 노드 추가 자동화** (자동/수동 방식 모두 지원)
- **지능형 CNI 선택**: Calico (x86_64 프로덕션) / Flannel (ARM64 개발)
- **Helm 설치 및 구성** (v3.13.0 ARM64 지원)
- **완전한 롤백 시스템** (3단계 롤백 레벨)
- **보안 강화된 구성** (Ansible Vault 지원)
- **실제 운영 경험 기반 문제 해결 가이드**

## 📋 시스템 요구사항

### 최소 하드웨어 요구사항
- **마스터 노드**: 2 CPU, 4GB RAM, 20GB 디스크
- **워커 노드**: 1 CPU, 2GB RAM, 10GB 디스크
- **네트워크**: 모든 노드 간 통신 가능
- **아키텍처**: ARM64 (aarch64) 또는 x86_64 지원

### 지원 운영체제
- **Rocky Linux 8 x86_64** (프로덕션 환경 - 완전 테스트됨)
- **Rocky Linux 8 aarch64** (개발 환경 - 호환성 지원)
- CentOS 8 x86_64 (호환성 지원)
- RHEL 8 x86_64 (호환성 지원)
- AlmaLinux 8 x86_64 (호환성 지원)

### 필수 소프트웨어
- Python 3.8+
- Ansible 7.0+
- SSH 접근 권한

## 🛠️ 설치 및 설정

### 1. Rocky Linux 8 노드 준비

모든 대상 노드에서 다음 사전 작업을 수행하세요:

```bash
# 시스템 업데이트 및 EPEL 저장소 활성화
sudo dnf update -y
sudo dnf install -y epel-release

# 필수 패키지 및 네이티브 도구 일괄 설치
sudo dnf install -y python3 ansible python3-kubernetes python3-openshift \
  jq bind-utils curl wget vim git ipcalc

# SSH 서버 확인
sudo systemctl enable --now sshd
```

### 2. 프로젝트 다운로드

```bash
git clone <repository-url>
cd circleci-k8s-ansible
```

### 3. 의존성 설치

```bash
# EPEL 저장소 활성화
sudo dnf install -y epel-release

# 최소 필수 패키지만 설치 (Python + 네이티브 도구)
sudo dnf install -y ansible python3-kubernetes python3-openshift jq bind-utils

# Ansible collections 설치
ansible-galaxy collection install -r requirements.yml

# 설치 확인
ansible --version
ansible localhost -m ping
python3 -c "import kubernetes; print('Kubernetes client:', kubernetes.__version__)"
```

**중요**: Ansible 필수 패키지만 설치하고, 나머지는 네이티브 도구를 사용합니다. pip 설치는 필요하지 않습니다.

**설치된 도구들:**
- **ansible**: Kubernetes 자동화
- **python3-kubernetes/openshift**: Ansible 모듈용 Python 라이브러리  
- **jq**: JSON 처리 (python-jsonpath 대체)
- **bind-utils**: DNS 조회 (dig, nslookup - python-dns 대체)
- **curl**: HTTP 요청 (python-requests 대체)
- **ipcalc**: 네트워크 계산 (python-netaddr 대체)

### 4. 인벤토리 구성

`inventory/hosts.yml` 파일을 수정하여 실제 x86_64 프로덕션 서버 정보를 입력하세요:

```yaml
all:
  children:
    k8s_cluster:
      children:
        k8s_masters:
          hosts:
            k8s-master-01:
              ansible_host: 192.168.1.10  # x86_64 프로덕션 마스터 노드 IP
              ansible_user: root
              ansible_python_interpreter: /usr/bin/python3
              node_role: master
        k8s_workers:
          hosts:
            k8s-worker-01:
              ansible_host: 192.168.1.11  # x86_64 프로덕션 워커 노드 IP
              ansible_user: root
              ansible_python_interpreter: /usr/bin/python3
              node_role: worker
            k8s-worker-02:
              ansible_host: 192.168.1.12  # 추가 워커 노드
              ansible_user: root
              ansible_python_interpreter: /usr/bin/python3
              node_role: worker
```

### 5. CircleCI 설정

#### CircleCI 토큰 설정
1. CircleCI 웹 콘솔에서 Organization Settings > Self-Hosted Runners로 이동
2. Resource class를 생성하고 토큰을 복사
3. `group_vars/all/vault.yml` 파일에 토큰 설정:

```bash
# 파일 편집
ansible-vault edit group_vars/all/vault.yml

# 내용 (실제 토큰으로 변경)
vault_circleci_token: "your-actual-circleci-runner-token"
```

#### 기본 설정 수정
`group_vars/all.yml` 파일에서 CircleCI 설정을 수정하세요:

```yaml
circleci:
  runner:
    namespace: "your-namespace"        # 실제 namespace로 변경
    resource_class: "your-resource-class"  # 실제 resource class로 변경
    token: "{{ vault_circleci_token }}"
    image: "cimg/base:stable"
    replicas: 2
```

## 🚀 사용 방법

### 전체 클러스터 설치

```bash
# 기본 설치 (전체 클러스터 + CircleCI runner)
./scripts/setup-cluster.sh

# Vault 비밀번호 파일 사용
./scripts/setup-cluster.sh --vault-password ~/.ansible-vault-pass

# Dry run (변경사항 미리 확인)
./scripts/setup-cluster.sh --dry-run
```

### Kubernetes 클러스터만 설치

```bash
# CircleCI 없이 Kubernetes만 설치
./scripts/setup-cluster.sh -p k8s-cluster.yml
```

### CircleCI Runner만 배포

```bash
# 기존 클러스터에 CircleCI runner 추가
./scripts/setup-cluster.sh -p circleci-runner.yml
```

### 새 노드 추가 (Rocky Linux 8)

#### 방법 1: 자동화 스크립트 사용 (권장)
```bash
# Rocky Linux 8 워커 노드 추가
./scripts/add-node.sh --node-ip 192.168.1.20 --node-name rocky8-worker-03

# Rocky Linux 8 마스터 노드 추가 (HA 구성)
./scripts/add-node.sh --node-ip 192.168.1.21 --node-name rocky8-master-02 --node-type master
```

#### 방법 2: 단계별 수동 추가 (실제 테스트 검증됨) 🆕
```bash
# 1. 워커 노드 SSH 연결 설정
ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-worker-key
ssh-copy-id -i ~/.ssh/k8s-worker-key.pub root@<worker-node-ip>

# 2. 연결 테스트
sudo ssh root@<worker-node-ip> "hostname && uname -a"

# 3. 인벤토리에 워커 노드 추가
vi inventory/hosts.yml  # 새 워커 노드 정보 추가

# 4. 워커 노드 설정 (필요한 경우 수동 설정)
sudo ssh root@<worker-node-ip> "
  mkdir -p /etc/selinux && echo 'SELINUX=disabled' > /etc/selinux/config
  swapoff -a
  modprobe overlay && modprobe br_netfilter
"

# 5. Ansible로 워커 노드 설정
ansible-playbook playbooks/k8s-cluster.yml --limit k8s_workers -i inventory/hosts.yml

# 6. 마스터에서 조인 토큰 생성
sudo kubeadm token create --print-join-command

# 7. 워커 노드에서 클러스터 조인
sudo ssh root@<worker-node-ip> "kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>"

# 8. 노드 상태 확인
kubectl get nodes
```

#### 노드 추가 전 확인사항 (대상 노드에서)
```bash
# 기본 시스템 상태 확인
ssh root@<worker-node-ip> "
  dnf update -y && 
  systemctl status sshd && 
  free -h && 
  df -h &&
  hostnamectl
"
```

## 📁 프로젝트 구조

```
circleci-k8s-ansible/
├── ansible.cfg                 # Ansible 설정
├── requirements.yml            # Ansible collections 요구사항
├── python-requirements.txt     # Python 패키지 요구사항
├── inventory/
│   └── hosts.yml              # 인벤토리 파일
├── group_vars/
│   ├── all.yml                # 공통 변수
│   ├── k8s_masters.yml        # 마스터 노드 변수
│   ├── k8s_workers.yml        # 워커 노드 변수
│   └── all/
│       └── vault.yml          # 암호화된 민감 정보
├── playbooks/
│   ├── site.yml               # 메인 playbook
│   ├── k8s-cluster.yml        # Kubernetes 전용 playbook
│   └── circleci-runner.yml    # CircleCI runner 전용 playbook
├── roles/
│   ├── kubernetes-common/     # K8s 공통 설정
│   ├── kubernetes-master/     # K8s 마스터 설정
│   ├── kubernetes-worker/     # K8s 워커 설정
│   └── circleci-runner/       # CircleCI runner 설정
└── scripts/
    ├── setup-cluster.sh       # 클러스터 설치 스크립트 (5.6KB)
    ├── add-node.sh           # 노드 추가 스크립트 (15.4KB)
    ├── prepare-worker-node.sh # 워커 노드 수동 준비 스크립트 (11.7KB)
    └── rollback.sh           # 클러스터 롤백 스크립트 (9.7KB)
```

## 🔧 설정 옵션

### Rocky Linux 8 + ARM64 특화 설정

`group_vars/all.yml`에서 Rocky Linux 8과 ARM64에 최적화된 설정들:

```yaml
# 시스템 설정 (Rocky Linux 8)
system:
  timezone: "Asia/Seoul"
  ntp_servers:
    - "pool.ntp.org"
    - "time.bora.net"
  os_family: "RedHat"
  os_version: "8"
  package_manager: "dnf"
  # Architecture detection: aarch64 또는 x86_64 자동 감지

# 네트워크 설정 (firewalld 기본)
network:
  firewall_enabled: false  # 실습 환경에서는 비활성화
```

### 🏗️ 아키텍처별 자동 설치 방법

**x86_64 Intel CPU (프로덕션 환경) - 기본값:**
- **CNI**: Calico (고성능, 네트워크 정책 지원)
- **containerd**: Docker 저장소에서 안정적인 패키지 설치
- **저장소**: 공식 pkgs.k8s.io Kubernetes 저장소
- **최적화**: 프로덕션 워크로드에 최적화된 설정

**ARM64 (aarch64) 개발 환경 - 자동 감지:**
- **CNI**: Flannel (ARM64 호환성 우선)
- **containerd**: GitHub 릴리스에서 직접 다운로드 (1.7.27)
- **runc**: GitHub 릴리스에서 ARM64 바이너리 사용
- **최적화**: 개발 및 테스트 환경에 적합한 설정

### Kubernetes 설정

`group_vars/all.yml`에서 다음 옵션들을 조정할 수 있습니다:

```yaml
kubernetes:
  version: "1.28.15"                   # Kubernetes 버전 (x86_64 프로덕션 테스트됨)
  cni_plugin: "calico"                 # CNI 플러그인 (x86_64: Calico, ARM64: 자동 Flannel)
  pod_network_cidr: "10.244.0.0/16"   # Pod 네트워크 대역
  service_network_cidr: "10.96.0.0/12" # Service 네트워크 대역
  # ARM64 환경에서는 자동으로 Flannel로 변경됩니다

# Container runtime (자동 아키텍처 감지)
container_runtime:
  name: "containerd"
  version: "1.7.27"  # x86_64: Docker 저장소, ARM64: GitHub 릴리스
```

### 마스터 노드 설정

마스터 노드에서 pod 스케줄링을 허용하려면:

```yaml
k8s_master:
  allow_scheduling: true  # 마스터 노드에서 pod 실행 허용
```

### CircleCI Runner 설정

```yaml
circleci:
  runner:
    replicas: 2                    # Runner 복제본 수
    image: "cimg/base:stable"      # 기본 이미지
```

## 🔐 보안 설정

### SSH 키 설정

```bash
# SSH 키 생성 (필요한 경우)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-cluster

# 모든 노드에 공개키 복사
ssh-copy-id -i ~/.ssh/k8s-cluster.pub root@<node-ip>
```

### Ansible Vault 사용

```bash
# Vault 파일 암호화
ansible-vault encrypt group_vars/all/vault.yml

# Vault 파일 편집
ansible-vault edit group_vars/all/vault.yml

# Vault 비밀번호 파일 생성
echo "your-vault-password" > ~/.ansible-vault-pass
chmod 600 ~/.ansible-vault-pass
```

## 🛠️ scripts 디렉토리 상세 가이드

### 1. setup-cluster.sh (5.6KB)
**목적**: 전체 Kubernetes 클러스터 및 CircleCI 러너 초기 구축
```bash
# 기본 사용법 - 전체 클러스터 구축
./scripts/setup-cluster.sh

# Kubernetes만 설치 (CircleCI 제외)
./scripts/setup-cluster.sh -p k8s-cluster.yml

# CircleCI 러너만 배포 (기존 클러스터에)
./scripts/setup-cluster.sh -p circleci-runner.yml

# 드라이런으로 미리 확인
./scripts/setup-cluster.sh --dry-run

# 특정 태그만 실행
./scripts/setup-cluster.sh --tags "kubernetes,common"
```

### 2. add-node.sh (15.4KB)
**목적**: 기존 클러스터에 새로운 노드 자동 추가 (Ansible 기반)
```bash
# 워커 노드 추가
./scripts/add-node.sh --node-ip 192.168.1.20 --node-name k8s-worker-03

# 마스터 노드 추가 (HA 구성)
./scripts/add-node.sh --node-ip 192.168.1.21 --node-name k8s-master-02 --node-type master

# 커스텀 SSH 키 사용
./scripts/add-node.sh --node-ip 192.168.1.20 --node-name k8s-worker-03 --ssh-key ~/.ssh/k8s-key

# 노드 준비 단계 건너뛰기
./scripts/add-node.sh --node-ip 192.168.1.20 --node-name k8s-worker-03 --skip-preparation
```

### 3. prepare-worker-node.sh (11.7KB)
**목적**: 워커 노드 수동 준비 (Ansible 실패 시 백업 방법)
```bash
# 기본 워커 노드 준비
./scripts/prepare-worker-node.sh --target-node 192.168.1.20

# 커스텀 SSH 키로 준비
./scripts/prepare-worker-node.sh --target-node 192.168.1.20 --ssh-key ~/.ssh/k8s-key

# 특정 버전으로 설치
./scripts/prepare-worker-node.sh --target-node 192.168.1.20 \
  --kubernetes-version 1.28.15 --containerd-version 1.7.27
```

**이 스크립트가 수행하는 작업:**
1. containerd 설치 및 설정 (ARM64 지원)
2. Kubernetes 구성 요소 설치 (kubelet, kubeadm, kubectl)
3. 시스템 설정 (swap 해제, iptables, systemd cgroup)
4. 필요한 서비스 시작 및 활성화

### 4. rollback.sh (9.7KB)
**목적**: 실패한 클러스터 설치 롤백 및 시스템 복구
```bash
# 전체 롤백 (패키지, 설정, 데이터 모두 제거)
./scripts/rollback.sh

# 부분 롤백 (클러스터 설정만 제거, 패키지 유지)
./scripts/rollback.sh --level partial

# 서비스만 중지 (설정 및 패키지 유지)
./scripts/rollback.sh --level services-only

# 확인 없이 강제 실행
./scripts/rollback.sh --force

# 드라이런으로 미리 확인
./scripts/rollback.sh --dry-run
```

**롤백 레벨 설명:**
- **full**: Kubernetes 및 containerd 패키지 완전 제거, 모든 설정 파일 삭제
- **partial**: 클러스터 설정만 제거, 설치된 패키지는 유지
- **services-only**: 서비스만 중지, 모든 파일과 패키지 유지

### 스크립트 선택 가이드

| 상황 | 사용할 스크립트 | 설명 |
|------|----------------|------|
| 새 클러스터 구축 | `setup-cluster.sh` | 처음부터 전체 클러스터 생성 |
| 노드 추가 (자동) | `add-node.sh` | Ansible로 자동화된 노드 추가 |
| 노드 추가 (수동) | `prepare-worker-node.sh` | Ansible 실패 시 수동 노드 준비 |
| 설치 실패 복구 | `rollback.sh` | 문제 발생 시 시스템 정리 |

## 📊 모니터링 및 관리

### 클러스터 상태 확인

```bash
# 노드 상태 확인
kubectl get nodes

# 전체 Pod 상태 확인
kubectl get pods -A

# CircleCI Runner 상태 확인
kubectl get pods -n circleci
kubectl logs -n circleci -l app=circleci-runner

# Helm 상태 확인 (v3.13.0 설치됨) 🆕
helm version
helm repo list
```

### CircleCI 프로젝트 설정

`.circleci/config.yml` 예제:

```yaml
version: 2.1

jobs:
  test:
    resource_class: your-namespace/your-resource-class
    steps:
      - checkout
      - run:
          name: Run tests
          command: |
            echo "Running on self-hosted runner!"
            kubectl version --client

workflows:
  test-workflow:
    jobs:
      - test
```

## 🔧 문제 해결

### 일반적인 문제들

#### 1. Ansible 설치 및 버전 문제 🆕

**Ansible 7.x 버전 오류 해결:**
```bash
# 문제: ansible>=7.0.0 버전을 찾을 수 없는 경우
# 해결: EPEL 저장소에서 최소 필수 패키지만 설치 (권장)
sudo dnf install -y epel-release
sudo dnf install -y ansible python3-kubernetes python3-openshift jq bind-utils

# 기존 pip 설치 패키지 제거 (필요한 경우)
python3 -m pip uninstall ansible ansible-core kubernetes openshift requests netaddr dnspython jsonpath-ng -y

# 설치 확인
ansible --version  # 9.2.0+ (core 2.16.3+) 확인
python3 -c "import kubernetes, openshift; print('All packages OK')"
```

**Python 환경 혼재 문제:**
```bash
# Python 3.12 사용 확인
python3 --version  # 3.12.10 확인
which python3.12

# PATH 설정 (필요한 경우)
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"
```

#### 2. SSH 연결 문제
```bash
# SSH 연결 테스트
ansible all -i inventory/hosts.yml -m ping

# SSH 설정 확인
ssh -v root@<node-ip>
```

#### 3. Kubernetes 클러스터 문제 (Rocky Linux 8 특화)
```bash
# 클러스터 로그 확인
sudo journalctl -u kubelet -f

# 컨테이너 런타임 상태 확인
sudo systemctl status containerd

# Rocky Linux 8 특화 확인사항
sudo dnf list installed | grep kubernetes
sudo dnf list installed | grep containerd

# 방화벽 상태 확인
sudo systemctl status firewalld
sudo firewall-cmd --list-all

# 시간 동기화 확인
sudo chrony sources
sudo timedatectl status
```

#### 4. CircleCI Runner 문제
```bash
# Runner 로그 확인
kubectl logs -n circleci -l app=circleci-runner -f

# Runner 상태 확인
kubectl describe deployment -n circleci circleci-runner
```

#### 5. ARM64 관련 문제
```bash
# 아키텍처 확인
uname -m

# containerd 바이너리 경로 확인 (ARM64)
ls -la /usr/local/bin/containerd

# CNI 플러그인 확인
ls -la /opt/cni/bin/

# GLIBC 버전 확인 (호환성 문제 시)
ldd --version
```

#### 6. 워커 노드 추가 시 일반적인 문제들 🆕

**SSH 연결 문제:**
```bash
# SSH 서비스 상태 확인
sudo systemctl status sshd
sudo systemctl start sshd
sudo systemctl enable sshd

# SSH 키 교환 (마스터 노드에서)
ssh-keygen -t rsa -b 4096
ssh-copy-id root@<worker-node-ip>

# SSH 연결 테스트
sudo ssh root@<worker-node-ip> "hostname && uname -a"
```

**Ansible 연결 문제:**
```bash
# Ansible 핑 테스트
ansible k8s_workers -i inventory/hosts.yml -m ping --private-key=<key-path>

# SSH 에이전트 설정
eval $(ssh-agent -s)
ssh-add <private-key-path>
```

**SELinux 설정 문제:**
```bash
# SELinux 설정 파일이 없는 경우
sudo mkdir -p /etc/selinux
echo 'SELINUX=disabled' | sudo tee /etc/selinux/config
```

**변수 누락 문제:**
```bash
# Ansible 실행 시 필요한 변수 직접 전달
ansible-playbook -e "kubernetes_version=1.28.15" -e "container_runtime_version=1.7.27" playbook.yml
```

**노드 Ready 상태 확인:**
```bash
# 노드 상태 지속 확인
watch kubectl get nodes

# CNI 플러그인 상태 확인
kubectl get pods -n kube-flannel
kubectl get daemonset -n kube-flannel

# 워커 노드에서 kubelet 로그 확인
sudo journalctl -u kubelet -f
```

#### 7. CrashLoopBackOff 문제 해결 🆕

**Flannel Pod 충돌 문제:**
```bash
# 문제가 있는 Flannel Pod 삭제 (DaemonSet이 자동 재생성)
kubectl delete pod <flannel-pod-name> -n kube-flannel

# kube-proxy 문제 해결
kubectl delete pod <kube-proxy-pod-name> -n kube-system
```

**CNI 충돌 문제 (Calico vs Flannel):**
```bash
# Calico 설정 제거 (Flannel 사용 시)
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/tigera-operator.yaml
kubectl delete namespace tigera-operator

# 모든 Pod 상태 확인
kubectl get pods -A --field-selector=status.phase!=Running
```

#### 8. Helm 설치 및 구성 🆕

**ARM64 환경에서 Helm 수동 설치:**
```bash
# Helm v3.13.0 ARM64 다운로드 및 설치
wget https://get.helm.sh/helm-v3.13.0-linux-arm64.tar.gz
tar -zxvf helm-v3.13.0-linux-arm64.tar.gz
sudo mv linux-arm64/helm /usr/local/bin/helm
sudo chmod +x /usr/local/bin/helm

# PATH 업데이트
echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
source ~/.bashrc

# Helm 저장소 추가
helm repo add stable https://charts.helm.sh/stable
helm repo update

# 설치 확인
helm version
helm repo list
```

### 클러스터 재설정

```bash
# 클러스터 완전 재설정 (주의!)
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/etcd/
sudo rm -rf ~/.kube/
```

## 🚀 고급 사용법

### 태그를 사용한 부분 실행

```bash
# 공통 설정만 실행
./scripts/setup-cluster.sh --tags "common"

# Kubernetes 설치만 실행
./scripts/setup-cluster.sh --tags "kubernetes"

# CircleCI Runner만 실행
./scripts/setup-cluster.sh --tags "circleci"
```

### 멀티 마스터 HA 구성

고가용성 클러스터를 위해 여러 마스터 노드를 구성할 수 있습니다:

```yaml
k8s_masters:
  hosts:
    k8s-master-01:
      ansible_host: 192.168.1.10
    k8s-master-02:
      ansible_host: 192.168.1.11
    k8s-master-03:
      ansible_host: 192.168.1.12
```

## 📝 업데이트 및 유지보수

### 정기적인 업데이트

```bash
# Ansible collections 업데이트
ansible-galaxy install -r requirements.yml --force

# Python 패키지 업데이트
pip install -r python-requirements.txt --upgrade
```

### 백업 및 복구

중요한 설정 파일들을 정기적으로 백업하세요:
- `inventory/hosts.yml`
- `group_vars/all/vault.yml`
- Kubernetes etcd 데이터

## 🤝 기여 및 지원

문제가 발생하거나 개선 사항이 있으면 GitHub Issues를 통해 알려주세요.

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

---

## 🧪 테스트 환경

**성공적으로 테스트된 환경:**
- **OS**: Rocky Linux 8.10 (Green Obsidian)
- **아키텍처**: aarch64 (ARM64)
- **Kubernetes**: v1.28.15
- **Container Runtime**: containerd 1.7.27
- **CNI**: Flannel
- **Python**: 3.12.10
- **Ansible**: 9.2.0 (core 2.16.3) - 시스템 패키지
- **클러스터**: 마스터 1개 + 워커 1개 (멀티 노드)

**테스트 완료 단계:**
1. ✅ 스왑 메모리 해제
2. ✅ containerd 설치 및 구성 (ARM64 GitHub 릴리스)
3. ✅ iptables 네트워크 구성
4. ✅ systemd cgroup driver 설정
5. ✅ kubeadm, kubelet, kubectl 설치
6. ✅ 클러스터 초기화
7. ✅ Flannel CNI 네트워크 플러그인 설치
8. ✅ 마스터 노드에서 Pod 스케줄링 활성화
9. ✅ **워커 노드 추가 및 클러스터 조인** 🆕
10. ✅ **멀티 노드 네트워킹 및 Pod 스케줄링** 🆕
11. ✅ **Helm v3.13.0 설치 및 저장소 구성** 🆕
12. ✅ **CrashLoopBackOff 문제 해결** 🆕
13. ✅ **CNI 충돌 문제 해결 (Calico vs Flannel)** 🆕
14. ✅ **DNS 기능 및 FQDN 해석 검증** 🆕
15. ✅ **전체 클러스터 안정성 검증 완료** 🆕

### 🎯 실제 환경 테스트 결과 (2025-06-11)

**테스트 클러스터 정보:**
- **마스터 노드**: 198.19.249.181 (rocky8-master)
- **워커 노드**: 198.19.249.230 (rocky8-worker1)
- **SSH 인증**: root 사용자 키 기반 인증
- **네트워킹**: Flannel CNI로 노드 간 통신 완료

**최종 클러스터 상태:**
```bash
NAME             STATUS   ROLES           AGE    VERSION
rocky8-master    Ready    control-plane   131m   v1.28.15
rocky8-worker1   Ready    <none>          50s    v1.28.15
```

**실행 중인 시스템 Pod:**
- CoreDNS: 2개 포드 정상 실행
- Flannel: 각 노드별 1개씩 정상 실행  
- kube-proxy: 각 노드별 1개씩 정상 실행
- 모든 컨트롤 플레인 구성 요소 정상 작동

**추가 구성 요소:**
- **Helm**: v3.13.0 ARM64 설치 완료 (/usr/local/bin/helm)
- **안정적인 Helm 저장소**: https://charts.helm.sh/stable 추가됨
- **DNS 기능**: FQDN 해석 정상 작동 확인
- **네트워킹**: 10.244.0.0/16 Pod 네트워크, 노드 간 통신 정상

## 🔧 최근 개선사항 (v2.1) 🆕

**1. scripts 디렉토리 구조 완성**
- **setup-cluster.sh** (5.6KB): 전체 Kubernetes 클러스터 초기 설정 및 CircleCI 배포
- **add-node.sh** (15.4KB): 기존 클러스터에 새 노드 자동 추가 (master/worker 지원)
- **prepare-worker-node.sh** (11.7KB): 수동 워커 노드 준비 (Ansible 실패 시 백업 방법)
- **rollback.sh** (9.7KB): 클러스터 설치 실패 시 시스템 복구 (3단계 롤백 레벨)

**2. 워커 노드 추가 프로세스 완료** 🎯
- 실제 환경에서 rocky8-master + rocky8-worker1 멀티 노드 클러스터 구축 성공
- SSH 키 관리 및 권한 문제 해결 가이드 추가
- SELinux 설정 파일 누락 문제 및 해결 방법 문서화
- containerd 1.7.27 ARM64 수동 설치 프로세스 검증

**3. Helm 설치 및 구성 완료**
- Helm v3.13.0 ARM64 설치 및 설정
- 안정적인 Helm 저장소 구성
- 애플리케이션 배포 준비 완료

**4. 클러스터 안정성 검증 완료**
- 모든 시스템 Pod 정상 작동 확인 (CoreDNS, Flannel, kube-proxy)
- CrashLoopBackOff 문제 해결 방법 문서화
- CNI 충돌 문제(Calico vs Flannel) 해결
- DNS 기능 및 FQDN 해석 정상 동작 확인

**5. Ansible 설치 최적화 및 문제 해결** 🆕
- Rocky Linux 8 환경에 최적화된 설치 방법 정립
- python-requirements.txt 최적화 (시스템 Ansible 사용)
- Python 환경 혼재 문제 해결 가이드
- Ansible 7.x 버전 오류 해결 방법

**6. 실제 테스트 기반 문제 해결 가이드**
- SSH 연결 문제 해결 (sudo ssh root@ 방식)
- Ansible 변수 누락 문제 해결
- 수동 설치 시 필요한 모든 단계 문서화
- 롤백 및 복구 시나리오 완성
- SSH 키 기반 인증 방법 문서화
- SELinux 설정 파일 누락 시 자동 생성 방법 추가
- Ansible 변수 누락 문제 해결 방안 제공
- 수동 설치 방법을 통한 대안적 접근법 검증

**5. 멀티 노드 클러스터 안정성 검증** 🆕
- 마스터(198.19.249.181) + 워커(198.19.249.230) 구성 테스트 완료
- Flannel CNI를 통한 노드 간 네트워킹 정상 작동 확인
- 모든 시스템 Pod의 정상 실행 및 분산 배치 검증
- containerd 1.7.27 ARM64 환경에서 안정성 확인

---

## 📈 프로젝트 버전 히스토리

### v2.1 (2025-06-11) - 워커 노드 추가 테스트 및 안정성 향상 🆕
- **멀티 노드 클러스터 테스트 완료**: 마스터 + 워커 노드 실제 환경 검증
- **워커 노드 추가 프로세스 개선**: SSH 키 기반 인증 및 자동화 스크립트 강화
- **ARM64 환경 완전 지원**: containerd, Kubernetes 수동 설치 방법 검증
- **문제 해결 가이드 추가**: 실제 발생한 문제들에 대한 해결책 문서화
- **개선된 스크립트**: `add-node.sh`, `prepare-worker-node.sh` 업데이트

### v2.0 (이전) - 아키텍처 호환성 및 에러 처리 개선
- 아키텍처 호환성 개선 (ARM64/x86_64 자동 감지)
- 에러 처리 강화 (`ignore_errors` 제거, `failed_when` 적용)
- 안정성 향상

---

### 🚀 **Rocky Linux 8 권장 설치 방법**

**새로운 환경에서 처음 설치할 때 (모든 패키지 시스템 설치):**
```bash
# 1. 시스템 업데이트 및 EPEL 저장소 활성화
sudo dnf update -y
sudo dnf install -y epel-release

# 2. 최소 필수 패키지만 설치 (pip 불필요!)
sudo dnf install -y ansible python3-kubernetes python3-openshift jq bind-utils git

# 3. 프로젝트 다운로드
git clone <repository-url>
cd circleci-k8s-ansible

# 4. Ansible 컬렉션 설치
ansible-galaxy collection install -r requirements.yml

# 5. 설치 확인
ansible --version
ansible localhost -m ping
python3 -c "import kubernetes, openshift; print('Python 패키지 OK')"
jq --version && dig google.com +short | head -1 && echo "네이티브 도구 OK"
```

**장점**: 
- ✅ **최소 설치**: 필수 패키지만 설치하여 시스템 리소스 절약
- ✅ **네이티브 도구 사용**: Python 대신 빠른 네이티브 도구 활용
- ✅ **안정적인 호환성**: EPEL에서 검증된 버전들만 사용
- ✅ **통합 관리**: `dnf update`로 한 번에 업데이트
- ✅ **의존성 최소화**: 불필요한 Python 라이브러리 제거

**도구 매핑**:
- JSON 처리: `jq` (python-jsonpath 대신)
- DNS 조회: `dig`, `nslookup` (python-dns 대신)  
- HTTP 요청: `curl` (python-requests 대신)
- 네트워크 계산: `ipcalc` (python-netaddr 대신)

**참고**: 이 도구를 프로덕션 환경에서 사용하기 전에 테스트 환경에서 충분히 검증하시기 바랍니다. 