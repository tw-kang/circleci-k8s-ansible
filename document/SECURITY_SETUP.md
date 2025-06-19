# 🔐 보안 설정 완벽 가이드

> **고급 사용자를 위한 CircleCI Kubernetes 클러스터 보안 설정 완벽 가이드**

## 🎯 보안 설정 개요

이 가이드는 **프로덕션 환경**에서 안전한 Kubernetes + CircleCI 환경을 구축하기 위한 **고급 보안 설정**을 다룹니다.

### 🔒 보안 요소들

1. **🔑 SSH 키 관리**: 강화된 인증 체계
2. **🔐 Ansible Vault**: 민감한 정보 암호화
3. **🎫 CircleCI 토큰**: 안전한 Runner 인증
4. **🛡️ 네트워크 보안**: 방화벽 및 포트 관리
5. **📋 접근 제어**: RBAC 및 권한 관리

---

## 🔐 1. Ansible Vault 고급 설정

### 🔑 강화된 Vault 비밀번호 관리

#### 복잡한 Vault 비밀번호 생성
```bash
# 강력한 Vault 비밀번호 생성 (32자리)
openssl rand -base64 32 > .vault-password

# 파일 권한 설정 (중요!)
chmod 600 .vault-password

# 소유자만 읽기 가능한지 확인
ls -la .vault-password
# 출력: -rw------- 1 user user 45 날짜 시간 .vault-password
```

#### Vault 파일 구조화
```bash
# Vault 파일 편집
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault-password
```

**강화된 vault.yml 구조:**
```yaml
---
# === CircleCI 인증 정보 ===
vault_circleci_token: "your-circleci-runner-token-here"
vault_circleci_namespace: "your-organization"
vault_circleci_resource_class: "your-resource-class"

# === SSH 인증 정보 ===
vault_ssh_password: "your-strong-ssh-password"

# === 관리자 계정 정보 ===
vault_admin_username: "k8s-admin"
vault_admin_password: "your-complex-admin-password"

# === 클러스터 보안 설정 ===
vault_cluster_ca_key_password: "your-ca-key-password"
vault_encryption_key: "your-etcd-encryption-key"

# === 외부 서비스 인증 ===
vault_registry_username: "your-registry-user"
vault_registry_password: "your-registry-pass"
vault_backup_key: "your-backup-encryption-key"
```

### 🔄 Vault 다중 환경 관리

#### 환경별 Vault 파일 구성
```bash
# 프로덕션 환경
inventory/production/group_vars/all/vault.yml

# 스테이징 환경  
inventory/staging/group_vars/all/vault.yml

# 개발 환경
inventory/development/group_vars/all/vault.yml
```

#### Vault 비밀번호 환경별 분리
```bash
# 환경별 Vault 비밀번호 파일
echo "production-vault-password" > .vault-password-prod
echo "staging-vault-password" > .vault-password-staging
echo "development-vault-password" > .vault-password-dev

# 모든 Vault 파일 권한 설정
chmod 600 .vault-password-*
```

---

## 🔑 2. SSH 보안 강화

### 🛡️ SSH 키 고급 관리

#### ED25519 키 생성 (최고 보안)
```bash
# 강화된 ED25519 키 생성
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/k8s_cluster_ed25519 \
  -C "k8s-cluster-$(date +%Y%m%d)-$(whoami)@$(hostname)"

# 키 권한 설정
chmod 600 ~/.ssh/k8s_cluster_ed25519
chmod 644 ~/.ssh/k8s_cluster_ed25519.pub
```

#### RSA 키 (호환성 필요시)
```bash
# 4096비트 RSA 키 생성
ssh-keygen -t rsa -b 4096 -a 100 -f ~/.ssh/k8s_cluster_rsa \
  -C "k8s-cluster-$(date +%Y%m%d)-$(whoami)@$(hostname)"
```

### 🔐 SSH 설정 최적화

#### ~/.ssh/config 보안 설정
```bash
cat > ~/.ssh/config << 'EOF'
# Kubernetes 클러스터 SSH 설정
Host k8s-*
    User root
    IdentityFile ~/.ssh/k8s_cluster_ed25519
    PubkeyAuthentication yes
    PasswordAuthentication no
    ChallengeResponseAuthentication no
    UsePAM no
    StrictHostKeyChecking yes
    UserKnownHostsFile ~/.ssh/known_hosts_k8s
    ConnectTimeout 10
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes
    Protocol 2

# 프로덕션 마스터 노드들
Host k8s-prod-master-*
    Port 22
    LogLevel ERROR

# 스테이징 환경
Host k8s-staging-*
    Port 22
    LogLevel INFO

EOF

chmod 600 ~/.ssh/config
```

### 🚪 SSH 접근 제한

#### 노드별 SSH 보안 설정
```bash
# 각 노드에서 실행할 SSH 보안 설정
cat > secure_ssh.sh << 'EOF'
#!/bin/bash
# SSH 보안 강화 스크립트

# 1. SSH 설정 백업
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# 2. SSH 보안 설정 적용
cat >> /etc/ssh/sshd_config << 'SSHEOF'

# === Kubernetes 클러스터 SSH 보안 설정 ===
Protocol 2
Port 22
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding no
PrintMotd no
ClientAliveInterval 600
ClientAliveCountMax 0
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 60

# 접근 허용 사용자 제한
AllowUsers root

# 로그 레벨 설정
LogLevel VERBOSE

SSHEOF

# 3. SSH 서비스 재시작
systemctl reload sshd

echo "SSH 보안 설정 완료"
EOF

chmod +x secure_ssh.sh
```

---

## 🎫 3. CircleCI 보안 설정

### 🔐 Resource Class 보안 강화

#### 제한된 Resource Class 설정
```yaml
# group_vars/all/vars.yml
circleci:
  runner:
    namespace: "{{ vault_circleci_namespace }}"
    resource_class: "{{ vault_circleci_resource_class }}"
    token: "{{ vault_circleci_token }}"
    
    # 보안 설정
    security:
      # 허용된 이미지만 사용
      allowed_images:
        - "cimg/base:stable"
        - "cimg/node:lts"
        - "cimg/python:3.9"
        - "your-private-registry/approved-image:tag"
      
      # 리소스 제한 (중요!)
      resources:
        limits:
          cpu: "2"
          memory: "4Gi"
          ephemeral_storage: "10Gi"
        requests:
          cpu: "500m"
          memory: "1Gi"
          
    # 네트워크 정책
    network_policy:
      enabled: true
      egress:
        - to: []  # 인터넷 접근 허용
          ports:
            - protocol: TCP
              port: 443  # HTTPS만 허용
            - protocol: TCP
              port: 80   # HTTP 허용
```

### 🛡️ CircleCI 프로젝트 보안

#### 보안 강화된 .circleci/config.yml
```yaml
version: 2.1

# 보안 컨텍스트 사용 (중요!)
workflows:
  secure-ci-cd:
    jobs:
      - security-scan:
          context: 
            - security-context     # CircleCI 컨텍스트 사용
            - production-secrets   # 프로덕션 시크릿
          filters:
            branches:
              only: 
                - main
                - develop
      - deploy:
          requires:
            - security-scan
          context:
            - production-secrets
          filters:
            branches:
              only: main

jobs:
  security-scan:
    resource_class: your-org/secure-runner
    docker:
      - image: cimg/base:stable
    steps:
      - checkout
      - run:
          name: "보안 스캔"
          command: |
            # 이미지 취약점 스캔
            trivy image $DOCKER_IMAGE
            
            # 코드 보안 스캔
            bandit -r .
            
            # 의존성 보안 검사
            safety check
            
      - run:
          name: "시크릿 스캔"
          command: |
            # Git 히스토리의 시크릿 검사
            truffleHog --regex --entropy=False .
```

---

## 🛡️ 4. 네트워크 보안 설정

### 🔥 방화벽 설정

#### 자동 방화벽 설정 활성화
```yaml
# group_vars/all/vars.yml
network:
  firewall_enabled: true
  
  # Kubernetes 필수 포트
  k8s_ports:
    master:
      - "6443/tcp"      # Kubernetes API
      - "2379-2380/tcp" # etcd
      - "10250/tcp"     # kubelet
      - "10251/tcp"     # kube-scheduler
      - "10252/tcp"     # kube-controller-manager
    worker:
      - "10250/tcp"     # kubelet
      - "30000-32767/tcp" # NodePort 서비스
    common:
      - "22/tcp"        # SSH
      
  # CircleCI Runner 포트
  circleci_ports:
    - "443/tcp"         # HTTPS 통신
    - "8080/tcp"        # 메트릭 (선택사항)
```

#### 수동 방화벽 설정
```bash
# 프로덕션 마스터 노드 방화벽 설정
firewall-cmd --permanent --add-port=22/tcp      # SSH
firewall-cmd --permanent --add-port=6443/tcp    # K8s API
firewall-cmd --permanent --add-port=2379-2380/tcp # etcd
firewall-cmd --permanent --add-port=10250/tcp   # kubelet
firewall-cmd --permanent --add-port=10251/tcp   # scheduler
firewall-cmd --permanent --add-port=10252/tcp   # controller-manager

# 워커 노드 방화벽 설정
firewall-cmd --permanent --add-port=22/tcp      # SSH
firewall-cmd --permanent --add-port=10250/tcp   # kubelet
firewall-cmd --permanent --add-port=30000-32767/tcp # NodePort

# 설정 적용
firewall-cmd --reload
```

### 🌐 네트워크 정책

#### Kubernetes 네트워크 정책 적용
```yaml
# CircleCI 네임스페이스 네트워크 정책
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: circleci-network-policy
  namespace: circleci
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: container-agent
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from: []  # 인그레스 차단
  egress:
  - to: []    # 외부 통신 허용
    ports:
    - protocol: TCP
      port: 443  # HTTPS만
    - protocol: TCP
      port: 80   # HTTP
  - to:         # 내부 DNS 허용
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

---

## 📋 5. 접근 제어 (RBAC)

### 👤 Kubernetes RBAC 설정

#### CircleCI Runner 전용 ServiceAccount
```yaml
# CircleCI Runner용 RBAC 설정
apiVersion: v1
kind: ServiceAccount
metadata:
  name: circleci-runner
  namespace: circleci
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: circleci-runner-role
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "create", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: circleci-runner-binding
subjects:
- kind: ServiceAccount
  name: circleci-runner
  namespace: circleci
roleRef:
  kind: ClusterRole
  name: circleci-runner-role
  apiGroup: rbac.authorization.k8s.io
```

### 🔐 etcd 암호화

#### etcd 데이터 암호화 활성화
```yaml
# encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: "{{ vault_encryption_key | b64encode }}"
  - identity: {}
```

---

## 🔍 6. 보안 모니터링

### 📊 로그 모니터링

#### 중요 보안 이벤트 모니터링
```bash
# SSH 로그인 모니터링
tail -f /var/log/secure | grep "Accepted\|Failed"

# Kubernetes API 감사 로그
kubectl get events --sort-by='.lastTimestamp' | grep -E "(Failed|Error|Warning)"

# CircleCI Runner 로그 모니터링
kubectl logs -n circleci -l app.kubernetes.io/name=container-agent --tail=100
```

### 🔔 알림 설정

#### Slack 알림 스크립트
```bash
#!/bin/bash
# security_alert.sh - 보안 알림 스크립트

SLACK_WEBHOOK="your-slack-webhook-url"

send_alert() {
    local message="$1"
    local color="$2"
    
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"attachments\":[{\"color\":\"$color\",\"text\":\"🔐 K8s Security Alert: $message\"}]}" \
        $SLACK_WEBHOOK
}

# SSH 로그인 실패 감지
failed_ssh=$(tail -n 50 /var/log/secure | grep "Failed password" | wc -l)
if [ $failed_ssh -gt 5 ]; then
    send_alert "SSH 로그인 실패 $failed_ssh 회 감지!" "danger"
fi

# 디스크 사용량 확인
disk_usage=$(df / | awk 'NR==2 {print $5}' | cut -d'%' -f1)
if [ $disk_usage -gt 80 ]; then
    send_alert "디스크 사용량 $disk_usage% 임계치 초과!" "warning"
fi
```

---

## 🧪 7. 보안 테스트

### 🔍 보안 검증 스크립트

```bash
#!/bin/bash
# security_check.sh - 보안 설정 검증

echo "🔐 Kubernetes 클러스터 보안 검증 시작..."

# 1. SSH 키 인증 확인
echo "1. SSH 키 인증 확인..."
if ssh -o PasswordAuthentication=no root@k8s-master-01 "echo 'SSH 키 인증 성공'" 2>/dev/null; then
    echo "   ✅ SSH 키 인증 정상"
else
    echo "   ❌ SSH 키 인증 실패"
fi

# 2. Vault 파일 암호화 확인
echo "2. Vault 파일 암호화 확인..."
if file group_vars/all/vault.yml | grep -q "ASCII text"; then
    echo "   ✅ Vault 파일 암호화됨"
else
    echo "   ❌ Vault 파일이 암호화되지 않음"
fi

# 3. 방화벽 상태 확인
echo "3. 방화벽 상태 확인..."
ansible all -i inventory/staging/hosts.yml -m shell \
    -a "systemctl is-active firewalld" --one-line 2>/dev/null | grep -q "active" && \
    echo "   ✅ 방화벽 활성화됨" || echo "   ⚠️ 방화벽 비활성화됨"

# 4. RBAC 설정 확인
echo "4. RBAC 설정 확인..."
kubectl auth can-i create pods --as=system:serviceaccount:circleci:circleci-runner 2>/dev/null && \
    echo "   ✅ RBAC 설정 정상" || echo "   ❌ RBAC 설정 필요"

echo "🔐 보안 검증 완료!"
```

---

## 📚 보안 체크리스트

### ✅ 필수 보안 설정

- [ ] **Ansible Vault 암호화** - 모든 민감 정보 암호화
- [ ] **강력한 SSH 키** - ED25519 또는 4096비트 RSA 사용
- [ ] **SSH 비밀번호 인증 비활성화** - 키 기반 인증만 사용
- [ ] **방화벽 설정** - 필요한 포트만 개방
- [ ] **RBAC 구성** - 최소 권한 원칙 적용
- [ ] **네트워크 정책** - Pod간 통신 제한
- [ ] **etcd 암호화** - 데이터 저장 암호화
- [ ] **로그 모니터링** - 보안 이벤트 감시

### 🔄 정기 보안 점검

- [ ] **SSH 키 순환** (매 6개월)
- [ ] **Vault 비밀번호 변경** (매 3개월)  
- [ ] **CircleCI 토큰 갱신** (매 1년)
- [ ] **보안 업데이트 적용** (매월)
- [ ] **로그 검토** (매주)

---

**🔐 보안은 한 번 설정하고 끝나는 것이 아닙니다. 지속적인 모니터링과 업데이트가 필요합니다!** 