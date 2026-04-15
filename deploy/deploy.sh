#!/usr/bin/env bash
# deploy.sh — Deploy a scenario into a running NemoClaw sandbox.
#
# Usage:
#   ./deploy/deploy.sh --scenario 01-it-ops --target oracle-vm
#
# What this script does:
#   0. Uploads shared/ environment data into the sandbox at /sandbox/shared/
#   1. Stages scenario files on the VM host via rsync
#   2. Uploads them into the sandbox using openshell sandbox upload
#   3. Runs host-setup.sh on the VM (if present — optional scenario VM setup)
#   4. Runs setup.sh inside the sandbox via SSH ProxyCommand

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
SHARED_STAGING="/tmp/nemoclaw-deploy/shared"

log "Deploying scenario '${SCENARIO}' → sandbox '${TARGET_SANDBOX_NAME}' on ${TARGET} (${TARGET_HOST})"

# ── 0. Upload shared environment data into sandbox ───────────────────────────
SHARED_DIR="${REPO_ROOT}/shared"
if [[ -d "${SHARED_DIR}" ]]; then
  log "Staging shared environment data on VM..."
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${SHARED_STAGING}"
  rsync -az --delete \
    -e "ssh ${SSH_OPTS}" \
    "${SHARED_DIR}/" \
    "${TARGET_USER}@${TARGET_HOST}:${SHARED_STAGING}/"
  log "Uploading shared data into sandbox..."
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
    "export PATH=\"\$HOME/.local/bin:\$PATH\"
     openshell sandbox upload --no-git-ignore ${TARGET_SANDBOX_NAME} ${SHARED_STAGING} /sandbox/shared"
  log "  Uploaded → /sandbox/shared"
fi

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

# ── 2.5 Sync model config in sandbox ─────────────────────────────────────────
# openclaw.json is written at onboard time and may have a stale/deprecated model.
# The file is root-owned inside the sandbox k3s pod, so we patch it as root via
# docker exec into the cluster container (no Python there; sed is available).
# Strategy: write the fix script to the VM with TARGET_MODEL already expanded,
# then docker cp it into the container and run it.
log "Syncing model config in sandbox (${TARGET_MODEL})..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "cat > /tmp/sync_model.sh" <<SYNC
#!/bin/sh
CONFIG=\$(find /run/k3s/containerd/io.containerd.runtime.v2.task \
              -name openclaw.json -path '*/sandbox/.openclaw/openclaw.json' \
              2>/dev/null | head -1)
[ -z "\$CONFIG" ] && { echo "[sync] openclaw.json not found in live container — skipping"; exit 0; }
chmod 644 "\$CONFIG"
sed -i \
  's|"id": "[^"]*"|"id": "${TARGET_MODEL}"|g
   s|"name": "inference/[^"]*"|"name": "inference/${TARGET_MODEL}"|g
   s|"primary": "inference/[^"]*"|"primary": "inference/${TARGET_MODEL}"|g
   s|"maxTokens": [0-9]*|"maxTokens": 16384|g
   s|"reasoning": false|"reasoning": true|g' \
  "\$CONFIG"
echo "[sync] Model synced to ${TARGET_MODEL}, maxTokens=16384, reasoning=true in \$CONFIG"
SYNC

ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "sudo docker cp /tmp/sync_model.sh openshell-cluster-nemoclaw:/tmp/sync_model.sh &&
   sudo docker exec openshell-cluster-nemoclaw sh /tmp/sync_model.sh"

# ── 2.6 Write registry-host.txt + apply merged network policy ────────────────
# The sandbox routes HTTP via a proxy at 10.200.0.1:3128. The correct registry
# host is the Docker bridge gateway (VM host as seen from cluster container).
# We determine it via docker inspect and write it for setup.sh to consume.
# We also apply the tool-registry network policy (if policies/ exists in scenario).
POLICY_DIR="${SCENARIO_DIR}/policies"
if [[ -d "${POLICY_DIR}" ]]; then
  log "Writing registry-host config and applying network policy..."

  # Determine VM host IP (Docker bridge gateway for the cluster container)
  TOOL_REGISTRY_HOST=$(ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
    "docker inspect --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' openshell-cluster-nemoclaw 2>/dev/null | head -1" 2>/dev/null || true)
  [[ -z "${TOOL_REGISTRY_HOST}" ]] && TOOL_REGISTRY_HOST="172.18.0.1"
  log "  Tool registry host (proxy-reachable): ${TOOL_REGISTRY_HOST}"

  # Write registry-host.txt into the sandbox data directory via docker exec
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "bash -s" <<REGHOST
set -e
SANDBOX_ROOTFS=\$(sudo docker exec openshell-cluster-nemoclaw \
  find /run/k3s/containerd/io.containerd.runtime.v2.task \
  -name openclaw.json -path '*/sandbox/.openclaw/*' 2>/dev/null \
  | head -1 | sed 's|/.openclaw/openclaw.json||')
if [[ -n "\$SANDBOX_ROOTFS" ]]; then
  DATA_DIR="\${SANDBOX_ROOTFS}/02-supply-chain/data"
  sudo docker exec openshell-cluster-nemoclaw \
    sh -c "mkdir -p '\${DATA_DIR}' && echo '${TOOL_REGISTRY_HOST}' > '\${DATA_DIR}/registry-host.txt'"
  echo "[policy] Wrote ${TOOL_REGISTRY_HOST} to registry-host.txt"
else
  echo "[policy] WARNING: could not find sandbox rootfs to write registry-host.txt"
fi
REGHOST

  # Build merged policy = base filesystem policy + tool_registry with exact IP.
  # The proxy (10.200.0.1:3128) does NOT support CIDR in host fields — exact IPs only.
  # We generate the tool_registry section here with TOOL_REGISTRY_HOST already resolved.
  # The merged YAML includes filesystem_policy so openshell policy set doesn't error.
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "bash -s" <<POLICY
set -e
export PATH="\$HOME/.local/bin:\$PATH"
BASE_IN_CONTAINER=\$(sudo docker exec openshell-cluster-nemoclaw \
  find /run/k3s -name 'openclaw-sandbox.yaml' -path '*/sandbox/.nemoclaw/*' 2>/dev/null | head -1)
if [[ -z "\$BASE_IN_CONTAINER" ]]; then
  echo "[policy] WARNING: base policy not found — skipping policy merge"
  exit 0
fi

# Copy base policy to VM; strip any stale tool_registry section if present
sudo docker exec openshell-cluster-nemoclaw cat "\$BASE_IN_CONTAINER" > /tmp/merged-policy.yaml
python3 -c "
import sys
lines = open('/tmp/merged-policy.yaml').readlines()
out, skip = [], False
for l in lines:
    if l.startswith('  tool_registry:'):
        skip = True
    elif skip and (l.startswith('    ') or l.strip() == ''):
        continue
    else:
        skip = False
        out.append(l)
open('/tmp/merged-policy.yaml','w').writelines(out)
"

# Append tool_registry with the exact proxy-reachable IP (access:full = no TLS enforcement)
cat >> /tmp/merged-policy.yaml << 'TOOLREG'

  tool_registry:
    name: tool_registry
    endpoints:
      - host: "${TOOL_REGISTRY_HOST}"
        port: ${PORT:-8888}
        access: full
    binaries:
      - { path: /usr/bin/curl }
      - { path: /usr/bin/bash }
      - { path: /bin/bash }
      - { path: /bin/sh }
TOOLREG
echo "[policy] tool_registry added for ${TOOL_REGISTRY_HOST}:${PORT:-8888}"

# Also patch the filesystem policy (gateway reads on restart)
sudo docker exec openshell-cluster-nemoclaw sh -c "
python3 -c \"
import sys, pathlib
p = pathlib.Path('\$BASE_IN_CONTAINER')
txt = p.read_text()
if 'tool_registry' not in txt:
    extra = open('/tmp/merged-policy.yaml').read()
    # Just append the tool_registry block
    import re
    m = re.search(r'\\n  tool_registry:.*', extra, re.DOTALL)
    if m:
        p.write_text(txt + m.group())
        print('[policy] Filesystem policy patched')
    else:
        print('[policy] WARNING: tool_registry block not found in merged policy')
else:
    print('[policy] Filesystem policy already has tool_registry')
\" 2>/dev/null || echo '[policy] WARNING: filesystem patch failed (no Python in container)'
" 2>/dev/null || true

# Apply via API
openshell policy set ${TARGET_SANDBOX_NAME} --policy /tmp/merged-policy.yaml --wait && \
  echo "[policy] Policy applied (tool_registry → ${TOOL_REGISTRY_HOST}:${PORT:-8888})" || \
  echo "[policy] WARNING: openshell policy set failed — check /tmp/merged-policy.yaml on VM"
POLICY
fi

# ── 3. Run host-setup.sh on the VM (optional — scenario-specific VM setup) ───
# If a scenario needs to prepare something on the VM host before sandbox setup
# (e.g. start an HTTP server), it provides a host-setup.sh.
# This runs on the VM directly, NOT inside the sandbox.
if [[ -f "${SCENARIO_DIR}/host-setup.sh" ]]; then
  log "Running host setup on VM (host-setup.sh)..."
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
    "export PATH=\"\$HOME/.local/bin:\$PATH\"; bash ${STAGING_DIR}/host-setup.sh"
fi

# ── 4. Run setup.sh inside sandbox ───────────────────────────────────────────
if [[ -f "${SCENARIO_DIR}/setup.sh" ]]; then
  log "Running scenario setup inside sandbox..."
  ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
    "export PATH=\"\$HOME/.local/bin:\$PATH\"
     ssh -o 'ProxyCommand \$HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}' \
         -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         sandbox@${TARGET_SANDBOX_NAME} \
         'bash /sandbox/${SCENARIO}/setup.sh'"
fi

# ── Restart gateway (picks up model config changes) ──────────────────────────
# Always restart — not just start — so a model update in step 2.5 takes effect.
log "Restarting OpenClaw gateway..."
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"
   ssh -o 'ProxyCommand \$HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name ${TARGET_SANDBOX_NAME}' \
       -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       sandbox@${TARGET_SANDBOX_NAME} \
       'pkill -f \"openclaw gateway\" 2>/dev/null || true
        sleep 1
        nohup openclaw gateway > /tmp/gw.log 2>&1 &
        sleep 3
        ss -tlnp | grep -q 18789 && echo \"gateway running\" || echo \"WARNING: gateway not listening on 18789\"'"

log "Deploy complete: '${SCENARIO}' is ready in sandbox '${TARGET_SANDBOX_NAME}'"
log ""
log "To run it:"
log "  ./test.sh --scenario ${SCENARIO}        # task mode"
log "  ./test.sh --scenario ${SCENARIO} --tui  # TUI mode"
log "  ./test.sh --ui                           # web UI"
