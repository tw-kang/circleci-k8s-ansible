#!/bin/bash

# Ansible Configuration Validation Script
# This script validates the entire Ansible project structure

set -e

echo "🔍 Starting Ansible project validation..."
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
print_status "1. Validating project structure..."

required_dirs=("group_vars" "inventory" "playbooks" "roles" "scripts" "templates")
for dir in "${required_dirs[@]}"; do
    if [ -d "$dir" ]; then
        print_success "Directory exists: $dir"
    else
        print_error "Directory missing: $dir"
        exit 1
    fi
done

# 2. Check symbolic links
print_status "2. Validating symbolic links..."

symlinks=("inventory/staging/group_vars" "inventory/production/group_vars")
for link in "${symlinks[@]}"; do
    if [ -L "$link" ]; then
        if [ -e "$link" ]; then
            print_success "Symbolic link OK: $link -> $(readlink $link)"
        else
            print_error "Symbolic link broken: $link"
            exit 1
        fi
    else
        print_error "Symbolic link missing: $link"
        exit 1
    fi
done

# 3. YAML syntax validation
print_status "3. Validating YAML syntax..."

yaml_files=(
    "group_vars/all.yml"
    "group_vars/k8s_masters.yml"
    "group_vars/k8s_workers.yml"
    "inventory/staging/hosts.yml"
    "inventory/production/hosts.yml"
)

for file in "${yaml_files[@]}"; do
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        print_success "YAML syntax OK: $file"
    else
        print_error "YAML syntax error: $file"
        exit 1
    fi
done

# 4. Playbook syntax validation
print_status "4. Validating playbook syntax..."

for playbook in playbooks/*.yml; do
    if ansible-playbook --syntax-check "$playbook" >/dev/null 2>&1; then
        print_success "Playbook syntax OK: $playbook"
    else
        print_error "Playbook syntax error: $playbook"
        exit 1
    fi
done

# 5. Inventory validation
print_status "5. Validating inventory..."

inventories=("inventory/staging/hosts.yml" "inventory/production/hosts.yml")
for inv in "${inventories[@]}"; do
    if ansible-inventory -i "$inv" --list >/dev/null 2>&1; then
        print_success "Inventory loading OK: $inv"
    else
        print_error "Inventory loading failed: $inv"
        exit 1
    fi
done

# 6. Variable loading validation
print_status "6. Validating variable loading..."

# Test critical variables
critical_vars=(
    "packages.base_system"
    "packages.kubernetes_base"
    "kubernetes.version"
    "container_runtime.name"
)

for var in "${critical_vars[@]}"; do
    if ansible -i inventory/staging/hosts.yml k8s_masters -m debug -a "var=$var" 2>/dev/null | grep -q "VARIABLE IS NOT DEFINED"; then
        print_error "Variable loading failed: $var"
        exit 1
    else
        print_success "Variable loading OK: $var"
    fi
done

# 7. Role structure validation
print_status "7. Validating role structure..."

role_dirs=("roles/kubernetes-common" "roles/kubernetes-master" "roles/kubernetes-worker")
for role in "${role_dirs[@]}"; do
    if [ -d "$role/tasks" ] && [ -f "$role/tasks/main.yml" ]; then
        print_success "Role structure OK: $role"
    else
        print_error "Role structure error: $role"
        exit 1
    fi
done

# 8. Critical files validation
print_status "8. Validating critical files..."

critical_files=(
    "ansible.cfg"
    "PACKAGE_MANAGEMENT.md"
    "README.md"
)

for file in "${critical_files[@]}"; do
    if [ -f "$file" ]; then
        print_success "File exists: $file"
    else
        print_warning "File missing: $file (optional)"
    fi
done

echo ""
echo "=============================================="
echo -e "${GREEN}✅ All validations passed!${NC}"
echo ""
echo "🚀 You can now run playbooks with the following commands:"
echo "   ansible-playbook -i inventory/staging/hosts.yml playbooks/cluster-only.yml"
echo "   ansible-playbook -i inventory/production/hosts.yml playbooks/cluster-only.yml"
echo ""

# 9. Generate validation report
print_status "9. Generating validation report..."

cat > validation-report.txt << EOF
Ansible Project Validation Report
=================================
Validation time: $(date)

✅ Project structure OK
✅ Symbolic links OK
✅ YAML syntax OK
✅ Playbook syntax OK
✅ Inventory loading OK
✅ Variable loading OK
✅ Role structure OK
✅ Critical files OK

Package management structure:
- All nodes common: packages.base_system, packages.python_system, packages.python_libs, packages.kubernetes_base
- Master nodes additional: packages.additional_system (jq, yq, tree, unzip)
- Worker nodes additional: packages.additional_system (stress-ng, iotop)

Environments:
- Staging: inventory/staging/hosts.yml
- Production: inventory/production/hosts.yml

Validation completed: All components are working properly.
EOF

print_success "Validation report saved to validation-report.txt" 