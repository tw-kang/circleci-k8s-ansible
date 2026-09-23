#!/bin/bash

set -uo pipefail

POLICY_FILE=/opt/job-hook/policy
MARK='[job-hook]'

log() { echo "$MARK $*"; }

log '=============================================='
log "시작 $(date -u +%FT%TZ)  pid=$$  uid=$(id -u)"

log "이벤트     : ${GITHUB_EVENT_NAME:-(없음)}"
log "저장소     : ${GITHUB_REPOSITORY:-(없음)}"
log "actor      : ${GITHUB_ACTOR:-(없음)}"
log "ref        : ${GITHUB_REF:-(없음)}"
log "워크플로   : ${GITHUB_WORKFLOW:-(없음)}"
log "workflowRef: ${GITHUB_WORKFLOW_REF:-(없음)}"
log "job        : ${GITHUB_JOB:-(없음)}"
log "run        : ${GITHUB_RUN_ID:-(없음)} 시도 ${GITHUB_RUN_ATTEMPT:-(없음)}"
log "러너       : ${RUNNER_NAME:-(없음)}"
log "hostname   : $(hostname)"

if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ]; then
  log "payload    : $GITHUB_EVENT_PATH ($(wc -c < "$GITHUB_EVENT_PATH") 바이트)"
else
  log "payload    : (없음)"
fi

MODE=observe
ALLOWED_EVENTS='workflow_dispatch repository_dispatch'

if [ -f "$POLICY_FILE" ]; then
  # shellcheck disable=SC1090
  . "$POLICY_FILE"
  log "정책 파일  : $POLICY_FILE"
else
  log "정책 파일  : 없다 — 내장 기본값을 쓴다"
fi
log "모드       : $MODE"
log "허용 이벤트: $ALLOWED_EVENTS"

case "$MODE" in
  observe)
    if [[ " $ALLOWED_EVENTS " == *" ${GITHUB_EVENT_NAME:-} "* ]]; then
      log '판정       : 통과 (observe — 어차피 허용)'
    else
      log "판정       : ⚠ enforce 였다면 거부했다 — 이벤트 '${GITHUB_EVENT_NAME:-(없음)}'"
    fi
    log '=============================================='
    exit 0
    ;;

  deny-all)
    log '판정       : 거부 (deny-all — 메커니즘 시험)'
    log '=============================================='
    exit 1
    ;;

  enforce)
    if [ -z "${GITHUB_EVENT_NAME:-}" ]; then
      log '판정       : 거부 — 이벤트 이름을 볼 수 없다'
      log '=============================================='
      exit 1
    fi
    if [[ " $ALLOWED_EVENTS " == *" $GITHUB_EVENT_NAME "* ]]; then
      log '판정       : 통과'
      log '=============================================='
      exit 0
    fi
    log "판정       : 거부 — '$GITHUB_EVENT_NAME' 는 허용 목록에 없다"
    log '=============================================='
    exit 1
    ;;

  *)
    log "판정       : 거부 — 모드 '$MODE' 를 모른다"
    log '=============================================='
    exit 1
    ;;
esac
