#!/usr/bin/env bash
# deploy.sh — Deploy a scenario to a target VM via SSH.
#
# Usage:
#   ./deploy/deploy.sh --scenario 01-security-triage --target my-oracle-vm
#   SCENARIO=01-security-triage TARGET=my-oracle-vm ./deploy/deploy.sh
#
# Reads VM connection details from config/targets.yaml (gitignored).
# Reads secrets from .env (gitignored) — never hardcode them here.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="${REPO_ROOT}/deploy/lib"

source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/targets.sh"

# --- Argument parsing ---
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
[[ -n "${TARGET}" ]]   || die "TARGET is required. Use --target <name>"

SCENARIO_DIR="${REPO_ROOT}/scenarios/${SCENARIO}"
[[ -d "${SCENARIO_DIR}" ]] || die "Scenario not found: ${SCENARIO_DIR}"

# --- Load target config ---
load_env "${REPO_ROOT}/.env"
read_target "${REPO_ROOT}/config/targets.yaml" "${TARGET}"
# Sets: TARGET_HOST, TARGET_USER, TARGET_SSH_KEY, TARGET_REMOTE_BASE

REMOTE_DIR="${TARGET_REMOTE_BASE}/${SCENARIO}"

log "Deploying scenario '${SCENARIO}' to ${TARGET} (${TARGET_HOST})"
log "Remote path: ${REMOTE_DIR}"

SSH_OPTS="-i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"

# --- Ensure remote directory exists ---
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_DIR}"

# --- Sync scenario files (exclude secrets) ---
rsync -avz --delete \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude '.env' \
  --exclude 'output/' \
  -e "ssh ${SSH_OPTS}" \
  "${SCENARIO_DIR}/" \
  "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/"

# --- Upload .env to remote (from local, never stored in repo) ---
if [[ -f "${REPO_ROOT}/.env" ]]; then
  log "Uploading .env to remote (not stored in repo)"
  scp ${SSH_OPTS} "${REPO_ROOT}/.env" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/.env"
else
  warn ".env not found locally — skipping upload. Set credentials manually on the VM."
fi

# --- Run scenario setup on remote ---
if [[ -f "${SCENARIO_DIR}/setup.sh" ]]; then
  log "Running remote setup..."
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
    "cd ${REMOTE_DIR} && bash setup.sh"
fi

log "Deploy complete: ${SCENARIO} → ${TARGET}"
