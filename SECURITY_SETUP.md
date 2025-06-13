# 🔐 보안 설정 완벽 가이드

> CircleCI Kubernetes 클러스터의 **보안 설정**을 단계별로 안내하는 완벽한 가이드입니다.

## 🎯 보안 설정 개요

이 프로젝트는 **Ansible Vault**를 사용하여 민감한 정보를 안전하게 관리합니다. 설정해야 할 보안 요소는 다음과 같습니다:

- 🔑 **SSH 키 관리**: 자동 생성 및 배포
- 🔐 **Ansible Vault**: 비밀 정보 암호화
- 🎫 **CircleCI 토큰**: Runner 인증
- 🔒 **SSH 비밀번호**: 초기 접근용

## 🚀 빠른 보안 설정 (3단계)

### 1단계: Ansible Vault 설정

#### Vault 파일 생성 및 편집
```bash
# Vault 파일 편집 (비밀번호 입력 필요)
ansible-vault edit group_vars/vault.yml
```

#### Vault 파일 내용 입력
```yaml
# CircleCI Runner 토큰 (필수)
vault_circleci_token: "your-actual-circleci-runner-token-here"

# SSH 비밀번호 (SSH 키 자동 배포용)
vault_ssh_password: "your-ssh-password-here"

# 추가 보안 설정 (선택사항)
vault_admin_password: "your-admin-password"
vault_database_password: "your-database-password"
```

### 2단계: CircleCI 토큰 발급

#### CircleCI 웹 콘솔에서 토큰 생성
1. **CircleCI 로그인** → 프로젝트 선택
2. **Project Settings** → **Self-Hosted Runners**
3. **Create Resource Class** 클릭
4. **Resource Class 정보 입력**:
   ```
   Namespace: your-organization
   Resource Class: your-resource-class
   Description: Kubernetes Self-Hosted Runner
   ```
5. **Runner Token 복사** (한 번만 표시됨!)

#### group_vars/all.yml에서 설정 확인
```yaml
circleci:
  runner:
    namespace: "your-organization"        # 👈 실제 값으로 변경
    resource_class: "your-resource-class" # 👈 실제 값으로 변경
    token: "{{ vault_circleci_token }}"   # Vault에서 자동 참조
    replicas: 2
```

### 3단계: SSH 보안 설정

#### SSH 키 자동 생성 확인
```bash
# SSH 키 존재 확인
ls -la ~/.ssh/id_ed25519*

# 없으면 setup-cluster.sh가 자동 생성
# 있으면 기존 키 사용
```

#### SSH 비밀번호 설정 (초기 접근용)
```bash
# 모든 대상 노드에서 동일한 root 비밀번호 설정
sudo passwd root
```

## 📚 상세 보안 설정 가이드

### 🔐 Ansible Vault 심화 설정

#### Vault 비밀번호 파일 생성 (권장)
```bash
# 1. Vault 비밀번호 파일 생성
echo "your-strong-vault-password" > ~/.ansible-vault-pass

# 2. 파일 권한 설정 (중요!)
chmod 600 ~/.ansible-vault-pass

# 3. 스크립트에서 사용
./scripts/setup-cluster.sh cluster-circleci --vault-password ~/.ansible-vault-pass
```

#### Vault 파일 관리 명령어
```bash
# Vault 파일 보기
ansible-vault view group_vars/vault.yml

# Vault 파일 편집
ansible-vault edit group_vars/vault.yml

# Vault 비밀번호 변경
ansible-vault rekey group_vars/vault.yml

# 일반 파일을 Vault로 암호화
ansible-vault encrypt group_vars/vault.yml

# Vault 파일을 일반 파일로 복호화
ansible-vault decrypt group_vars/vault.yml
```

### 🔑 SSH 키 관리 심화

#### SSH 키 수동 생성 (고급 사용자용)
```bash
# 1. ED25519 키 생성 (권장)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "k8s-cluster-$(date +%s)"

# 2. RSA 키 생성 (호환성 필요시)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -C "k8s-cluster-$(date +%s)"

# 3. 키 권한 설정
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

#### SSH 키 수동 배포
```bash
# 각 노드에 SSH 키 복사
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.10  # 마스터
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.11  # 워커1
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.12  # 워커2

# SSH 연결 테스트
ssh -i ~/.ssh/id_ed25519 root@192.168.1.10 "echo 'SSH 연결 성공!'"
```

#### SSH 설정 최적화
```bash
# ~/.ssh/config 파일 생성
cat > ~/.ssh/config << EOF
Host k8s-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ConnectTimeout 10
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host k8s-master-01
    HostName 192.168.1.10

Host k8s-worker-01
    HostName 192.168.1.11

Host k8s-worker-02
    HostName 192.168.1.12
EOF

chmod 600 ~/.ssh/config
```

### 🎫 CircleCI 보안 설정

#### Resource Class 보안 설정
```yaml
# group_vars/all.yml
circleci:
  runner:
    namespace: "your-org"
    resource_class: "k8s-runner"
    token: "{{ vault_circleci_token }}"
    
    # 보안 설정
    security:
      # Runner가 사용할 수 있는 이미지 제한
      allowed_images:
        - "cimg/base:stable"
        - "cimg/node:lts"
        - "cimg/python:3.9"
      
      # 리소스 제한
      resources:
        limits:
          cpu: "2"
          memory: "4Gi"
          ephemeral_storage: "10Gi"
        requests:
          cpu: "500m"
          memory: "1Gi"
```

#### CircleCI 프로젝트 보안 설정
```yaml
# .circleci/config.yml 보안 예제
version: 2.1

# 보안 컨텍스트 사용
workflows:
  secure-workflow:
    jobs:
      - secure-job:
          context: 
            - production-secrets  # CircleCI 컨텍스트 사용
          filters:
            branches:
              only: main  # main 브랜치에서만 실행

jobs:
  secure-job:
    resource_class: your-org/k8s-runner
    steps:
      - checkout
      - run:
          name: "보안 검사"
          command: |
            # 민감한 정보 마스킹
            echo "Running on: $(hostname)"
            echo "User: $(whoami)"
            # 환경 변수는 CircleCI 컨텍스트에서 관리
```

### 🔒 네트워크 보안 설정

#### 방화벽 설정 (선택사항)
```yaml
# group_vars/all.yml
network:
  firewall_enabled: true
  
  # 허용할 포트 목록
  allowed_ports:
    - "22/tcp"      # SSH
    - "6443/tcp"    # Kubernetes API
    - "2379-2380/tcp"  # etcd
    - "10250/tcp"   # kubelet
    - "10251/tcp"   # kube-scheduler
    - "10252/tcp"   # kube-controller-manager
    - "30000-32767/tcp"  # NodePort 서비스
```

#### 수동 방화벽 설정
```bash
# 모든 노드에서 실행
sudo firewall-cmd --permanent --add-port=22/tcp      # SSH
sudo firewall-cmd --permanent --add-port=6443/tcp    # K8s API
sudo firewall-cmd --permanent --add-port=2379-2380/tcp  # etcd
sudo firewall-cmd --permanent --add-port=10250/tcp   # kubelet
sudo firewall-cmd --permanent --add-port=10251/tcp   # scheduler
sudo firewall-cmd --permanent --add-port=10252/tcp   # controller
sudo firewall-cmd --permanent --add-port=30000-32767/tcp  # NodePort

# 설정 적용
sudo firewall-cmd --reload

# 상태 확인
sudo firewall-cmd --list-all
```

## 🛡️ 보안 모범 사례

### 1. 비밀번호 정책
```bash
# 강력한 비밀번호 생성
openssl rand -base64 32

# 또는 pwgen 사용
pwgen -s 32 1
```

### 2. 정기 보안 점검
```bash
# SSH 키 로테이션 (월 1회 권장)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_new
# 새 키로 교체 후 기존 키 삭제

# Vault 비밀번호 변경 (분기 1회 권장)
ansible-vault rekey group_vars/vault.yml

# CircleCI 토큰 갱신 (반기 1회 권장)
# CircleCI 웹 콘솔에서 새 토큰 생성 후 Vault 업데이트
```

### 3. 접근 권한 관리
```yaml
# group_vars/all.yml
security:
  # sudo 권한 제한
  sudo_users:
    - "admin"
    - "k8s-admin"
  
  # SSH 접근 제한
  ssh_allowed_users:
    - "root"
    - "admin"
  
  # 불필요한 서비스 비활성화
  disabled_services:
    - "telnet"
    - "ftp"
    - "rsh"
```

## 🔍 보안 검증 및 테스트

### SSH 보안 테스트
```bash
# 1. SSH 키 인증 테스트
ssh -i ~/.ssh/id_ed25519 root@192.168.1.10 "echo 'SSH Key Auth: OK'"

# 2. 비밀번호 인증 비활성화 확인
ssh -o PreferredAuthentications=password root@192.168.1.10
# 실패해야 정상 (키 인증만 허용)

# 3. SSH 설정 확인
ssh -i ~/.ssh/id_ed25519 root@192.168.1.10 "cat /etc/ssh/sshd_config | grep -E '(PasswordAuthentication|PubkeyAuthentication)'"
```

### Vault 보안 테스트
```bash
# 1. Vault 파일 암호화 확인
file group_vars/vault.yml
# "ASCII text" 출력되면 암호화 안됨
# "$ANSIBLE_VAULT" 시작하면 암호화됨

# 2. Vault 내용 확인
ansible-vault view group_vars/vault.yml

# 3. Ansible에서 Vault 변수 사용 테스트
ansible all -i inventory/hosts.yml -m debug -a "var=vault_circleci_token" --ask-vault-pass
```

### CircleCI 보안 테스트
```bash
# 1. Runner 연결 상태 확인
kubectl get pods -n circleci
kubectl logs -n circleci -l app=circleci-runner

# 2. Runner 권한 확인
kubectl auth can-i --list --as=system:serviceaccount:circleci:circleci-runner

# 3. 네트워크 정책 확인 (설정된 경우)
kubectl get networkpolicies -n circleci
```

## 🚨 보안 사고 대응

### 1. SSH 키 유출 시
```bash
# 1. 즉시 새 SSH 키 생성
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_emergency

# 2. 모든 노드에 새 키 배포
for host in 192.168.1.10 192.168.1.11 192.168.1.12; do
    ssh-copy-id -i ~/.ssh/id_ed25519_emergency.pub root@$host
done

# 3. 기존 키 제거
rm ~/.ssh/id_ed25519*

# 4. 새 키로 이름 변경
mv ~/.ssh/id_ed25519_emergency ~/.ssh/id_ed25519
mv ~/.ssh/id_ed25519_emergency.pub ~/.ssh/id_ed25519.pub
```

### 2. CircleCI 토큰 유출 시
```bash
# 1. CircleCI 웹 콘솔에서 기존 토큰 무효화
# 2. 새 토큰 생성
# 3. Vault 파일 업데이트
ansible-vault edit group_vars/vault.yml

# 4. Runner 재배포
./scripts/setup-cluster.sh deploy-circleci
```

### 3. Vault 비밀번호 유출 시
```bash
# 1. 새 비밀번호로 Vault 재암호화
ansible-vault rekey group_vars/vault.yml

# 2. 새 비밀번호 파일 생성
echo "new-strong-password" > ~/.ansible-vault-pass-new
chmod 600 ~/.ansible-vault-pass-new

# 3. 기존 파일 삭제
rm ~/.ansible-vault-pass
mv ~/.ansible-vault-pass-new ~/.ansible-vault-pass
```

## 📋 보안 체크리스트

### 설치 전 체크리스트
- [ ] 모든 노드에서 root 비밀번호 설정
- [ ] SSH 서비스 활성화 확인
- [ ] 방화벽 정책 검토
- [ ] CircleCI 토큰 발급 완료
- [ ] Vault 비밀번호 설정

### 설치 후 체크리스트
- [ ] SSH 키 인증 작동 확인
- [ ] 비밀번호 인증 비활성화 확인
- [ ] Vault 파일 암호화 확인
- [ ] CircleCI Runner 연결 확인
- [ ] 불필요한 서비스 비활성화
- [ ] 로그 모니터링 설정

### 정기 점검 체크리스트 (월 1회)
- [ ] SSH 키 로테이션
- [ ] 시스템 업데이트 적용
- [ ] 로그 분석 및 이상 징후 확인
- [ ] 백업 상태 확인
- [ ] 접근 권한 재검토

---

## 🆘 보안 문제 발생 시

### 긴급 연락처
- **시스템 관리자**: [연락처 정보]
- **보안 담당자**: [연락처 정보]

### 로그 수집
```bash
# 보안 관련 로그 수집
sudo journalctl -u sshd --since "1 hour ago" > ssh-security.log
sudo journalctl -u kubelet --since "1 hour ago" > k8s-security.log
kubectl get events --sort-by='.lastTimestamp' > k8s-events.log
```

**🔐 보안은 지속적인 관리가 필요합니다. 정기적으로 이 가이드를 참조하여 보안 상태를 점검하세요!** 