#!/usr/bin/env bash
# install-nemoclaw.sh — Install NemoClaw and its prerequisites on a remote VM.
#
# Usage:
#   ./deploy/install-nemoclaw.sh --target oracle-vm
#
# What this script does on the remote VM:
#   1. Installs Node.js 22 (required by NemoClaw CLI)
#   2. Installs Docker (required by OpenShell sandbox runtime)
#   3. Installs NemoClaw CLI and runs non-interactive onboarding
#      (sandbox is created here using NVIDIA_API_KEY + targets.yaml config)

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

log "Installing NemoClaw prerequisites on ${TARGET} (${TARGET_HOST})"

# ── 1. Node.js 22 ────────────────────────────────────────────────────────────
log "Installing Node.js 22..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "bash -s" <<'REMOTE'
set -euo pipefail
if command -v node &>/dev/null && node --version | grep -q "^v22"; then
  echo "[node] Already installed: $(node --version)"
else
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
  echo "[node] Installed: $(node --version)"
fi
REMOTE

# ── 2. Docker ────────────────────────────────────────────────────────────────
log "Installing Docker..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "bash -s" <<'REMOTE'
set -euo pipefail
if command -v docker &>/dev/null; then
  echo "[docker] Already installed: $(docker --version)"
else
  curl -fsSL https://get.docker.com | sudo bash
  sudo usermod -aG docker "${USER}"
  echo "[docker] Installed: $(docker --version)"
fi
REMOTE

# ── 3. NemoClaw (install + onboard) ──────────────────────────────────────────
log "Installing NemoClaw..."
[[ -n "${NVIDIA_API_KEY:-}" ]] || die "NVIDIA_API_KEY is not set. Add it to .env"

# Note: unquoted heredoc (<<REMOTE) so local variables are expanded and passed
# to the remote shell. Remote-side variables are escaped with \.
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "bash -s" <<REMOTE
set -euo pipefail
export PATH="\$HOME/.local/bin:\$PATH"
export NVIDIA_API_KEY="${NVIDIA_API_KEY}"
export NEMOCLAW_NON_INTERACTIVE=1
export NEMOCLAW_SANDBOX_NAME="${TARGET_SANDBOX_NAME}"
export NEMOCLAW_PROVIDER="${TARGET_PROVIDER}"
export NEMOCLAW_MODEL="${TARGET_MODEL}"

if command -v nemoclaw &>/dev/null; then
  echo "[nemoclaw] Already installed: \$(nemoclaw --version 2>/dev/null || echo 'version unknown')"
else
  curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
  echo "[nemoclaw] Installed"
fi
REMOTE

log "NemoClaw installed on ${TARGET} (${TARGET_HOST})"
