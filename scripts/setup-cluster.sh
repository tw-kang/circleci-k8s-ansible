#!/bin/bash

# Unified Kubernetes Cluster Management Script
# This script provides comprehensive Kubernetes cluster management capabilities
# Updated for Kubernetes v1.28.15 with ARM64 support and containerd v1.7.27

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
MODE=""
INVENTORY="inventory/production/hosts.yml"
VAULT_PASSWORD_FILE=""
DRY_RUN=false
VERBOSE=""
SKIP_SSH_SETUP=false
NEW_NODE_IP=""
NEW_NODE_NAME=""
NODE_TYPE="worker"

# Current supported versions
KUBERNETES_VERSION="1.28.15"
CONTAINERD_VERSION="1.7.27"

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to auto-generate SSH keys
setup_ssh_keys() {
    local ssh_key_path="$HOME/.ssh/id_ed25519"
    local ssh_pub_key_path="$HOME/.ssh/id_ed25519.pub"
    
    print_message $BLUE "🔑 SSH 키 자동 설정 시작..."
    
    # Ensure .ssh directory exists
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Check if SSH keys already exist
    if [[ -f "$ssh_key_path" && -f "$ssh_pub_key_path" ]]; then
        print_message $GREEN "✅ SSH 키가 이미 존재합니다: $ssh_key_path"
        print_message $YELLOW "기존 키를 사용합니다."
    else
        print_message $YELLOW "🔧 SSH 키 쌍을 자동 생성합니다..."
        
        # Generate SSH key pair
        ssh-keygen -t ed25519 -f "$ssh_key_path" -N "" -C "k8s-cluster-$(date +%s)" 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            print_message $GREEN "✅ SSH 키 쌍이 성공적으로 생성되었습니다!"
            print_message $GREEN "   개인 키: $ssh_key_path"
            print_message $GREEN "   공개 키: $ssh_pub_key_path"
        else
            print_message $RED "❌ SSH 키 생성에 실패했습니다."
            return 1
        fi
    fi
    
    # Set correct permissions
    chmod 600 "$ssh_key_path" 2>/dev/null
    chmod 644 "$ssh_pub_key_path" 2>/dev/null
    
    print_message $BLUE "📋 SSH 공개 키 내용:"
    print_message $YELLOW "$(cat "$ssh_pub_key_path")"
    echo
    
    return 0
}

# Function to copy SSH keys to target nodes
copy_ssh_keys() {
    print_message $BLUE "🔐 SSH 키를 대상 노드들에 배포 중..."
    
    # Get SSH password from vault
    local ssh_password=""
    if [[ -f "group_vars/vault.yml" ]]; then
        # Try to extract SSH password from vault file
        if command -v ansible-vault &> /dev/null && [[ -n "$VAULT_PASSWORD_FILE" ]]; then
            ssh_password=$(ansible-vault view group_vars/vault.yml --vault-password-file "$VAULT_PASSWORD_FILE" 2>/dev/null | grep "vault_ssh_password:" | cut -d'"' -f2 2>/dev/null || echo "")
        fi
    fi
    
    # Get list of all nodes from inventory
    local nodes=$(ansible all -i "$INVENTORY" --list-hosts 2>/dev/null | grep -v "hosts" | sed 's/^[[:space:]]*//' || echo "")
    
    if [[ -z "$nodes" ]]; then
        print_message $YELLOW "⚠️ inventory에서 노드를 찾을 수 없습니다."
        return 1
    fi
    
    for node in $nodes; do
        # Get node IP
        local node_ip=$(ansible "$node" -i "$INVENTORY" -m debug -a "var=ansible_host" --one-line 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "")
        
        if [[ -n "$node_ip" ]]; then
            print_message $BLUE "📤 $node ($node_ip)에 SSH 키 복사 중..."
            
            # Try ssh-copy-id with password if available
            if [[ -n "$ssh_password" ]]; then
                print_message $YELLOW "비밀번호를 사용하여 SSH 키 복사 시도..."
                expect -c "
                    spawn ssh-copy-id -i ~/.ssh/id_ed25519.pub root@$node_ip
                    expect {
                        \"password:\" { send \"$ssh_password\r\"; exp_continue }
                        \"(yes/no)?\" { send \"yes\r\"; exp_continue }
                        eof
                    }
                " 2>/dev/null || {
                    print_message $YELLOW "자동 복사 실패. 수동으로 복사하세요:"
                    print_message $YELLOW "ssh-copy-id -i ~/.ssh/id_ed25519.pub root@$node_ip"
                }
            else
                print_message $YELLOW "SSH 비밀번호가 설정되지 않았습니다. 수동으로 복사하세요:"
                print_message $YELLOW "ssh-copy-id -i ~/.ssh/id_ed25519.pub root@$node_ip"
            fi
            
            # Test SSH connection
            if timeout 10 ssh -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node_ip "echo 'SSH connection successful'" >/dev/null 2>&1; then
                print_message $GREEN "✅ $node: SSH 연결 성공"
            else
                print_message $RED "❌ $node: SSH 연결 실패"
            fi
        else
            print_message $YELLOW "⚠️ $node: IP 주소를 찾을 수 없습니다"
        fi
    done
}

# Function to add node to inventory
add_node_to_inventory() {
    local node_name="$1"
    local node_ip="$2"
    local node_type="$3"
    
    print_message $BLUE "📝 inventory에 노드 추가: $node_name ($node_ip)"
    
    # Create backup
    cp "$INVENTORY" "${INVENTORY}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ "$node_type" == "worker" ]]; then
        # Add to workers section
        awk -v node_name="$node_name" -v node_ip="$node_ip" '
        /k8s_workers:/{
            print $0
            getline
            print $0  # print "hosts:"
            print "            " node_name ":"
            print "              ansible_host: " node_ip "  # Added by setup-cluster.sh"
            print "              ansible_user: root"
            print "              node_role: worker"
            next
        }
        {print}' "$INVENTORY" > "${INVENTORY}.tmp" && mv "${INVENTORY}.tmp" "$INVENTORY"
    else
        # Add to masters section
        awk -v node_name="$node_name" -v node_ip="$node_ip" '
        /k8s_masters:/{
            print $0
            getline
            print $0  # print "hosts:"
            print "            " node_name ":"
            print "              ansible_host: " node_ip "  # Added by setup-cluster.sh"
            print "              ansible_user: root"
            print "              node_role: master"
            next
        }
        {print}' "$INVENTORY" > "${INVENTORY}.tmp" && mv "${INVENTORY}.tmp" "$INVENTORY"
    fi
    
    print_message $GREEN "✅ 노드가 inventory에 추가되었습니다"
}

# Function to detect target architecture
detect_target_architecture() {
    if [[ -f "$INVENTORY" ]]; then
        print_message $BLUE "대상 시스템 아키텍처 감지 중..."
        local arch=$(ansible all -i "$INVENTORY" -m setup -a "filter=ansible_architecture" --one-line 2>/dev/null | head -1 | grep -o 'aarch64\|x86_64' || echo "unknown")
        
        case "$arch" in
            "aarch64")
                print_message $GREEN "대상 아키텍처: ARM64 (aarch64)"
                print_message $YELLOW "ARM64 호환성을 위해 Flannel CNI를 사용합니다"
                ;;
            "x86_64")
                print_message $GREEN "대상 아키텍처: x86_64"
                print_message $YELLOW "x86_64 성능을 위해 Calico CNI를 사용합니다"
                ;;
            *)
                print_message $YELLOW "대상 아키텍처를 감지할 수 없거나 혼합 아키텍처입니다"
                print_message $YELLOW "모든 노드가 동일한 아키텍처인지 확인하세요"
                ;;
        esac
    fi
}

# Function to run ansible playbook
run_ansible_playbook() {
    local playbook="$1"
    local tags="$2"
    local limit="$3"
    
    print_message $BLUE "Ansible 플레이북 실행: $playbook"
    
    # Build ansible-playbook command
    local cmd="ansible-playbook -i $INVENTORY playbooks/$playbook"
    
    [[ -n "$tags" ]] && cmd="$cmd --tags $tags"
    [[ -n "$limit" ]] && cmd="$cmd --limit $limit"
    [[ -n "$VAULT_PASSWORD_FILE" ]] && cmd="$cmd --vault-password-file $VAULT_PASSWORD_FILE"
    [[ "$DRY_RUN" == true ]] && cmd="$cmd --check --diff"
    [[ -n "$VERBOSE" ]] && cmd="$cmd $VERBOSE"
    
    print_message $BLUE "실행 명령어: $cmd"
    echo
    
    # Ask for confirmation if not dry run
    if [[ "$DRY_RUN" != true ]]; then
        read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message $YELLOW "작업이 취소되었습니다"
            return 1
        fi
    fi
    
    # Execute the playbook
    if eval "$cmd"; then
        print_message $GREEN "✅ 플레이북 실행이 성공적으로 완료되었습니다!"
        return 0
    else
        print_message $RED "❌ 플레이북 실행이 실패했습니다!"
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
통합 Kubernetes 클러스터 관리 스크립트
Kubernetes v${KUBERNETES_VERSION}, containerd v${CONTAINERD_VERSION}, ARM64/x86_64 지원

사용법: $0 <MODE> [OPTIONS]

모드 (MODE):
    cluster-only        Kubernetes 클러스터만 구성
    add-node           기존 클러스터에 노드 추가
    cluster-circleci   Kubernetes + CircleCI container-agent (Helm)
    add-node-circleci  노드 추가 + CircleCI container-agent (Helm)
    deploy-circleci    기존 클러스터에 CircleCI agent 구성 (Helm)

옵션 (OPTIONS):
    -i, --inventory FILE        inventory 파일 (기본값: inventory/production/hosts.yml)
    -v, --vault-password FILE   vault 비밀번호 파일
    -d, --dry-run              실제 실행 없이 확인만
    -vv, --verbose             상세 출력
    --skip-ssh-setup           SSH 키 설정 건너뛰기
    
    # 노드 추가 모드용 옵션
    --node-ip IP               새 노드 IP 주소 (필수)
    --node-name NAME           새 노드 이름 (필수)
    --node-type TYPE           노드 타입: worker|master (기본값: worker)
    
    -h, --help                 도움말 표시

예제:
    # 1. Kubernetes 클러스터만 구성
    $0 cluster-only

    # 2. 워커 노드 추가
    $0 add-node --node-ip 198.19.249.230 --node-name k8s-worker-01

    # 3. Kubernetes + CircleCI 구성
    $0 cluster-circleci

    # 4. 노드 추가 + CircleCI 설정
    $0 add-node-circleci --node-ip 198.19.249.230 --node-name k8s-worker-01

    # 5. 기존 클러스터에 CircleCI agent만 배포
    $0 deploy-circleci

    # Dry run으로 확인
    $0 cluster-only --dry-run

    # Vault 파일 사용
    $0 cluster-circleci --vault-password ~/.ansible-vault-pass

아키텍처 지원:
    - x86_64: Calico CNI로 완전 지원
    - ARM64: Flannel CNI로 완전 지원
    - 자동 감지 및 아키텍처별 구성

요구사항:
    - Ansible 2.9+
    - 대상 노드: Rocky Linux 8 또는 호환 OS
    - 대상 노드에 SSH 접근 권한
    - 인터넷 연결 (패키지 다운로드용)

EOF
}

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
fi

MODE="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -v|--vault-password)
            VAULT_PASSWORD_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -vv|--verbose)
            VERBOSE="-vv"
            shift
            ;;
        --skip-ssh-setup)
            SKIP_SSH_SETUP=true
            shift
            ;;
        --node-ip)
            NEW_NODE_IP="$2"
            shift 2
            ;;
        --node-name)
            NEW_NODE_NAME="$2"
            shift 2
            ;;
        --node-type)
            NODE_TYPE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_message $RED "알 수 없는 옵션: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate mode
case "$MODE" in
    cluster-only|add-node|cluster-circleci|add-node-circleci|deploy-circleci)
        ;;
    *)
        print_message $RED "잘못된 모드: $MODE"
        show_usage
        exit 1
        ;;
esac

# Validate node addition parameters
if [[ "$MODE" == "add-node" || "$MODE" == "add-node-circleci" ]]; then
    if [[ -z "$NEW_NODE_IP" || -z "$NEW_NODE_NAME" ]]; then
        print_message $RED "노드 추가 모드에서는 --node-ip와 --node-name이 필수입니다"
        exit 1
    fi
fi

# Change to project directory
cd "$PROJECT_DIR"

print_message $BLUE "========================================="
print_message $BLUE "통합 Kubernetes 클러스터 관리"
print_message $BLUE "모드: $MODE"
print_message $BLUE "Kubernetes: v${KUBERNETES_VERSION}"
print_message $BLUE "containerd: v${CONTAINERD_VERSION}"
print_message $BLUE "========================================="

# Check prerequisites
if ! command -v ansible-playbook &> /dev/null; then
    print_message $RED "오류: ansible-playbook이 설치되지 않았습니다"
    print_message $YELLOW "Ansible을 먼저 설치하세요:"
    print_message $YELLOW "  dnf install ansible"
    exit 1
fi

if [[ ! -f "$INVENTORY" ]]; then
    print_message $RED "오류: inventory 파일을 찾을 수 없습니다: $INVENTORY"
    exit 1
fi

# Setup SSH keys automatically (unless skipped)
if [[ "$SKIP_SSH_SETUP" != true ]]; then
    if ! setup_ssh_keys; then
        print_message $RED "SSH 키 설정에 실패했습니다. --skip-ssh-setup 옵션을 사용하여 건너뛸 수 있습니다."
        exit 1
    fi
    
    # Copy SSH keys to target nodes
    copy_ssh_keys
    echo
fi

# Detect target architecture
detect_target_architecture

# Execute based on mode
case "$MODE" in
    cluster-only)
        print_message $GREEN "🚀 Kubernetes 클러스터 구성 시작..."
        if run_ansible_playbook "cluster-only.yml" "common,kubernetes,verification" ""; then
            print_message $GREEN "✅ Kubernetes 클러스터 구성 완료!"
            print_message $BLUE "다음 단계:"
            print_message $BLUE "1. 클러스터 상태 확인: kubectl get nodes"
            print_message $BLUE "2. 모든 파드 확인: kubectl get pods -A"
        fi
        ;;
        
    add-node)
        print_message $GREEN "🔗 클러스터에 노드 추가 시작..."
        
        # Add node to inventory
        add_node_to_inventory "$NEW_NODE_NAME" "$NEW_NODE_IP" "$NODE_TYPE"
        
        # Run playbook for the new node
        if run_ansible_playbook "add-node.yml" "" "$NEW_NODE_NAME"; then
            print_message $GREEN "✅ 노드 추가 완료!"
            print_message $BLUE "클러스터 상태 확인: kubectl get nodes"
        fi
        ;;
        
    cluster-circleci)
        print_message $GREEN "🚀 Kubernetes + CircleCI 구성 시작..."
        if run_ansible_playbook "cluster-circleci.yml" "" ""; then
            print_message $GREEN "✅ Kubernetes + CircleCI 구성 완료!"
            print_message $BLUE "다음 단계:"
            print_message $BLUE "1. 클러스터 상태 확인: kubectl get nodes"
            print_message $BLUE "2. CircleCI 런너 확인: kubectl get pods -n circleci"
            print_message $BLUE "3. CircleCI 프로젝트 설정에서 resource class 구성"
        fi
        ;;
        
    add-node-circleci)
        print_message $GREEN "🔗 노드 추가 + CircleCI 구성 시작..."
        
        # Add node to inventory
        add_node_to_inventory "$NEW_NODE_NAME" "$NEW_NODE_IP" "$NODE_TYPE"
        
        # Run full playbook for the new node
        if run_ansible_playbook "add-node-circleci.yml" "" "$NEW_NODE_NAME"; then
            print_message $GREEN "✅ 노드 추가 + CircleCI 구성 완료!"
            print_message $BLUE "다음 단계:"
            print_message $BLUE "1. 클러스터 상태 확인: kubectl get nodes"
            print_message $BLUE "2. CircleCI 런너 확인: kubectl get pods -n circleci"
        fi
        ;;
        
    deploy-circleci)
        print_message $GREEN "🎯 기존 클러스터에 CircleCI agent 배포 시작..."
        if run_ansible_playbook "deploy-circleci.yml" "circleci,runner" ""; then
            print_message $GREEN "✅ CircleCI agent 배포 완료!"
            print_message $BLUE "다음 단계:"
            print_message $BLUE "1. CircleCI 런너 상태 확인: kubectl get pods -n circleci"
            print_message $BLUE "2. 런너 로그 확인: kubectl logs -n circleci -l app=circleci-runner"
            print_message $BLUE "3. CircleCI 프로젝트에서 resource class 설정"
            print_message $BLUE "4. .circleci/config.yml에서 self-hosted runner 사용"
        fi
        ;;
esac

print_message $GREEN "========================================="
print_message $GREEN "작업 완료!"
print_message $GREEN "완료 시간: $(date)"
print_message $GREEN "=========================================" 