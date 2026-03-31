#!/usr/bin/env bash
# teardown.sh — Remove scenario data from the NemoClaw sandbox and staging area.
#
# This does NOT destroy the sandbox itself (use `nemoclaw <name> destroy` for that).
# It removes the scenario files injected by deploy.sh so you can redeploy cleanly.
#
# Usage:
#   ./deploy/teardown.sh --scenario 01-it-ops --target oracle-vm

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="${REPO_ROOT}/deploy/lib"

source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/targets.sh"

SCENARIO="${SCENARIO:-}"
TARGET="${TARGET:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO="$2"; shift 2 ;;
    --target)   TARGET="$2";   shift 2 ;;
    --help|-h)  usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${SCENARIO}" ]] || die "SCENARIO is required."
[[ -n "${TARGET}" ]]   || die "TARGET is required."

load_env "${REPO_ROOT}/.env"
read_target "${REPO_ROOT}/../targets.yaml" "${TARGET}"

SSH_OPTS="-i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"
STAGING_DIR="/tmp/nemoclaw-deploy/${SCENARIO}"

warn "This will remove /sandbox/${SCENARIO} from sandbox '${TARGET_SANDBOX_NAME}' on ${TARGET} (${TARGET_HOST})."
warn "Press Ctrl+C to cancel."
sleep 3

# Remove scenario files from inside the sandbox via SSH ProxyCommand
log "Removing /sandbox/${SCENARIO} from sandbox '${TARGET_SANDBOX_NAME}'..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"
   ssh -o 'ProxyCommand \$HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}' \
       -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       sandbox@${TARGET_SANDBOX_NAME} \
       'rm -rf /sandbox/${SCENARIO}'" 2>/dev/null || warn "Could not remove from sandbox (may already be clean)"

log "Removed /sandbox/${SCENARIO} from sandbox"

# Remove staging dir on VM host
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "rm -rf ${STAGING_DIR}" 2>/dev/null || true
log "Removed staging dir ${STAGING_DIR} on VM host"

log "Teardown complete: '${SCENARIO}' removed from '${TARGET_SANDBOX_NAME}'"
log "To destroy the sandbox entirely: ssh into the VM and run: nemoclaw ${TARGET_SANDBOX_NAME} destroy"
