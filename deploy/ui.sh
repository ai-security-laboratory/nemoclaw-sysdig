#!/usr/bin/env bash
# ui.sh — Forward the OpenClaw web UI to your local browser.
#
# Usage:
#   ./deploy/ui.sh --target oracle-vm
#
# Port forwarding chain (single SSH command, two hops):
#   laptop:18789 → VM (ProxyCommand) → sandbox:18789
#
# Press Ctrl+C to close.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="${REPO_ROOT}/deploy/lib"

source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/targets.sh"

TARGET="${TARGET:-}"
LOCAL_PORT=18789

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)  TARGET="$2";      shift 2 ;;
    --port)    LOCAL_PORT="$2";  shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${TARGET}" ]] || die "TARGET is required. Use --target <name>"

load_env "${REPO_ROOT}/.env"
read_target "${REPO_ROOT}/../targets.yaml" "${TARGET}"

SSH_OPTS="-i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"
PROXY_BIN="/home/${TARGET_USER}/.local/bin/openshell"

# ── Retrieve the auth token from inside the sandbox ──────────────────────────
log "Fetching OpenClaw UI token from sandbox..."
TOKEN=$(ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"
   ssh -o 'ProxyCommand \$HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}' \
       -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       sandbox@${TARGET_SANDBOX_NAME} \
       \"python3 -c \\\"import json; c=json.load(open('/sandbox/.openclaw/openclaw.json')); print(c.get('gateway',{}).get('auth',{}).get('token',''))\\\"\"" 2>/dev/null || true)

if [[ -n "${TOKEN}" ]]; then
  LOCAL_URL="http://127.0.0.1:${LOCAL_PORT}/#token=${TOKEN}"
else
  warn "Could not retrieve token — opening UI without token (may show auth error)"
  LOCAL_URL="http://127.0.0.1:${LOCAL_PORT}/"
fi

# ── Start tunnel: laptop:LOCAL_PORT → VM → sandbox:18789 ─────────────────────
log "Opening tunnel to sandbox '${TARGET_SANDBOX_NAME}' on ${TARGET}..."
ssh -L "${LOCAL_PORT}:localhost:18789" -N \
  -o "ProxyCommand ssh -i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no ${TARGET_USER}@${TARGET_HOST} '${PROXY_BIN} ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}'" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  sandbox@"${TARGET_SANDBOX_NAME}" &
TUNNEL_PID=$!

# Wait for tunnel to establish through two hops
sleep 5

# ── Print access info and open browser ───────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OpenClaw UI"
echo ""
echo "  ${LOCAL_URL}"
echo ""
echo "  Tunnel is open — press Ctrl+C to close."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v open &>/dev/null && [[ -n "${TOKEN}" ]]; then
  open "${LOCAL_URL}"
fi

# ── Keep alive until Ctrl+C ───────────────────────────────────────────────────
trap "kill ${TUNNEL_PID} 2>/dev/null; echo ''; log 'Tunnel closed.'" EXIT INT TERM
wait "${TUNNEL_PID}"
