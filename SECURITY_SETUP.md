# 보안 설정 가이드

## 🔐 Ansible Vault 설정

### 1. 필수 단계: Vault 파일 암호화

현재 `group_vars/all/vault.yml` 파일이 평문으로 저장되어 있습니다. 다음 단계를 따라 즉시 암호화하세요.

#### Step 1: 실제 값으로 업데이트

```bash
# vault 파일 편집
ansible-vault edit group_vars/all/vault.yml
```

파일을 열어 다음 값들을 실제 값으로 변경:

```yaml
---
# CircleCI Runner Token (실제 토큰으로 변경)
vault_circleci_token: "your-actual-circleci-token-here"

# SSH Password (실제 비밀번호로 변경)
vault_ssh_password: "your-actual-ssh-password"
```

#### Step 2: 기존 파일 암호화 (이미 평문 파일이 있는 경우)

```bash
# 기존 평문 파일 암호화
ansible-vault encrypt group_vars/all/vault.yml
```

#### Step 3: Vault 비밀번호 파일 생성 (선택사항)

```bash
# vault 비밀번호 파일 생성
echo "your-vault-password" > ~/.ansible-vault-pass
chmod 600 ~/.ansible-vault-pass

# ansible.cfg에 추가
echo "vault_password_file = ~/.ansible-vault-pass" >> ansible.cfg
```

### 2. 사용 방법

#### 암호화된 vault와 함께 플레이북 실행

```bash
# 비밀번호 직접 입력
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-vault-pass

# 비밀번호 파일 사용
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --vault-password-file ~/.ansible-vault-pass
```

#### Vault 파일 편집

```bash
# 암호화된 파일 편집
ansible-vault edit group_vars/all/vault.yml

# 파일 내용 보기 (복호화)
ansible-vault view group_vars/all/vault.yml
```

### 3. SSH 키 설정 확인

SSH 키 인증이 올바르게 설정되었는지 확인:

```bash
# 1. SSH 키가 자동 생성되었는지 확인
ls -la ~/.ssh/id_ed25519*

# 2. SSH 연결 테스트 스크립트 실행
./scripts/test-ssh-connectivity.sh

# 3. SSH 키를 대상 노드에 복사 (필요한 경우)
ssh-copy-id root@198.19.249.65  # 마스터 노드
ssh-copy-id root@198.19.249.230 # 워커 노드

# 4. 수동 SSH 연결 테스트
ssh root@198.19.249.65
```

#### SSH 키 문제해결

SSH 키 인증이 실패하는 경우:

1. **SSH 키 권한 확인**:
   ```bash
   chmod 600 ~/.ssh/id_ed25519
   chmod 644 ~/.ssh/id_ed25519.pub
   ```

2. **대상 노드의 SSH 설정 확인**:
   ```bash
   # 대상 노드에서 실행
   systemctl status sshd
   cat /etc/ssh/sshd_config | grep -E "(PubkeyAuthentication|PasswordAuthentication)"
   ```

3. **SSH Agent 사용** (선택사항):
   ```bash
   eval $(ssh-agent)
   ssh-add ~/.ssh/id_ed25519
   ```

### 4. CircleCI 토큰 획득 방법

1. CircleCI 웹 인터페이스 로그인
2. `Project Settings` > `Self-Hosted Runners` 이동
3. `Create Resource Class` 클릭
4. 생성된 토큰 복사하여 vault 파일에 입력

### 5. 보안 체크리스트

- [ ] vault.yml 파일이 암호화되었는지 확인
- [ ] 실제 CircleCI 토큰으로 업데이트
- [ ] 실제 SSH 비밀번호로 업데이트 (필요한 경우)
- [ ] SSH 키가 올바르게 생성되고 배포되었는지 확인
- [ ] SSH 연결 테스트 통과
- [ ] vault 비밀번호가 안전한 곳에 저장됨
- [ ] .gitignore에 `~/.ansible-vault-pass` 추가됨

### 6. 문제해결

#### 🚫 "CircleCI runner is not enabled" 오류

```bash
# CircleCI 없이 Kubernetes만 설치
ansible-playbook -i inventory/hosts.yml playbooks/k8s-cluster.yml --ask-vault-pass
```

#### 🚫 Vault 비밀번호 분실

암호화된 파일이 있지만 비밀번호를 분실한 경우:

1. `group_vars/all/vault.yml` 백업
2. 새로운 vault 파일 생성
3. 새로운 비밀번호로 암호화

```bash
# 새 vault 파일 생성
cat > group_vars/all/vault.yml << 'EOF'
---
vault_circleci_token: "your-new-token"
vault_ssh_password: "your-ssh-password"
EOF

# 새 비밀번호로 암호화
ansible-vault encrypt group_vars/all/vault.yml
```

---

⚠️ **중요**: 이 설정을 완료하기 전까지는 프로덕션 환경에서 사용하지 마세요! 