#!/usr/bin/env bash
# onboard.sh — Ensure the NemoClaw sandbox exists; create it if not.
#
# Usage:
#   ./deploy/onboard.sh --target oracle-vm
#
# This script is idempotent:
#   - If the sandbox already exists, it exits immediately.
#   - If not, it runs `nemoclaw onboard` non-interactively using env vars.
#
# Non-interactive onboard uses:
#   NEMOCLAW_NON_INTERACTIVE=1      skips the interactive wizard
#   NEMOCLAW_SANDBOX_NAME           sandbox name (from targets.yaml: sandbox_name)
#   NEMOCLAW_PROVIDER               inference provider (from targets.yaml: provider)
#   NEMOCLAW_MODEL                  model name       (from targets.yaml: model)
#   NVIDIA_API_KEY                  from .env

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="${REPO_ROOT}/deploy/lib"

source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/targets.sh"

TARGET="${TARGET:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${TARGET}" ]] || die "TARGET is required. Use --target <name>"

load_env "${REPO_ROOT}/.env"
read_target "${REPO_ROOT}/../targets.yaml" "${TARGET}"
# Sets: TARGET_HOST, TARGET_USER, TARGET_SSH_KEY, TARGET_SANDBOX_NAME,
#       TARGET_PROVIDER, TARGET_MODEL

SSH_OPTS="-i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"

log "Checking sandbox '${TARGET_SANDBOX_NAME}' on ${TARGET} (${TARGET_HOST})..."

if ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"; nemoclaw list 2>/dev/null | grep -q '${TARGET_SANDBOX_NAME}'"; then
  log "Sandbox '${TARGET_SANDBOX_NAME}' already exists — skipping onboard."
  exit 0
fi

log "Sandbox not found — running 'nemoclaw onboard' non-interactively..."

[[ -n "${NVIDIA_API_KEY:-}" ]] || die "NVIDIA_API_KEY is not set. Add it to .env"

ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "bash -s" <<REMOTE
set -euo pipefail
export PATH="\$HOME/.local/bin:\$PATH"
export NVIDIA_API_KEY="${NVIDIA_API_KEY}"
export NEMOCLAW_NON_INTERACTIVE=1
export NEMOCLAW_SANDBOX_NAME="${TARGET_SANDBOX_NAME}"
export NEMOCLAW_PROVIDER="${TARGET_PROVIDER}"
export NEMOCLAW_MODEL="${TARGET_MODEL}"
nemoclaw onboard
REMOTE

log "Sandbox '${TARGET_SANDBOX_NAME}' created."

# ── Configure inference API key ───────────────────────────────────────────────
log "Configuring inference API key..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"
   openshell provider update ${TARGET_PROVIDER} --credential NVIDIA_API_KEY=${NVIDIA_API_KEY} 2>/dev/null || true"
