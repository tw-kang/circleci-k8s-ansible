#!/usr/bin/env bash
set -euo pipefail

out=$(realpath -m "${1:?usage: $0 <out-dir>}")
repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'sudo rm -rf "$work"' EXIT

# Only what git would commit: an ignored plaintext vault must not reach a golden.
git -C "$repo" ls-files -z -co --exclude-standard \
  | tar -C "$repo" --null --no-recursion -T - -cf - \
  | tar -C "$work" -xf -
cp "$repo/tests/golden/vault-dummy.yml" "$work/inventory/production/group_vars/all/vault.yml"
# ansible.cfg fails if its library dir is missing.
sed -i '/^vault_password_file/d' "$work/ansible.cfg"
mkdir -p "$work/3rdparty/kubespray/library" "$work/3rdparty/kubespray/roles"

unset ANSIBLE_VAULT_PASSWORD_FILE ANSIBLE_VAULT_IDENTITY_LIST
export ANSIBLE_CONFIG="$work/ansible.cfg" ANSIBLE_LOG_PATH="$work/ansible.log"
render=$work/render
mkdir -p "$render/monitoring"
play() {
  (cd "$work" && ansible-playbook "$@" \
    -e ansible_connection=local \
    -e '{"ansible_python_interpreter": "{{ ansible_playbook_python }}"}')
}

play playbooks/deploy-arc.yml --tags arc_render -e "arc_config_path=$render/arc"
play playbooks/deploy-circleci.yml --tags circleci_render -e "circleci_config_path=$render/circleci"
play -i inventory/production/hosts.ini -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring.yml --tags monitoring_render -e "monitoring_render_path=$render/monitoring"

for role in arc monitoring circleci; do
  rm -rf "${out:?}/$role"
  mkdir -p "$out/$role"
  cp -r "$render/$role/." "$out/$role/"
done
