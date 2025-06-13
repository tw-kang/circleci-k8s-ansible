# 🔧 워커 노드 설정 완벽 가이드

> Kubernetes 클러스터에 **워커 노드를 추가**하는 모든 방법을 단계별로 안내하는 완벽한 가이드입니다.

## 🎯 워커 노드 추가 개요

이 가이드는 기존 Kubernetes 클러스터에 새로운 워커 노드를 추가하는 **3가지 방법**을 제공합니다:

1. 🚀 **자동 추가**: `setup-cluster.sh` 스크립트 사용 (권장)
2. 🔧 **수동 추가**: Ansible 플레이북 직접 실행
3. 🛠️ **완전 수동**: 명령어로 직접 설정

## 🚀 방법 1: 자동 워커 노드 추가 (권장)

### 📋 사전 준비

#### 새 워커 노드에서 실행
```bash
# 기본 패키지 설치
sudo dnf update -y && sudo dnf install -y epel-release python3 openssh-server

# SSH 서비스 시작
sudo systemctl enable --now sshd

# root 비밀번호 설정 (SSH 키 배포용)
sudo passwd root
```

### 🎯 워커 노드 추가 실행

#### 기본 워커 노드 추가
```bash
# 워커 노드만 추가
./scripts/setup-cluster.sh add-node \
  --node-ip 192.168.1.12 \
  --node-name k8s-worker-02

# 워커 노드 추가 + CircleCI 설정
./scripts/setup-cluster.sh add-node-circleci \
  --node-ip 192.168.1.12 \
  --node-name k8s-worker-02
```

#### 고급 옵션 사용
```bash
# Vault 파일 지정
./scripts/setup-cluster.sh add-node \
  --node-ip 192.168.1.12 \
  --node-name k8s-worker-02 \
  --vault-password ~/.ansible-vault-pass

# Dry run으로 확인
./scripts/setup-cluster.sh add-node \
  --node-ip 192.168.1.12 \
  --node-name k8s-worker-02 \
  --dry-run

# 상세 출력
./scripts/setup-cluster.sh add-node \
  --node-ip 192.168.1.12 \
  --node-name k8s-worker-02 \
  --verbose
```

### ✅ 추가 완료 확인
```bash
# 노드 상태 확인
kubectl get nodes -o wide

# 노드 상세 정보
kubectl describe node k8s-worker-02

# 모든 Pod 상태 확인
kubectl get pods -A -o wide
```

## 🔧 방법 2: 수동 워커 노드 추가

### 1단계: inventory 파일 수정

#### `inventory/hosts.yml` 편집
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
              node_role: master
        k8s_workers:
          hosts:
            k8s-worker-01:
              ansible_host: 192.168.1.11
              ansible_user: root
              node_role: worker
            k8s-worker-02:  # 👈 새 워커 노드 추가
              ansible_host: 192.168.1.12
              ansible_user: root
              node_role: worker
```

### 2단계: SSH 키 배포
```bash
# 새 노드에 SSH 키 복사
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.12

# SSH 연결 테스트
ssh -i ~/.ssh/id_ed25519 root@192.168.1.12 "echo 'SSH 연결 성공!'"
```

### 3단계: Ansible 플레이북 실행
```bash
# 새 워커 노드만 대상으로 실행
ansible-playbook -i inventory/hosts.yml \
  playbooks/add-node.yml \
  --limit k8s-worker-02 \
  --ask-vault-pass

# 또는 Vault 파일 사용
ansible-playbook -i inventory/hosts.yml \
  playbooks/add-node.yml \
  --limit k8s-worker-02 \
  --vault-password-file ~/.ansible-vault-pass
```

## 🛠️ 방법 3: 완전 수동 워커 노드 추가

### 1단계: 기본 시스템 설정

#### 새 워커 노드에서 실행
```bash
# 시스템 업데이트
sudo dnf update -y

# 필수 패키지 설치
sudo dnf install -y epel-release python3 curl wget

# SELinux 설정
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# 방화벽 비활성화 (또는 필요한 포트만 열기)
sudo systemctl disable --now firewalld

# Swap 비활성화
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### 2단계: 커널 모듈 및 시스템 설정

#### 커널 모듈 로드
```bash
# 필요한 커널 모듈 설정
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

#### 시스템 파라미터 설정
```bash
# sysctl 파라미터 설정
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### 3단계: containerd 설치

#### x86_64 시스템용
```bash
# Docker 저장소 추가
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# containerd 설치
sudo dnf install -y containerd.io

# containerd 설정
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# SystemdCgroup 활성화
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# containerd 시작
sudo systemctl enable --now containerd
```

#### ARM64 시스템용
```bash
# containerd 바이너리 다운로드
CONTAINERD_VERSION="1.7.27"
wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz

# 바이너리 설치
sudo tar Cxzvf /usr/local containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz

# systemd 서비스 파일 다운로드
sudo wget -O /etc/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service

# runc 설치
wget https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.arm64
sudo install -m 755 runc.arm64 /usr/local/sbin/runc

# containerd 설정 및 시작
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
```

### 4단계: Kubernetes 패키지 설치

#### Kubernetes 저장소 추가
```bash
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
```

#### Kubernetes 패키지 설치
```bash
# 특정 버전 설치
KUBERNETES_VERSION="1.28.15"
sudo dnf install -y kubelet-${KUBERNETES_VERSION} kubeadm-${KUBERNETES_VERSION} kubectl-${KUBERNETES_VERSION} --disableexcludes=kubernetes

# 패키지 버전 고정
sudo dnf versionlock kubelet kubeadm kubectl

# kubelet 시작
sudo systemctl enable --now kubelet
```

### 5단계: 클러스터 조인

#### 마스터 노드에서 조인 토큰 생성
```bash
# 마스터 노드에서 실행
kubeadm token create --print-join-command
```

#### 워커 노드에서 클러스터 조인
```bash
# 마스터 노드에서 받은 명령어 실행 (예시)
sudo kubeadm join 192.168.1.10:6443 \
  --token abcdef.1234567890abcdef \
  --discovery-token-ca-cert-hash sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
```

### 6단계: 조인 확인

#### 마스터 노드에서 확인
```bash
# 노드 상태 확인
kubectl get nodes

# 노드가 Ready 상태가 될 때까지 대기
kubectl get nodes -w

# 노드 상세 정보 확인
kubectl describe node k8s-worker-02
```

## 🔍 문제 해결

### 일반적인 문제들

#### 1. 노드가 Ready 상태가 되지 않음
```bash
# 워커 노드에서 kubelet 로그 확인
sudo journalctl -u kubelet -f

# 일반적인 해결 방법
sudo systemctl restart kubelet
sudo systemctl restart containerd
```

#### 2. CNI 플러그인 문제
```bash
# 마스터 노드에서 CNI Pod 상태 확인
kubectl get pods -n kube-system | grep -E "(flannel|calico)"

# CNI Pod 재시작
kubectl delete pods -n kube-system -l app=flannel
```

#### 3. 조인 토큰 만료
```bash
# 마스터 노드에서 새 토큰 생성
kubeadm token create --print-join-command --ttl 24h
```

#### 4. 네트워크 연결 문제
```bash
# 워커 노드에서 마스터 노드 연결 테스트
telnet 192.168.1.10 6443

# DNS 해결 확인
nslookup 192.168.1.10
```

### 로그 확인 방법

#### 시스템 로그
```bash
# kubelet 로그
sudo journalctl -u kubelet --since "1 hour ago"

# containerd 로그
sudo journalctl -u containerd --since "1 hour ago"

# 시스템 메시지
sudo tail -f /var/log/messages
```

#### Kubernetes 로그
```bash
# 클러스터 이벤트
kubectl get events --sort-by='.lastTimestamp'

# 특정 노드 이벤트
kubectl get events --field-selector involvedObject.name=k8s-worker-02

# Pod 로그 (CNI 관련)
kubectl logs -n kube-system -l app=flannel
```

## 📊 성능 최적화

### 워커 노드 리소스 설정

#### kubelet 설정 최적화
```bash
# /var/lib/kubelet/config.yaml 편집
sudo cat <<EOF > /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
systemReserved:
  cpu: "200m"
  memory: "512Mi"
  ephemeral-storage: "1Gi"
kubeReserved:
  cpu: "200m"
  memory: "512Mi"
  ephemeral-storage: "1Gi"
evictionHard:
  memory.available: "100Mi"
  nodefs.available: "10%"
  nodefs.inodesFree: "5%"
EOF

sudo systemctl restart kubelet
```

#### 노드 라벨링
```bash
# 워커 노드에 라벨 추가
kubectl label node k8s-worker-02 node-type=worker
kubectl label node k8s-worker-02 workload=general
kubectl label node k8s-worker-02 zone=zone-a

# 라벨 확인
kubectl get nodes --show-labels
```

### 리소스 모니터링

#### 노드 리소스 사용량 확인
```bash
# 노드 리소스 사용량
kubectl top nodes

# Pod 리소스 사용량
kubectl top pods -A

# 노드 상세 리소스 정보
kubectl describe node k8s-worker-02 | grep -A 10 "Allocated resources"
```

## 🔄 워커 노드 제거

### 안전한 노드 제거 절차

#### 1. 노드 드레인
```bash
# 노드에서 Pod 안전하게 제거
kubectl drain k8s-worker-02 --ignore-daemonsets --delete-emptydir-data

# 노드 상태 확인
kubectl get nodes
```

#### 2. 노드 삭제
```bash
# 클러스터에서 노드 제거
kubectl delete node k8s-worker-02
```

#### 3. 워커 노드 정리
```bash
# 워커 노드에서 실행
sudo kubeadm reset --force
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/kubelet/
sudo rm -rf /var/lib/etcd/
sudo rm -rf /etc/cni/net.d/
```

#### 4. inventory 파일 정리
```yaml
# inventory/hosts.yml에서 해당 노드 제거
k8s_workers:
  hosts:
    k8s-worker-01:
      ansible_host: 192.168.1.11
      ansible_user: root
      node_role: worker
    # k8s-worker-02 항목 삭제
```

## 📋 워커 노드 체크리스트

### 추가 전 체크리스트
- [ ] 새 노드에서 기본 패키지 설치 완료
- [ ] SSH 서비스 활성화 및 root 비밀번호 설정
- [ ] 네트워크 연결 확인 (마스터 노드와 통신 가능)
- [ ] 하드웨어 요구사항 충족 (1 CPU, 2GB RAM, 10GB 디스크)
- [ ] inventory/hosts.yml 파일 업데이트

### 추가 후 체크리스트
- [ ] 노드가 Ready 상태인지 확인
- [ ] 모든 시스템 Pod가 정상 실행 중인지 확인
- [ ] CNI 네트워크가 정상 작동하는지 확인
- [ ] 테스트 Pod 배포 및 실행 확인
- [ ] 노드 라벨링 및 리소스 설정 완료

### 정기 점검 체크리스트 (주 1회)
- [ ] 노드 리소스 사용량 모니터링
- [ ] 시스템 업데이트 적용
- [ ] 로그 분석 및 이상 징후 확인
- [ ] 백업 상태 확인
- [ ] 성능 최적화 검토

---

## 🆘 지원 및 문의

### 문제 발생 시 정보 수집
```bash
# 노드 정보 수집 스크립트
cat > collect-node-info.sh << 'EOF'
#!/bin/bash
echo "=== 노드 정보 수집 시작 ==="
echo "날짜: $(date)"
echo "호스트명: $(hostname)"
echo "IP 주소: $(ip addr show | grep 'inet ' | grep -v '127.0.0.1')"
echo ""

echo "=== 시스템 정보 ==="
uname -a
cat /etc/os-release
echo ""

echo "=== 리소스 사용량 ==="
free -h
df -h
echo ""

echo "=== 서비스 상태 ==="
systemctl status kubelet --no-pager
systemctl status containerd --no-pager
echo ""

echo "=== Kubernetes 정보 ==="
kubectl get nodes
kubectl get pods -A
echo ""

echo "=== 로그 (최근 1시간) ==="
journalctl -u kubelet --since "1 hour ago" --no-pager | tail -20
echo "=== 정보 수집 완료 ==="
EOF

chmod +x collect-node-info.sh
./collect-node-info.sh > node-info-$(date +%Y%m%d_%H%M%S).log
```

**🔧 워커 노드 추가는 클러스터 확장의 핵심입니다. 이 가이드를 참조하여 안전하고 효율적으로 노드를 관리하세요!** 