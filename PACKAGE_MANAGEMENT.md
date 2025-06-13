# Package Management Structure (개선된 버전)

이 프로젝트는 Ansible 모범 사례를 따라 **중복 없는** 패키지 관리를 구현했습니다.

## 📦 개선된 패키지 관리 구조

### 🎯 **핵심 개념: DRY (Don't Repeat Yourself)**

- **공통 패키지**: `group_vars/all.yml`에서 한 번만 정의
- **추가 패키지**: 각 그룹에서 필요한 것만 추가 정의
- **자동 상속**: Ansible이 자동으로 변수를 병합

### 1. 공통 패키지 (`group_vars/all.yml`)

**모든 노드에 설치되는 기본 패키지들:**

```yaml
packages:
  # 기본 시스템 패키지 (모든 노드)
  base_system:
    - dnf-utils, curl, wget, vim, git, htop 등
  
  # Python 시스템 패키지 (모든 노드)
  python_system:
    - python3-pip, python3-setuptools
  
  # Python 라이브러리 (모든 노드)
  python_libs:
    - kubernetes, PyYAML, jsonpatch
  
  # Kubernetes 기본 패키지 (모든 노드)
  kubernetes_base:
    - kubelet, kubeadm, kubectl (버전 포함)
```

### 2. 그룹별 **추가** 패키지 (중복 없음!)

#### 마스터 노드 (`group_vars/k8s_masters.yml`)
```yaml
packages_additional:  # 기본 패키지에 추가로
  master_tools:
    - jq        # JSON 처리
    - yq        # YAML 처리  
    - tree      # 디렉토리 구조 표시
    - unzip     # 압축 해제
    - wget2     # 향상된 다운로드 도구
  
  kubernetes_tools:
    - kubernetes-cni
```

#### 워커 노드 (`group_vars/k8s_workers.yml`)
```yaml
packages_additional:  # 기본 패키지에 추가로
  worker_tools:
    - stress-ng        # CPU/메모리 부하 테스트
    - iotop           # I/O 모니터링
    - htop            # 프로세스 모니터링 (추가)
    - sysstat         # 시스템 성능 통계
    - perf            # 성능 프로파일링
  
  kubernetes_tools:
    - kubernetes-cni
```

## 🔧 패키지 설치 프로세스

### 설치 순서:
1. **기본 시스템 패키지** (`packages.base_system`) - 모든 노드
2. **Python 시스템 패키지** (`packages.python_system`) - 모든 노드
3. **Python 라이브러리** (`packages.python_libs`) - 모든 노드
4. **Kubernetes 기본 패키지** (`packages.kubernetes_base`) - 모든 노드
5. **마스터 전용 도구** (`packages_additional.master_tools`) - 마스터만
6. **워커 전용 도구** (`packages_additional.worker_tools`) - 워커만
7. **그룹별 Kubernetes 도구** (`packages_additional.kubernetes_tools`) - 해당 그룹

### 태그별 실행:
```bash
# 기본 패키지만 설치
ansible-playbook -i inventory/staging/hosts.yml playbooks/cluster-only.yml --tags "base-packages"

# 마스터 전용 도구만 설치
ansible-playbook -i inventory/staging/hosts.yml playbooks/cluster-only.yml --tags "master-tools"

# 워커 전용 도구만 설치
ansible-playbook -i inventory/staging/hosts.yml playbooks/cluster-only.yml --tags "worker-tools"

# Kubernetes 패키지만 설치
ansible-playbook -i inventory/staging/hosts.yml playbooks/cluster-only.yml --tags "k8s-packages"
```

## ✨ 개선 후 장점

### 1. **❌ 중복 완전 제거**
- **이전**: 같은 패키지가 3곳에 정의 (all.yml, k8s_masters.yml, k8s_workers.yml)
- **현재**: 공통 패키지는 1곳에만 정의 (all.yml)

### 2. **🔧 유지보수성 향상**
- **패키지 추가**: `all.yml`에 한 번만 추가하면 모든 노드에 적용
- **일관성 보장**: 환경별 설정 차이 발생 불가능
- **실수 방지**: 한 곳만 수정하면 됨

### 3. **📋 명확한 역할 분리**
- `all.yml`: 모든 노드 공통
- `k8s_masters.yml`: 마스터 전용 추가 도구
- `k8s_workers.yml`: 워커 전용 추가 도구

### 4. **🎯 Ansible 모범 사례 준수**
- 변수 상속 활용
- DRY 원칙 준수
- 그룹별 변수 올바른 사용

## 🛠️ 패키지 추가/수정 방법

### **모든 노드에 패키지 추가 (권장 방법):**
```bash
# group_vars/all.yml의 packages.base_system에 추가
vim group_vars/all.yml
```

### **마스터 노드에만 패키지 추가:**
```bash
# group_vars/k8s_masters.yml의 packages_additional.master_tools에 추가
vim group_vars/k8s_masters.yml
```

### **워커 노드에만 패키지 추가:**
```bash
# group_vars/k8s_workers.yml의 packages_additional.worker_tools에 추가
vim group_vars/k8s_workers.yml
```

## 📊 변수 상속 구조

```
📁 all.yml (기본 변수)
├── packages.base_system      → 모든 노드
├── packages.python_system   → 모든 노드  
├── packages.python_libs     → 모든 노드
└── packages.kubernetes_base → 모든 노드

📁 k8s_masters.yml (추가 변수)
└── packages_additional.master_tools → 마스터 노드에 추가

📁 k8s_workers.yml (추가 변수) 
└── packages_additional.worker_tools → 워커 노드에 추가
```

## 📋 예시: 새 패키지 추가

### **시나리오**: 모든 노드에 `curl`의 최신 버전인 `curl-minimal` 추가

```bash
# ✅ 올바른 방법 (한 곳에만 수정)
vim group_vars/all.yml

# packages.base_system에 추가:
packages:
  base_system:
    - dnf-utils
    - device-mapper-persistent-data
    - ...
    - curl-minimal  # 새로 추가
```

### **시나리오**: 마스터 노드에만 `kubectl-tree` 플러그인 추가

```bash
# ✅ 올바른 방법
vim group_vars/k8s_masters.yml

# packages_additional.master_tools에 추가:
packages_additional:
  master_tools:
    - jq
    - yq  
    - ...
    - kubectl-tree  # 새로 추가
```

## 🎉 **요약**

이제 **중복 없는, 유지보수하기 쉬운** 패키지 관리 구조를 갖추었습니다:

- ✅ 공통 패키지: 한 곳에서 관리
- ✅ 추가 패키지: 그룹별로 필요한 것만
- ✅ 자동 상속: Ansible이 알아서 병합
- ✅ DRY 원칙: Don't Repeat Yourself
- ✅ 모범 사례: Ansible 표준 구조
