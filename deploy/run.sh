#!/usr/bin/env bash
# run.sh — Send a task to the OpenClaw agent running inside the NemoClaw sandbox.
#
# Usage:
#   ./deploy/run.sh --scenario 01-it-ops --target oracle-vm          # task mode
#   ./deploy/run.sh --scenario 01-it-ops --target oracle-vm --tui    # TUI mode

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="${REPO_ROOT}/deploy/lib"

source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/targets.sh"

SCENARIO="${SCENARIO:-}"
TARGET="${TARGET:-}"
TUI_MODE="${TUI_MODE:-false}"
SESSION_ID="${SESSION_ID:-nemoclaw-$(date +%s)}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)   SCENARIO="$2";    shift 2 ;;
    --target)     TARGET="$2";      shift 2 ;;
    --tui)        TUI_MODE="true";  shift 1 ;;
    --session-id) SESSION_ID="$2";  shift 2 ;;
    --help|-h)    usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${SCENARIO}" ]] || die "SCENARIO is required. Use --scenario <name>"
[[ -n "${TARGET}" ]]   || die "TARGET is required.   Use --target <name>"

SCENARIO_DIR="${REPO_ROOT}/scenarios/${SCENARIO}"
[[ -f "${SCENARIO_DIR}/prompt.md" ]] || die "prompt.md not found: ${SCENARIO_DIR}/prompt.md"

load_env "${REPO_ROOT}/.env"
read_target "${REPO_ROOT}/../targets.yaml" "${TARGET}"

SSH_OPTS="-i ${TARGET_SSH_KEY} -o StrictHostKeyChecking=no"
PROXY_BIN="/home/${TARGET_USER}/.local/bin/openshell"
SANDBOX_SSH="ssh -o 'ProxyCommand ${PROXY_BIN} ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null sandbox@${TARGET_SANDBOX_NAME}"

# ── TUI mode ─────────────────────────────────────────────────────────────────
if [[ "${TUI_MODE}" == "true" ]]; then
  log "Opening OpenClaw TUI in sandbox '${TARGET_SANDBOX_NAME}' on ${TARGET} (${TARGET_HOST})"
  log "Press Ctrl+C to return to your laptop."
  log ""
  SANDBOX_PROMPT_PATH="/sandbox/${SCENARIO}/prompt.md"
  ssh -t ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
    "export PATH=\"\$HOME/.local/bin:\$PATH\"
     ssh -t \
         -o 'ProxyCommand \$HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}' \
         -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         sandbox@${TARGET_SANDBOX_NAME} \
         'rm -f ~/.openclaw/agents/main/sessions/*.jsonl ~/.openclaw/agents/main/sessions/sessions.json
          MSG=\$(cat ${SANDBOX_PROMPT_PATH})
          openclaw agent --agent main --session-id main -m \"\$MSG\" > /tmp/openclaw-tui-run.log 2>&1 &
          sleep 1
          openclaw tui'"
  exit 0
fi

# ── Task mode ─────────────────────────────────────────────────────────────────
# The prompt is already in the sandbox at /sandbox/<scenario>/prompt.md (put
# there by deploy.sh). We read it inside the sandbox to avoid quoting issues
# with multi-line strings across SSH hops.

SANDBOX_PROMPT_PATH="/sandbox/${SCENARIO}/prompt.md"

log "Sending scenario '${SCENARIO}' to agent in sandbox '${TARGET_SANDBOX_NAME}'"
log "  host:      ${TARGET_HOST}"
log "  session:   ${SESSION_ID}"
log ""
log "  Tailing gateway log (live)... Ctrl+C to stop."
log "  ─────────────────────────────────────────────"

# Task mode: no -t flag (PTY breaks heredoc piping to inner sandbox SSH)
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"
   ${SANDBOX_SSH} bash << 'SANDBOX'
# Clear session history so the agent starts fresh (avoids context bloat from prior runs)
rm -f ~/.openclaw/agents/main/sessions/*.jsonl ~/.openclaw/agents/main/sessions/sessions.json 2>/dev/null || true

# Tail gateway log in background so we see live progress (only new lines)
tail -n 0 -f /tmp/openclaw/\$(ls -t /tmp/openclaw/ 2>/dev/null | head -1) 2>/dev/null &
TAIL_PID=\$!

# Run agent — gateway connects to inference.local via OpenShell NIM proxy
MSG=\$(cat ${SANDBOX_PROMPT_PATH})
RESULT=\$(openclaw agent --agent main --session-id '${SESSION_ID}' --json -m \"\$MSG\" 2>&1)

kill \$TAIL_PID 2>/dev/null

# Parse JSON response; fall back to raw output if not JSON
echo \"\$RESULT\" | python3 -c \"
import sys, json
raw = sys.stdin.read()
try:
    d = json.loads(raw)
    payloads = d.get('result', {}).get('payloads', [])
    if payloads:
        for p in payloads:
            print(p.get('text', ''))
    else:
        print(raw)
except Exception:
    print(raw)
\"
SANDBOX"
