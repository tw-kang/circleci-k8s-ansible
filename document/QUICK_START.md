# ⚡ 빠른 시작 가이드 (5분 완성)

> **이미 환경 설정이 완료된 사용자를 위한 슈퍼 빠른 실행 가이드**

## 🎯 처음 사용하시나요?

**완전 초기 설정이 필요하다면** → 🏁 **[GETTING_STARTED.md](GETTING_STARTED.md)** 를 먼저 확인하세요!

이 가이드는 **이미 환경 설정이 완료된 사용자**를 위한 빠른 실행 가이드입니다.

---

## ✅ 사전 조건 체크리스트

- [x] 모든 대상 노드에서 Rocky Linux 8 실행 중
- [x] SSH 서비스 활성화 및 root 접근 가능  
- [x] Ansible 설치 완료
- [x] Vault 비밀번호 파일 (.vault-password) 준비됨
- [x] inventory/staging/hosts.yml에 IP 설정 완료

---

## 🚀 원클릭 실행 (3단계)

### 📝 Step 1: IP 설정 확인 (30초)

**`inventory/staging/hosts.yml` 파일의 IP가 정확한지 확인:**

```yaml
k8s-master-01:
  ansible_host: 192.168.1.100  # 👈 실제 마스터 IP
k8s-worker-01:
  ansible_host: 192.168.1.101  # 👈 실제 워커 IP
```

### 🔐 Step 2: 연결 테스트 (30초)

```bash
# 모든 노드 연결 확인
ansible all -i inventory/staging/hosts.yml -m ping --vault-password-file .vault-password
```

### 🎯 Step 3: 실행! (5-15분)

```bash
# 가장 일반적인 사용 (Kubernetes + CircleCI)
./scripts/setup-cluster.sh cluster-circleci \
  -i inventory/staging/hosts.yml \
  --vault-password-file .vault-password
```

---

## 🔧 다른 배포 모드들

### 🎯 Kubernetes만 구축
```bash
./scripts/setup-cluster.sh cluster-only
```

### 🔗 워커 노드 추가
```bash
./scripts/setup-cluster.sh add-node \
  --node-ip 192.168.1.102 \
  --node-name k8s-worker-02
```

### 🏃 CircleCI만 추가
```bash
./scripts/setup-cluster.sh deploy-circleci
```

### 🔗 노드 추가 + CircleCI
```bash
./scripts/setup-cluster.sh add-node-circleci \
  --node-ip 192.168.1.102 \
  --node-name k8s-worker-02
```

---

## ✅ 완료 확인

### 🔍 클러스터 상태
```bash
# 노드 상태 확인
kubectl get nodes

# 모든 Pod 상태 확인  
kubectl get pods -A

# 클러스터 정보
kubectl cluster-info
```

### 🏃 CircleCI Runner (선택사항)
```bash
# Runner Pod 상태
kubectl get pods -n circleci

# Runner 로그 확인
kubectl logs -n circleci -l app.kubernetes.io/name=container-agent
```

---

## 🔄 문제 해결

### SSH 연결 실패 시
```bash
# SSH 키 수동 복사
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@target-node-ip
```

### Ansible 실행 오류 시  
```bash
# 연결 테스트
ansible all -i inventory/staging/hosts.yml -m ping
```

### 클러스터 초기화 필요 시
```bash
# 완전 롤백
./scripts/rollback.sh
```

---

## 🎉 성공!

축하합니다! 이제 다음이 준비되었습니다:

- ✅ **완전한 Kubernetes 클러스터**
- ✅ **CircleCI Self-Hosted Runner** (선택사항)
- ✅ **자동화된 CI/CD 환경**

### 📚 더 자세한 정보

- 📖 **전체 가이드**: [README.md](../README.md)
- 🔐 **보안 설정**: [SECURITY_SETUP.md](SECURITY_SETUP.md)  
- 🏁 **완전 초기 설정**: [GETTING_STARTED.md](GETTING_STARTED.md)

---

**🚀 이제 시작하세요! 5분이면 완성됩니다!** 