# CircleCI self-hosted runner

## Overview

The CircleCI container runner is deployed as a Kubernetes Deployment via the official
`container-agent/container-agent` Helm chart from
`https://packagecloud.io/circleci/container-agent/helm`.

- **Helm release name**: `container-agent`
- **Namespace**: `cubrid` (not `circleci`)
- **Resource class**: `cubrid/ramdisk`
- **Dependencies**: a running K8s cluster (see `docs/installation.md`),
  `vault_circleci_token` encrypted in `vault.yml`, and `/home/build-cache`
  mounted on worker nodes (GlusterFS, set up by `cluster-only.yml`)

---

## Prerequisites

1. K8s cluster provisioned and kubectl accessible via
   `inventory/{env}/artifacts/kubectl.sh` — verified automatically by
   `deploy-circleci.yml` pre-tasks (line 10-19).
2. `vault_circleci_token` present and ansible-vault encrypted in `vault.yml`.
   The playbook asserts this at lines 22-36:

   ```yaml
   # deploy-circleci.yml:22-36
   - name: Validate CircleCI configuration
     assert:
       that:
         - circleci_namespace is defined
         - resource_class is defined
         - token is defined

   - name: Check if CircleCI token is encrypted
     fail:
       msg: "CircleCI token must be encrypted with ansible-vault."
     when:
       - token is defined
       - not token.startswith('$ANSIBLE_VAULT')
       - token != "{{ vault_circleci_token }}"
   ```

3. `/home/build-cache` mounted on all worker nodes.  This is a GlusterFS
   replicated volume set up by `cluster-only.yml` (the `glusterfs` role runs
   on `kube_node` hosts, tag `glusterfs`).

---

## Configuration

Variables live in `inventory/{env}/group_vars/circleci/runner.yml`.

| Variable | Production | Staging |
|---|---|---|
| `circleci_namespace` | `cubrid` | `cubrid` |
| `circleci_config_path` | `/opt/circleci/config` | `/opt/circleci/config/staging` |
| `resource_class` | `ramdisk` | `ramdisk` |
| `replicas` | `1` | `1` |
| `maxConcurrentTasks` | `50` | `50` |
| `image` | `cubridci/cubridci:test_shell` | `cubridci/cubridci:test_shell` |
| `resources.requests.cpu` | `2` | `2` |
| `resources.requests.memory` | `4Gi` | `4Gi` |
| `resources.limits.cpu` | `8` | `8` |
| `resources.limits.memory` | `32Gi` | `16Gi` |
| `token` | `{{ vault_circleci_token }}` | `{{ vault_circleci_token }}` |

---

## Template

`roles/circleci/tasks/main.yml` renders
`roles/circleci/templates/circleci-values.yaml.j2` into the Helm values used at
deploy time. The template includes the GlusterFS build-cache postStart logic
described below.

---

## Pod structure

Each task pod (`cubrid/ramdisk`) runs a single `primary` container with:

- **Security context**: `privileged: true` (required for overlay mounts)
- **Node selector**: `node-role.kubernetes.io/worker: ""`
- **Topology spread**: `maxSkew: 1` across hostnames, `ScheduleAnyway`
- **`shareProcessNamespace: true`**

### Volumes

| Name | Type | Mount path | Notes |
|---|---|---|---|
| `goat-ephemeral` | `emptyDir` | `/runner-init` | Init scratch |
| `repo-ro` | `hostPath` `/home/tc-repo/cubrid-testcases-private-ex` | `/ro` | Read-only testcases |
| `overlay-rw` | `emptyDir` Memory | `/rw` | Testcase overlay upper+work; production sizeLimit 16Gi, staging 8Gi |
| `build-cache` | `hostPath` `/home/build-cache` | `/home/build-cache` | GlusterFS-backed build cache |
| `build-overlay-rw` | `emptyDir` | `/build-rw` | CUBRID overlay upper+work; production no medium, staging Memory 2Gi |
| `podinfo` | `downwardAPI` labels | `/etc/podinfo` | Exposes pod labels for postStart |

### postStart hook logic

The `postStart` exec runs four steps:

1. Mount testcases overlay: `lowerdir=/ro` → `/home/cubrid-testcases-private-ex`
2. Read pod labels from `/etc/podinfo/labels` to extract `CIRCLE_JOB` and `CIRCLE_SHA1`
3. Early exit if job is `download-build` (no CUBRID needed) or CUBRID already exists
   at `/home/CUBRID/bin/cubrid` (legacy workspace method)
4. GlusterFS method: wait for `/home/build-cache/builds/$CIRCLE_SHA1/CUBRID` then
   mount it as an overlay at `/home/CUBRID`

The wait loop at `circleci-values.yaml.j2:117-121`:

```sh
# circleci-values.yaml.j2:117-121
RETRY=0
MAX_WAIT=300
INTERVAL=5
while [ ! -d "$BUILD_DIR/CUBRID" ] && [ $RETRY -lt $((MAX_WAIT / INTERVAL)) ]; do
  [ $((RETRY % 12)) -eq 0 ] && echo "$LOG Waiting for build... ($((RETRY * INTERVAL))s / ${MAX_WAIT}s)"
  sleep $INTERVAL
  RETRY=$((RETRY + 1))
done
```

Maximum wait is 300 seconds (5-second polling interval).  If the build directory
is not found after 300 s the container exits non-zero and the pod fails.

---

## Deployment

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

For staging:

```bash
ansible-playbook \
  -i inventory/staging/hosts.ini \
  playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

The playbook (`deploy-circleci.yml`) flow:

1. **pre_tasks**: verify kubespray artifacts exist, validate CircleCI config
   variables, assert token is vault-encrypted, confirm cluster has at least one
   node.
2. **tasks**: `include_role: circleci` — adds Helm repo, creates namespace if
   absent, writes `values.yaml` from template, runs `helm install/upgrade`
   (`wait: false`).
3. **post_tasks**: query `deployment/container-agent` readyReplicas and print
   summary.

`cluster-only.yml` provisions the K8s cluster (Kubespray) and GlusterFS build
cache but does **not** deploy the CircleCI runner.  There is no
`circleci_enabled` flag in `cluster-only.yml`.

---

## Verification

```bash
# Using kubespray kubectl wrapper
inventory/production/artifacts/kubectl.sh get pods -n cubrid
inventory/production/artifacts/kubectl.sh logs -n cubrid deployment/container-agent

# Or with a standard kubeconfig
kubectl get pods -n cubrid
kubectl describe pod -n cubrid -l app=container-agent
```

Confirm the runner appears as **ONLINE** in the CircleCI web console under
**Self-Hosted Runners → `cubrid/ramdisk`**.

---

## Operations

### Scale replicas

Edit `replicas` in `inventory/{env}/group_vars/circleci/runner.yml` and re-run
the deploy playbook.  The Helm chart reconciles the Deployment.

Immediate scale without Ansible:

```bash
kubectl scale deployment container-agent -n cubrid --replicas=2
```

Note: scaling back down requires a re-deploy to persist the change in
`values.yaml`.

### Restart

```bash
kubectl rollout restart deployment/container-agent -n cubrid
```

### Update token

```bash
ansible-vault edit vault.yml   # update vault_circleci_token
ansible-playbook -i inventory/production/hosts.ini playbooks/deploy-circleci.yml \
  --vault-password-file .vault-password
```

### Update resource class or image

Edit `runner.yml` (`resource_class`, `image`, or `resources.*`) and re-run the
deploy playbook.  There is no in-place patch path; Helm applies the full
`values.yaml` diff.

---

## Troubleshooting

**Pod not starting**

```bash
kubectl describe pod -n cubrid <pod-name>
kubectl get events -n cubrid --sort-by=.lastTimestamp
```

Common causes:
- Token validation failed at deploy time (pre-task assert, `deploy-circleci.yml:22-36`)
- Node selector `node-role.kubernetes.io/worker: ""` does not match any node

**postStart failure (pod stuck in `Init` or `OOMKilled`)**

```bash
kubectl logs -n cubrid <pod-name> --previous
```

Check:
- `/home/build-cache` is mounted on the worker node
- `/home/build-cache/builds/<SHA1>/CUBRID` appears within 300 s of job start
- `overlay-rw` memory emptyDir not exhausted (production 16Gi, staging 8Gi)

**Build cache miss**

```bash
ls /home/build-cache/builds/
```

The `download-build` CircleCI job must complete before test jobs reach
postStart step 4.  If the directory is empty the `download-build` job likely
failed upstream.

**Resource starvation**

```bash
kubectl top nodes
kubectl top pods -n cubrid
```

Worker node must have headroom for requests (2 CPU, 4Gi RAM) per concurrent
task pod.  `maxConcurrentTasks: 50` is a CircleCI-side limit; K8s scheduling
is the actual constraint.

