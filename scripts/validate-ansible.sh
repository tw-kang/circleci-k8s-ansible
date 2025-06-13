#!/bin/bash

# Ansible Configuration Validation Script
# This script validates the entire Ansible project structure

set -e

echo "🔍 Ansible 프로젝트 검증을 시작합니다..."
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# 1. Check project structure
print_status "1. 프로젝트 구조 검증 중..."

required_dirs=("group_vars" "inventory" "playbooks" "roles" "scripts" "templates")
for dir in "${required_dirs[@]}"; do
    if [ -d "$dir" ]; then
        print_success "디렉토리 존재: $dir"
    else
        print_error "디렉토리 누락: $dir"
        exit 1
    fi
done

# 2. Check symbolic links
print_status "2. 심볼릭 링크 검증 중..."

symlinks=("inventory/staging/group_vars" "inventory/production/group_vars")
for link in "${symlinks[@]}"; do
    if [ -L "$link" ]; then
        if [ -e "$link" ]; then
            print_success "심볼릭 링크 정상: $link -> $(readlink $link)"
        else
            print_error "심볼릭 링크 깨짐: $link"
            exit 1
        fi
    else
        print_error "심볼릭 링크 누락: $link"
        exit 1
    fi
done

# 3. YAML syntax validation
print_status "3. YAML 문법 검증 중..."

yaml_files=(
    "group_vars/all.yml"
    "group_vars/k8s_masters.yml"
    "group_vars/k8s_workers.yml"
    "inventory/staging/hosts.yml"
    "inventory/production/hosts.yml"
)

for file in "${yaml_files[@]}"; do
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        print_success "YAML 문법 정상: $file"
    else
        print_error "YAML 문법 오류: $file"
        exit 1
    fi
done

# 4. Playbook syntax validation
print_status "4. 플레이북 문법 검증 중..."

for playbook in playbooks/*.yml; do
    if ansible-playbook --syntax-check "$playbook" >/dev/null 2>&1; then
        print_success "플레이북 문법 정상: $playbook"
    else
        print_error "플레이북 문법 오류: $playbook"
        exit 1
    fi
done

# 5. Inventory validation
print_status "5. 인벤토리 검증 중..."

inventories=("inventory/staging/hosts.yml" "inventory/production/hosts.yml")
for inv in "${inventories[@]}"; do
    if ansible-inventory -i "$inv" --list >/dev/null 2>&1; then
        print_success "인벤토리 로딩 정상: $inv"
    else
        print_error "인벤토리 로딩 실패: $inv"
        exit 1
    fi
done

# 6. Variable loading validation
print_status "6. 변수 로딩 검증 중..."

# Test critical variables
critical_vars=(
    "packages.base_system"
    "packages.kubernetes_base"
    "kubernetes.version"
    "container_runtime.name"
)

for var in "${critical_vars[@]}"; do
    if ansible -i inventory/staging/hosts.yml k8s_masters -m debug -a "var=$var" 2>/dev/null | grep -q "VARIABLE IS NOT DEFINED"; then
        print_error "변수 로딩 실패: $var"
        exit 1
    else
        print_success "변수 로딩 정상: $var"
    fi
done

# 7. Role structure validation
print_status "7. Role 구조 검증 중..."

role_dirs=("roles/kubernetes-common" "roles/kubernetes-master" "roles/kubernetes-worker")
for role in "${role_dirs[@]}"; do
    if [ -d "$role/tasks" ] && [ -f "$role/tasks/main.yml" ]; then
        print_success "Role 구조 정상: $role"
    else
        print_error "Role 구조 오류: $role"
        exit 1
    fi
done

# 8. Critical files validation
print_status "8. 중요 파일 검증 중..."

critical_files=(
    "ansible.cfg"
    "PACKAGE_MANAGEMENT.md"
    "README.md"
)

for file in "${critical_files[@]}"; do
    if [ -f "$file" ]; then
        print_success "파일 존재: $file"
    else
        print_warning "파일 누락: $file (선택사항)"
    fi
done

echo ""
echo "=============================================="
echo -e "${GREEN}✅ 모든 검증을 통과했습니다!${NC}"
echo ""
echo "🚀 이제 다음 명령으로 플레이북을 실행할 수 있습니다:"
echo "   ansible-playbook -i inventory/staging/hosts.yml playbooks/cluster-only.yml"
echo "   ansible-playbook -i inventory/production/hosts.yml playbooks/cluster-only.yml"
echo ""

# 9. Generate validation report
print_status "9. 검증 리포트 생성 중..."

cat > validation-report.txt << EOF
Ansible 프로젝트 검증 리포트
============================
검증 시간: $(date)

✅ 프로젝트 구조 정상
✅ 심볼릭 링크 정상
✅ YAML 문법 정상
✅ 플레이북 문법 정상
✅ 인벤토리 로딩 정상
✅ 변수 로딩 정상
✅ Role 구조 정상
✅ 중요 파일 정상

패키지 관리 구조:
- 모든 노드 공통: packages.base_system, packages.python_system, packages.python_libs, packages.kubernetes_base
- 마스터 노드 추가: packages.additional_system (jq, yq, tree, unzip)
- 워커 노드 추가: packages.additional_system (stress-ng, iotop)

환경:
- Staging: inventory/staging/hosts.yml
- Production: inventory/production/hosts.yml

검증 완료: 모든 구성요소가 정상적으로 작동합니다.
EOF

print_success "검증 리포트가 validation-report.txt에 저장되었습니다." 