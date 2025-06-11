# 워커 노드 추가 가이드

## 현재 상황
- **마스터 노드**: `198.19.249.181` (설치 완료, 정상 동작)
- **워커 노드**: `198.19.249.230` (추가 예정)
- **클러스터 상태**: Flannel CNI 설치, 1개 마스터 노드 Running

## 워커 노드에서 실행해야 할 작업

### 1. 워커 노드에 로그인
워커 노드 `198.19.249.230`에 직접 접속하세요.

### 2. 워커 노드 준비 스크립트 실행

```bash
# 준비 스크립트를 워커 노드로 복사 (또는 직접 생성)
curl -o prepare-worker-node.sh https://raw.githubusercontent.com/your-repo/circleci-k8s-ansible/main/scripts/prepare-worker-node.sh

# 또는 직접 스크립트 내용을 복사하여 생성
cat > prepare-worker-node.sh << 'EOF'
#!/bin/bash
# [스크립트 내용은 scripts/prepare-worker-node.sh 참조]
EOF

# 실행 권한 부여 및 실행
chmod +x prepare-worker-node.sh
sudo ./prepare-worker-node.sh
```

### 3. SSH 키 교환

워커 노드 준비가 완료되면, **마스터 노드**에서 다음을 실행:

```bash
# 마스터 노드에서 실행
sudo ssh-copy-id root@198.19.249.230
```

### 4. 연결 테스트

```bash
# 마스터 노드에서 워커 노드 연결 테스트
ssh root@198.19.249.230 "hostname && uname -a"
```

### 5. 워커 노드 추가 실행

연결이 확인되면 다음 중 하나를 선택하여 실행:

#### 옵션 A: 자동화 스크립트 사용
```bash
cd circleci-k8s-ansible
./scripts/add-node.sh --node-ip 198.19.249.230 --node-name rocky8-worker
```

#### 옵션 B: Ansible Playbook 직접 실행
```bash
cd circleci-k8s-ansible
ansible-playbook playbooks/k8s-cluster.yml --limit k8s_workers -i inventory/hosts.yml
```

#### 옵션 C: 워커 노드에서 직접 조인
워커 노드에서 다음 명령을 실행:
```bash
# 마스터 노드에서 생성된 join 명령
kubeadm join 198.19.249.181:6443 --token 1oxzfx.sjdmpz02q2v92gu7 --discovery-token-ca-cert-hash sha256:13f8abb68c75d4be5714be1ae050f0665c4b4642d159bcd5b601c946c4c77cc1
```

### 6. 클러스터 상태 확인

```bash
# 마스터 노드에서 확인
kubectl get nodes
kubectl get pods -A
```

---

## 예상 결과

성공적으로 완료되면 다음과 같은 결과를 볼 수 있습니다:

```bash
$ kubectl get nodes
NAME            STATUS   ROLES           AGE   VERSION
rocky8-master   Ready    control-plane   80m   v1.28.15
rocky8-worker   Ready    <none>          5m    v1.28.15
```

## 문제 해결

### SSH 연결 문제
```bash
# 워커 노드에서 SSH 서비스 확인
sudo systemctl status sshd
sudo systemctl enable sshd
sudo systemctl start sshd

# 방화벽 설정
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload
```

### 토큰 만료 문제
토큰은 24시간 후 만료됩니다. 새 토큰 생성:
```bash
# 마스터 노드에서 실행
kubeadm token create --print-join-command
```

### 네트워크 문제
```bash
# 워커 노드에서 마스터 노드 연결 테스트
ping -c 3 198.19.249.181
telnet 198.19.249.181 6443
```

## 현재 생성된 파일들

1. `scripts/prepare-worker-node.sh` - 워커 노드 준비 스크립트
2. `inventory/hosts.yml` - 업데이트된 인벤토리 (실제 IP 반영)
3. `WORKER_NODE_SETUP.md` - 이 가이드 문서

---

**참고**: 워커 노드 추가는 클러스터가 실행 중인 상태에서도 안전하게 수행할 수 있습니다. 