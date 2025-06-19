# CircleCI Kubernetes Self-Hosted Runner 자동화 프로젝트

> **Rocky Linux 8**에서 **Kubernetes 클러스터**를 자동으로 구축하고 **CircleCI self-hosted container runner**를 배포하는 완전 자동화 솔루션입니다.

## 🎯 프로젝트 개요

**단 2개 파일만 수정**하고 **1개 명령어만 실행**하면 완전한 Kubernetes + CircleCI 환경을 구축할 수 있습니다.

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

## 🚀 빠른 시작

### 📚 문서 가이드

| 문서 | 대상 | 소요 시간 | 설명 |
|------|------|-----------|------|
| 🏁 **[GETTING_STARTED.md](document/GETTING_STARTED.md)** | 처음 사용자 | 20분 | 완전한 초기 설정 가이드 |
| ⚡ **[QUICK_START.md](document/QUICK_START.md)** | 기존 사용자 | 5분 | 슈퍼 빠른 시작 가이드 |
| 🔐 **[SECURITY_SETUP.md](document/SECURITY_SETUP.md)** | 고급 사용자 | 15분 | 보안 설정 완벽 가이드 |

### 🎯 원클릭 실행 (설정 완료된 경우)

```bash
# 1. IP 설정 (inventory/staging/hosts.yml)
# 2. 실행!
./scripts/setup-cluster.sh cluster-circleci \
  -i inventory/staging/hosts.yml \
  --vault-password-file .vault-password
```

## 🔧 지원하는 5가지 배포 모드

| 모드 | 설명 | 실행 시간 | 사용 사례 |
|------|------|-----------|-----------|
| `cluster-only` | Kubernetes만 구축 | ~10분 | 클러스터만 먼저 구축 |
| `cluster-circleci` | K8s + CircleCI 함께 | ~15분 | **가장 일반적인 사용** |
| `add-node` | 기존 클러스터에 노드 추가 | ~5분 | 클러스터 확장 |
| `deploy-circleci` | 기존 클러스터에 CircleCI 추가 | ~3분 | 나중에 CircleCI 추가 |
| `add-node-circleci` | 노드 추가 + CircleCI | ~8분 | 확장과 CircleCI 동시 |

### 🔧 실행 예제

```bash
# 가장 일반적인 사용
./scripts/setup-cluster.sh cluster-circleci

# 워커 노드 추가
./scripts/setup-cluster.sh add-node --node-ip 192.168.1.12 --node-name k8s-worker-02

# 상세 출력으로 실행
./scripts/setup-cluster.sh cluster-only --verbose

# 실제 실행 전 확인
./scripts/setup-cluster.sh cluster-only --dry-run
```

## 📁 프로젝트 구조

```
circleci-k8s-ansible/
├── 📁 scripts/                    # 실행 스크립트
│   ├── setup-cluster.sh          # 🎯 메인 설치 스크립트 (5가지 모드)
│   ├── rollback.sh               # 🔄 롤백 스크립트
│   ├── validate-ansible.sh       # 🔍 Ansible 검증
│   └── verify-k8s-tools.sh       # ✅ Kubernetes 도구 검증
├── 📁 playbooks/                 # Ansible 플레이북
│   ├── cluster-circleci.yml      # Kubernetes + CircleCI
│   ├── cluster-only.yml          # Kubernetes만 설치
│   ├── add-node.yml              # 노드 추가
│   ├── add-node-circleci.yml     # 노드 추가 + CircleCI
│   ├── deploy-circleci.yml       # CircleCI만 배포
│   └── rollback.yml              # 시스템 롤백
├── 📁 inventory/                 # 인벤토리 설정
│   ├── staging/hosts.yml         # 🔧 스테이징 노드 정보
│   └── production/hosts.yml      # 🔧 프로덕션 노드 정보
├── 📁 group_vars/                # 변수 설정
│   ├── all/vars.yml              # 공통 설정
│   ├── all/vault.yml             # 🔐 보안 설정 (수정 필요)
│   ├── k8s_masters.yml           # 마스터 노드 설정
│   └── k8s_workers.yml           # 워커 노드 설정
├── 📁 roles/                     # Ansible 역할
│   ├── kubernetes-common/        # 공통 Kubernetes 설정
│   ├── kubernetes-master/        # 마스터 노드 설정
│   ├── kubernetes-worker/        # 워커 노드 설정
│   └── circleci-runner/          # CircleCI Runner 설정
├── 📁 document/                  # 사용자 가이드
│   ├── GETTING_STARTED.md        # 🏁 완전 초기 설정 가이드 (20분)
│   ├── QUICK_START.md            # ⚡ 빠른 시작 가이드 (5분)
│   └── SECURITY_SETUP.md         # 🔐 고급 보안 설정 가이드
└── ansible.cfg                   # Ansible 설정
```

## ✅ 완료 확인

### 🔍 클러스터 상태
```bash
# 노드 상태 확인
kubectl get nodes -o wide

# 모든 Pod 상태
kubectl get pods -A

# 클러스터 정보
kubectl cluster-info
```

### 🏃 CircleCI Runner (선택사항)
```bash
# Runner Pod 상태
kubectl get pods -n circleci

# Runner 로그
kubectl logs -n circleci -l app.kubernetes.io/name=container-agent
```

## 🔄 문제 해결

### 자주 발생하는 문제

```bash
# SSH 연결 실패
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@target-node-ip

# Ansible 실행 오류
ansible all -i inventory/staging/hosts.yml -m ping

# 클러스터 초기화
./scripts/rollback.sh
```

## 📈 버전 정보

- **Kubernetes**: v1.28.15
- **containerd**: v1.7.27  
- **Ansible**: 9.0+
- **지원 OS**: Rocky Linux 8, CentOS 8, RHEL 8, AlmaLinux 8
- **지원 아키텍처**: x86_64, ARM64 (aarch64)

## 🚀 최신 개선사항 (v2.0)

### 🔧 주요 수정사항

1. **동적 Join Token 생성**: `kubeadm token create` 사용으로 24시간 만료 문제 해결
2. **PATH 환경변수 개선**: 모든 Kubernetes 명령어에 경로 보장
3. **Kubernetes 도구 설치 검증**: `verify-k8s-tools.sh` 스크립트 추가
4. **SSH 비밀번호 Vault 연동**: `ansible-vault view` 명령어로 간단화
5. **노드 추가 순서 최적화**: inventory → SSH → playbook 순서로 개선

### 🚀 새로운 기능

```bash
# Kubernetes 도구 검증
./scripts/verify-k8s-tools.sh

# 설치 시 검증 포함
./scripts/setup-cluster.sh cluster-only --verify-k8s-tools
```

---

**🎯 이제 시작하세요!** 위의 3단계만 따라하면 완전한 Kubernetes + CircleCI 환경이 구축됩니다!

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.