# ⚡ 빠른 시작 가이드 (5분 완성)

> **단 2개 파일만 수정**하고 **1개 명령어만 실행**하면 완전한 Kubernetes + CircleCI 환경이 구축됩니다!

## 🎯 시작하기 전에

### ✅ 체크리스트
- [ ] 모든 대상 노드에서 Rocky Linux 8 실행 중
- [ ] 모든 노드에서 인터넷 연결 가능
- [ ] 개발장비에서 모든 대상 노드로 네트워크 접근 가능
- [ ] CircleCI 계정 및 프로젝트 준비됨

### 📋 하드웨어 요구사항
```
마스터 노드: 2 CPU, 4GB RAM, 20GB 디스크
워커 노드:   1 CPU, 2GB RAM, 10GB 디스크
```

## 🚀 3단계 완성

### 1️⃣ 모든 대상 노드에서 실행 (마스터 + 워커)
```bash
# 기본 패키지 설치
sudo dnf update -y && sudo dnf install -y epel-release python3 openssh-server

# SSH 서비스 시작
sudo systemctl enable --now sshd

# root 비밀번호 설정 (모든 노드에서 동일하게)
sudo passwd root
```

### 2️⃣ 개발장비에서 실행 (Ansible 관리 서버)
```bash
# Ansible 설치
sudo dnf install -y ansible python3-kubernetes python3-openshift jq bind-utils expect

# 프로젝트 다운로드
git clone <repository-url>
cd circleci-k8s-ansible
```

### 3️⃣ 설정 파일 수정 (2개 파일만!)

#### 📝 `inventory/hosts.yml` - 노드 정보 수정
```yaml
all:
  children:
    k8s_cluster:
      children:
        k8s_masters:
          hosts:
            k8s-master-01:
              ansible_host: 192.168.1.10  # 👈 실제 마스터 IP로 변경
              ansible_user: root
              node_role: master
        k8s_workers:
          hosts:
            k8s-worker-01:
              ansible_host: 192.168.1.11  # 👈 실제 워커 IP로 변경
              ansible_user: root
              node_role: worker
```

#### 🔐 `group_vars/all/vault.yml` - 보안 설정
```bash
# 1. CircleCI 토큰 발급
# CircleCI 웹 콘솔 → Project Settings → Self-Hosted Runners → Create Resource Class

# 2. Vault 파일 편집
ansible-vault edit group_vars/all/vault.yml

# 3. 다음 내용 입력 후 저장
vault_circleci_token: "your-actual-circleci-runner-token"
vault_ssh_password: "your-ssh-password"
```

#### ⚙️ `group_vars/all.yml` - CircleCI 설정 확인
```yaml
circleci:
  runner:
    namespace: "your-organization"        # 👈 실제 값으로 변경
    resource_class: "your-resource-class" # 👈 실제 값으로 변경
```

## 🎯 실행!

### 가장 일반적인 사용 (Kubernetes + CircleCI)
```bash
./scripts/setup-cluster.sh cluster-circleci
```

### 다른 모드들
```bash
# Kubernetes만 구축
./scripts/setup-cluster.sh cluster-only

# 기존 클러스터에 노드 추가
./scripts/setup-cluster.sh add-node --node-ip 192.168.1.12 --node-name k8s-worker-02

# 기존 클러스터에 CircleCI만 추가
./scripts/setup-cluster.sh deploy-circleci

# 노드 추가 + CircleCI 설정
./scripts/setup-cluster.sh add-node-circleci --node-ip 192.168.1.12 --node-name k8s-worker-02
```

## ✅ 완료 확인

### Kubernetes 클러스터 확인
```bash
# 노드 상태 확인
kubectl get nodes

# 모든 Pod 상태 확인
kubectl get pods -A

# 클러스터 정보
kubectl cluster-info
```

### CircleCI Runner 확인
```bash
# Runner Pod 상태
kubectl get pods -n circleci

# Runner 로그 확인
kubectl logs -n circleci -l app=circleci-runner

# Runner 서비스 확인
kubectl get svc -n circleci
```

## 🔧 문제 해결

### SSH 연결 실패 시
```bash
# SSH 키 수동 복사
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@target-node-ip

# SSH 연결 테스트
ssh -i ~/.ssh/id_ed25519 root@target-node-ip
```

### Ansible 실행 오류 시
```bash
# 연결 테스트
ansible all -i inventory/hosts.yml -m ping

# Vault 비밀번호 확인
ansible-vault view group_vars/all/vault.yml
```

### 클러스터 초기화 필요 시
```bash
# 완전 롤백
./scripts/rollback.sh
```

## 🎉 성공!

축하합니다! 이제 다음이 준비되었습니다:

- ✅ **완전한 Kubernetes 클러스터**
- ✅ **CircleCI Self-Hosted Runner**
- ✅ **자동화된 CI/CD 환경**

### 다음 단계
1. **CircleCI 프로젝트 설정**: `.circleci/config.yml`에서 `resource_class` 사용
2. **애플리케이션 배포**: `kubectl apply -f your-app.yaml`
3. **모니터링 설정**: Prometheus, Grafana 등 추가 도구 설치

---

## 📚 더 자세한 정보

- 📖 **전체 가이드**: [README.md](README.md)
- 🔐 **보안 설정**: [SECURITY_SETUP.md](SECURITY_SETUP.md)  
- 🔧 **워커 노드 추가**: [WORKER_NODE_SETUP.md](WORKER_NODE_SETUP.md)

**🚀 이제 시작하세요! 5분이면 완성됩니다!** 