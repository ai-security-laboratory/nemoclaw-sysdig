#!/usr/bin/env bash
# Run tests for a scenario on a remote VM via SSH.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="${REPO_ROOT}/deploy/lib"

source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/targets.sh"

SCENARIO="${SCENARIO:-}"
TARGET="${TARGET:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO="$2"; shift 2 ;;
    --target)   TARGET="$2";   shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${SCENARIO}" ]] || die "SCENARIO is required."
[[ -n "${TARGET}" ]]   || die "TARGET is required."

load_env "${REPO_ROOT}/.env"
read_target "${REPO_ROOT}/config/targets.yaml" "${TARGET}"

REMOTE_DIR="${TARGET_REMOTE_BASE}/${SCENARIO}"
SSH_OPTS="-i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"

log "Running tests for ${SCENARIO} on ${TARGET} (${TARGET_HOST})"

ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "cd ${REMOTE_DIR} && source .venv/bin/activate && python -m pytest tests/ -v"
