#!/usr/bin/env bash
# deploy.sh — Deploy a scenario into a running NemoClaw sandbox.
#
# Usage:
#   ./deploy/deploy.sh --scenario 01-it-ops --target oracle-vm
#
# What this script does:
#   1. Stages scenario files on the VM host via rsync
#   2. Uploads them into the sandbox using openshell sandbox upload
#   3. Runs setup.sh inside the sandbox via SSH ProxyCommand

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

[[ -n "${SCENARIO}" ]] || die "SCENARIO is required. Use --scenario <name>"
[[ -n "${TARGET}" ]]   || die "TARGET is required.   Use --target <name>"

SCENARIO_DIR="${REPO_ROOT}/scenarios/${SCENARIO}"
[[ -d "${SCENARIO_DIR}" ]] || die "Scenario not found: ${SCENARIO_DIR}"

load_env "${REPO_ROOT}/.env"
read_target "${REPO_ROOT}/../targets.yaml" "${TARGET}"
# Sets: TARGET_HOST, TARGET_USER, TARGET_SSH_KEY, TARGET_SANDBOX_NAME

SSH_OPTS="-i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"
STAGING_DIR="/tmp/nemoclaw-deploy/${SCENARIO}"

log "Deploying scenario '${SCENARIO}' → sandbox '${TARGET_SANDBOX_NAME}' on ${TARGET} (${TARGET_HOST})"

# ── 1. Stage scenario files on the VM host ───────────────────────────────────
log "Staging scenario files on VM..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${STAGING_DIR}"

rsync -az --delete \
  --exclude '.env' \
  -e "ssh ${SSH_OPTS}" \
  "${SCENARIO_DIR}/" \
  "${TARGET_USER}@${TARGET_HOST}:${STAGING_DIR}/"

# ── 2. Upload scenario into sandbox ──────────────────────────────────────────
log "Uploading scenario files into sandbox '${TARGET_SANDBOX_NAME}'..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"
   openshell sandbox upload --no-git-ignore ${TARGET_SANDBOX_NAME} ${STAGING_DIR} /sandbox/${SCENARIO}"

log "  Uploaded → /sandbox/${SCENARIO}"

# ── 3. Run setup.sh inside sandbox ───────────────────────────────────────────
if [[ -f "${SCENARIO_DIR}/setup.sh" ]]; then
  log "Running scenario setup inside sandbox..."
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
    "export PATH=\"\$HOME/.local/bin:\$PATH\"
     ssh -o 'ProxyCommand \$HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}' \
         -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         sandbox@${TARGET_SANDBOX_NAME} \
         'bash /sandbox/${SCENARIO}/setup.sh'"
fi

# ── Ensure gateway is running ─────────────────────────────────────────────────
log "Ensuring OpenClaw gateway is running..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"
   ssh -o 'ProxyCommand \$HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}' \
       -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       sandbox@${TARGET_SANDBOX_NAME} \
       'ss -tlnp | grep -q 18789 && echo \"gateway already running\" || (nohup openclaw gateway > /tmp/gw.log 2>&1 & sleep 3 && echo \"gateway started\")'"

log "Deploy complete: '${SCENARIO}' is ready in sandbox '${TARGET_SANDBOX_NAME}'"
log ""
log "To run it:"
log "  ./test.sh --scenario ${SCENARIO}        # task mode"
log "  ./test.sh --scenario ${SCENARIO} --tui  # TUI mode"
log "  ./test.sh --ui                           # web UI"
