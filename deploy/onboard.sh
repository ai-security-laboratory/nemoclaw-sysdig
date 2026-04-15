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

# ── Ensure OpenShell cluster container is running ─────────────────────────────
# nemoclaw list reads local config and succeeds even when the cluster is down,
# so we must check the container state explicitly before any openshell command.
log "Ensuring OpenShell cluster container is running..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "
  STATUS=\$(docker inspect --format '{{.State.Status}}' openshell-cluster-nemoclaw 2>/dev/null || echo 'missing')
  case \"\$STATUS\" in
    running)
      echo '[cluster] Already running' ;;
    exited|created|paused)
      echo '[cluster] Restarting stopped container...'
      docker start openshell-cluster-nemoclaw ;;
    missing)
      echo '[cluster] Container not found — NemoClaw may not be installed yet' ;;
    *)
      echo '[cluster] Unexpected state: '\$STATUS ;;
  esac
"
# ── Check sandbox state in the cluster (not local nemoclaw metadata) ──────────
# nemoclaw list reads local config and shows stale entries even after deletion.
# Use openshell sandbox list which reflects actual cluster pod state.
log "Checking sandbox '${TARGET_SANDBOX_NAME}' on ${TARGET} (${TARGET_HOST})..."

SANDBOX_IN_CLUSTER=false
if ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"
   openshell sandbox list 2>/dev/null | grep -q '${TARGET_SANDBOX_NAME}'"; then
  SANDBOX_IN_CLUSTER=true
fi

if [[ "${SANDBOX_IN_CLUSTER}" == "true" ]]; then
  # Sandbox exists in cluster — wait for it to be Ready, then verify SSH.
  log "Sandbox '${TARGET_SANDBOX_NAME}' found in cluster — waiting for Ready..."
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    for i in \$(seq 1 20); do
      if openshell sandbox list 2>/dev/null | grep '${TARGET_SANDBOX_NAME}' | grep -q 'Ready'; then
        echo '[sandbox] Ready'
        exit 0
      fi
      echo '[sandbox] Not ready yet, waiting 3s... ('\$i'/20)'
      sleep 3
    done
    echo '[sandbox] WARNING: not Ready after 60s — continuing anyway'
  "

  # After a cluster restart the sandbox pod gets new SSH host keys;
  # openshell's client credentials go stale → "handshake verification failed".
  # Detect and self-heal by deleting + re-onboarding.
  log "Verifying sandbox SSH access..."
  SSH_OK=false
  if ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
    "export PATH=\"\$HOME/.local/bin:\$PATH\"
     ssh -o 'ProxyCommand \$HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}' \
         -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -o ConnectTimeout=10 \
         sandbox@${TARGET_SANDBOX_NAME} echo ok 2>/dev/null" 2>/dev/null; then
    SSH_OK=true
  fi

  if [[ "${SSH_OK}" == "true" ]]; then
    log "Sandbox '${TARGET_SANDBOX_NAME}' is accessible — skipping onboard."
    exit 0
  fi

  log "Sandbox SSH inaccessible (stale certs after cluster restart) — deleting and re-creating..."
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
    "export PATH=\"\$HOME/.local/bin:\$PATH\"
     openshell sandbox delete ${TARGET_SANDBOX_NAME} 2>&1 || true"
fi

log "Sandbox not found in cluster — running 'nemoclaw onboard' non-interactively..."

[[ -n "${NVIDIA_API_KEY:-}" ]] || die "NVIDIA_API_KEY is not set. Add it to .env"

# Retry up to 3 times. The inference verification (step 4/7) can time out on
# a cold 49B model; --resume on subsequent attempts skips already-done steps.
ONBOARD_OK=false
for ATTEMPT in 1 2 3; do
  RESUME_FLAG=""
  [[ "${ATTEMPT}" -gt 1 ]] && RESUME_FLAG="--resume"
  [[ "${ATTEMPT}" -gt 1 ]] && log "Onboard attempt ${ATTEMPT}/3 (--resume)..."
  if ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "bash -s" <<REMOTE
set -euo pipefail
export PATH="\$HOME/.local/bin:\$PATH"
export NVIDIA_API_KEY="${NVIDIA_API_KEY}"
export NEMOCLAW_NON_INTERACTIVE=1
export NEMOCLAW_SANDBOX_NAME="${TARGET_SANDBOX_NAME}"
export NEMOCLAW_PROVIDER="${TARGET_PROVIDER}"
export NEMOCLAW_MODEL="${TARGET_MODEL}"
nemoclaw onboard ${RESUME_FLAG}
REMOTE
  then
    ONBOARD_OK=true
    break
  fi
  [[ "${ATTEMPT}" -lt 3 ]] && log "Attempt ${ATTEMPT} failed — retrying in 5s..." && sleep 5
done

[[ "${ONBOARD_OK}" == "true" ]] || die "nemoclaw onboard failed after 3 attempts"

log "Sandbox '${TARGET_SANDBOX_NAME}' created."

# ── Configure inference API key ───────────────────────────────────────────────
log "Configuring inference API key..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"
   openshell provider update ${TARGET_PROVIDER} --credential NVIDIA_API_KEY=${NVIDIA_API_KEY} 2>/dev/null || true"
