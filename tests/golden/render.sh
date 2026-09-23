#!/usr/bin/env bash
# Render what the arc, monitoring and circleci deploys hand to helm and k8s,
# offline, into <out>/{arc,monitoring,circleci}. No host, no cluster, no vault.
#
#   tests/golden/render.sh "$RUNNER_TEMP/golden"   # the PR gate compares this
#   tests/golden/render.sh tests/golden            # refresh the goldens
#
# Needs passwordless sudo: the plays run with become.
set -euo pipefail

out=$(realpath -m "${1:?usage: $0 <out-dir>}")
repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'sudo rm -rf "$work"' EXIT

# A copy, so the real vault in the working tree is never read or replaced.
# Only what git would commit: an ignored plaintext vault or credentials dir
# in the working tree must not reach the render.
git -C "$repo" ls-files -z -co --exclude-standard \
  | tar -C "$repo" --null --no-recursion -T - -cf - \
  | tar -C "$work" -xf -
cp "$repo/tests/golden/vault-dummy.yml" "$work/inventory/production/group_vars/all/vault.yml"
# ansible.cfg names a vault password file the copy does not have, and a
# kubespray library dir that must exist even though nothing here uses it.
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
# Both inventories: the scrape targets come from external-nodes.ini.
play -i inventory/production/hosts.ini -i inventory/production/external-nodes.ini \
  playbooks/deploy-monitoring.yml --tags monitoring_render -e "monitoring_render_path=$render/monitoring"

for role in arc monitoring circleci; do
  rm -rf "${out:?}/$role"
  mkdir -p "$out/$role"
  cp -r "$render/$role/." "$out/$role/"
done
