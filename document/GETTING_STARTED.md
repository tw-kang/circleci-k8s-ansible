# 🏁 시작하기 - 완전 초기 설정 가이드

> **처음 이 프로젝트를 사용하는 사용자를 위한 완전한 초기 설정 가이드** (20분 완성)

## 🎯 개요

**총 4단계로 완전한 Kubernetes + CircleCI 환경 구축:**

1. ✅ **환경 준비** (5분)
2. ✅ **프로젝트 다운로드 및 설정** (5분)  
3. ✅ **보안 설정** (5분)
4. ✅ **실행 및 확인** (5분)

**총 소요시간: 약 20분**

---

## 🖥️ 1단계: 환경 준비 (5분)

### 📋 시스템 요구사항

| 구분 | 최소 사양 | 권장 사양 |
|------|-----------|-----------|
| **관리 서버** | 1 vCPU, 1GB RAM, 5GB 디스크 | 2 vCPU, 2GB RAM, 10GB 디스크 |
| **마스터 노드** | 2 vCPU, 4GB RAM, 20GB 디스크 | 4 vCPU, 8GB RAM, 50GB 디스크 |
| **워커 노드** | 1 vCPU, 2GB RAM, 10GB 디스크 | 2 vCPU, 4GB RAM, 20GB 디스크 |

**지원 OS**: Rocky Linux 8, CentOS 8, RHEL 8, AlmaLinux 8
**지원 아키텍처**: x86_64, ARM64 (aarch64)

### 🔧 모든 대상 노드에서 실행

**마스터 노드와 워커 노드 모두에서 다음 명령어를 실행하세요:**

```bash
# 1. 시스템 업데이트 및 기본 패키지 설치
sudo dnf update -y
sudo dnf install -y epel-release python3 openssh-server

# 2. SSH 서비스 활성화
sudo systemctl enable --now sshd

# 3. root 비밀번호 설정 (모든 노드에서 동일하게!)
sudo passwd root
# 예시: K8s123!@# (나중에 Vault에 저장할 비밀번호)

# 4. 방화벽 비활성화 (권장)
sudo systemctl disable --now firewalld

# 5. SELinux 비활성화 (권장)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

### 🖥️ 관리 서버에서 실행

**Ansible을 실행할 관리 서버에서 다음을 설치하세요:**

```bash
# Rocky Linux/CentOS/RHEL인 경우
sudo dnf install -y ansible python3-kubernetes python3-openshift jq bind-utils expect git

# Ubuntu/Debian인 경우  
sudo apt update
sudo apt install -y ansible python3-kubernetes jq dnsutils expect git
pip3 install openshift
```

---

## 📦 2단계: 프로젝트 다운로드 및 설정 (5분)

### 🔄 프로젝트 다운로드

```bash
# 1. 프로젝트 클론
git clone https://github.com/your-username/circleci-k8s-ansible.git
cd circleci-k8s-ansible

# 2. 실행 권한 부여
chmod +x scripts/*.sh

# 3. 프로젝트 구조 확인
ls -la
```

### 📝 노드 정보 설정

**`inventory/staging/hosts.yml` 파일을 실제 IP 주소로 수정하세요:**

```bash
# 파일 편집
nano inventory/staging/hosts.yml
```

**실제 IP 주소로 변경:**
```yaml
all:
  children:
    k8s_cluster:
      children:
        k8s_masters:
          hosts:
            k8s-master-01:
              ansible_host: 192.168.1.100  # 👈 실제 마스터 노드 IP
              ansible_user: root
              node_role: master
        k8s_workers:
          hosts:
            k8s-worker-01:
              ansible_host: 192.168.1.101  # 👈 실제 워커 노드 IP  
              ansible_user: root
              node_role: worker
            k8s-worker-02:
              ansible_host: 192.168.1.102  # 👈 추가 워커 노드 (선택사항)
              ansible_user: root
              node_role: worker
```

### ⚙️ CircleCI 설정 (선택사항)

CircleCI를 사용할 예정이라면 `group_vars/all/vars.yml`을 수정하세요:

```bash
nano group_vars/all/vars.yml
```

**다음 부분을 실제 값으로 변경:**
```yaml
circleci:
  runner:
    namespace: "your-organization"        # 👈 실제 조직명
    resource_class: "your-resource-class" # 👈 실제 리소스 클래스명
    token: "{{ vault_circleci_token }}"
    replicas: 2
```

---

## 🔐 3단계: 보안 설정 (5분)

### 🔑 Vault 비밀번호 파일 생성

```bash
# 1. Vault 비밀번호 파일 생성 (권장 방법)
echo "ansible123" > .vault-password

# 2. 파일 권한 설정 (보안상 중요!)
chmod 600 .vault-password

# 3. 확인
ls -la .vault-password
```

### 🛡️ Vault 파일 설정

**암호화된 vault 파일을 편집합니다:**

```bash
# Vault 파일 편집
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault-password
```

**vault.yml 파일 내용:**
```yaml
---
# CircleCI Runner Token (CircleCI 사용시 필수)
vault_circleci_token: "CHANGE_ME_TO_YOUR_ACTUAL_CIRCLECI_TOKEN"

# SSH 비밀번호 (초기 SSH 키 배포용)
vault_ssh_password: "K8s123!@#"  # 👈 1단계에서 설정한 root 비밀번호

# 추가 보안 설정 (선택사항)
vault_admin_password: "your-admin-password"
```

### 🎫 CircleCI 토큰 설정 (CircleCI 사용시)

**CircleCI를 사용할 예정이라면:**

1. **CircleCI 웹 콘솔** 로그인
2. **프로젝트 설정** → **Self-Hosted Runners**
3. **Create Resource Class** 클릭
4. **토큰 복사** (한 번만 표시됨!)
5. **Vault 파일에 토큰 추가:**

```bash
# Vault 파일 편집
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault-password

# vault_circleci_token 값을 실제 토큰으로 변경
vault_circleci_token: "your-actual-token-here"
```

---

## ✅ 4단계: 실행 및 확인 (5분)

### 🔌 연결 테스트

```bash
# 모든 노드 연결 테스트
ansible all -i inventory/staging/hosts.yml -m ping --vault-password-file .vault-password
```

**✅ 성공 예시:**
```
k8s-master-01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
k8s-worker-01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

**❌ 연결 실패시:**
```bash
# SSH 키 수동 복사
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.100
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.101
```

### 🚀 클러스터 구축 실행

```bash
# 가장 일반적인 사용 (Kubernetes + CircleCI)
./scripts/setup-cluster.sh cluster-circleci \
  -i inventory/staging/hosts.yml \
  --vault-password-file .vault-password
```

**실행 시간**: 약 15-20분

### 🔍 완료 확인

**클러스터 상태 확인:**
```bash
# 마스터 노드 접속
ssh root@192.168.1.100

# 클러스터 상태
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes -o wide

# 예상 결과:
# NAME            STATUS   ROLES           AGE   VERSION
# k8s-master-01   Ready    control-plane   5m    v1.28.15
# k8s-worker-01   Ready    worker          4m    v1.28.15
```

**CircleCI Runner 확인 (선택사항):**
```bash
# Runner Pod 상태
kubectl get pods -n circleci

# Runner 로그
kubectl logs -n circleci -l app.kubernetes.io/name=container-agent
```

---

## 🎉 완료!

축하합니다! 이제 다음이 준비되었습니다:

- ✅ **완전한 Kubernetes 클러스터** (v1.28.15)
- ✅ **CircleCI Self-Hosted Runner** (선택사항)
- ✅ **자동화된 CI/CD 환경**

### 📚 다음 단계

- 📖 **빠른 사용법**: [QUICK_START.md](QUICK_START.md)
- 🔐 **고급 보안 설정**: [SECURITY_SETUP.md](SECURITY_SETUP.md)
- 🔧 **워커 노드 추가**: `./scripts/setup-cluster.sh add-node --node-ip 192.168.1.103 --node-name k8s-worker-03`

---

## 🆘 문제 해결

### 자주 발생하는 문제

| 문제 | 원인 | 해결방법 |
|------|------|----------|
| SSH 연결 실패 | 키 배포 안됨 | `ssh-copy-id` 수동 실행 |
| Vault 오류 | 파일 손상 | `ansible-vault edit` 재실행 |
| 패키지 설치 실패 | 네트워크 문제 | `ping 8.8.8.8` 확인 |
| 방화벽 오류 | 포트 차단 | `firewalld` 비활성화 |

### 🔄 완전 초기화

```bash
# 모든 설정 초기화
./scripts/rollback.sh

# 수동 초기화 (마스터 노드에서)
kubeadm reset -f
sudo rm -rf /etc/kubernetes/ ~/.kube/ /var/lib/kubelet/
```

---

**🎯 설정 완료!** 이제 [QUICK_START.md](QUICK_START.md)를 참조하여 빠르게 사용하세요!