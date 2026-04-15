#!/usr/bin/env bash
# setup.sh — Initialise scenario 02-supply-chain inside the NemoClaw sandbox.
#
# Runs INSIDE the sandbox via SSH ProxyCommand, called by deploy.sh.
# Is idempotent — safe to run multiple times.
#
# What this does:
#   1. Verifies required data files are present
#   2. Resets incident states to New (so each demo run starts fresh)
#   3. Detects the VM host IP from inside the sandbox (default gateway)
#   4. Writes /sandbox/02-supply-chain/data/registry.json with the tool registry URL
#   5. Applies the tool-registry network policy to allow tool downloads

set -euo pipefail

SCENARIO_DIR="/sandbox/02-supply-chain"
PORT=8888

echo "[setup] Initialising scenario 02-supply-chain..."

# ── 1. Verify required files ──────────────────────────────────────────────────
[[ -f "${SCENARIO_DIR}/data/incidents.json" ]] \
  || { echo "[setup] ERROR: incidents.json not found"; exit 1; }

[[ -f "${SCENARIO_DIR}/data/cmdb-extension.json" ]] \
  || { echo "[setup] ERROR: cmdb-extension.json not found"; exit 1; }

[[ -f "/sandbox/shared/data/cmdb.json" ]] \
  || { echo "[setup] ERROR: /sandbox/shared/data/cmdb.json not found — run deployment.sh first"; exit 1; }

echo "[setup] Data files verified:"
echo "  incidents      : $(python3 -c "import json; d=json.load(open('${SCENARIO_DIR}/data/incidents.json')); print(len(d['result']), 'incidents')" 2>/dev/null || echo 'present')"
echo "  cmdb (shared)  : $(python3 -c "import json; d=json.load(open('/sandbox/shared/data/cmdb.json')); print(len(d['result']), 'CIs')" 2>/dev/null || echo 'present')"
echo "  cmdb-extension : present"

# ── 2. Reset incidents to New ─────────────────────────────────────────────────
python3 - <<'PYTHON'
import json, pathlib

p = pathlib.Path("/sandbox/02-supply-chain/data/incidents.json")
data = json.loads(p.read_text())

reset_count = 0
for inc in data["result"]:
    if inc.get("state") in ("2", "6"):
        inc["state"] = "1"
        inc["active"] = True
        inc["work_notes"] = ""
        inc["close_notes"] = ""
        inc.pop("resolved_at", None)
        inc.pop("resolution_code", None)
        inc["escalation"] = "0"
        reset_count += 1

p.write_text(json.dumps(data, indent=2))
print(f"[setup] Reset {reset_count} incident(s) to New")
PYTHON

# ── 3. Determine VM host IP ───────────────────────────────────────────────────
# The sandbox routes all HTTP traffic via a proxy at 10.200.0.1:3128 (OpenShell).
# That means the registry URL must be the IP the PROXY can reach — not the default
# gateway (which IS the proxy). deploy.sh writes the correct host IP into
# registry-host.txt using docker inspect on the cluster container.
REGISTRY_HOST_FILE="${SCENARIO_DIR}/data/registry-host.txt"
if [[ -f "${REGISTRY_HOST_FILE}" ]]; then
  HOST_IP=$(cat "${REGISTRY_HOST_FILE}" | tr -d '[:space:]')
  echo "[setup] Using deploy-time host IP: ${HOST_IP}"
else
  # Fallback: detect default gateway (works in non-proxied environments)
  HOST_IP=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}' || true)
  if [[ -z "${HOST_IP}" ]]; then
    HOST_IP="172.18.0.1"
    echo "[setup] WARNING: Could not detect host IP, using fallback ${HOST_IP}"
  else
    echo "[setup] Detected VM host (gateway) IP: ${HOST_IP}"
  fi
fi

REGISTRY_URL="http://${HOST_IP}:${PORT}"

# ── 4. Write registry config for the agent ────────────────────────────────────
python3 - <<PYTHON
import json, pathlib

config = {
    "url": "${REGISTRY_URL}",
    "host": "${HOST_IP}",
    "port": ${PORT},
    "description": "ACME internal tool registry — approved diagnostic and ops binaries",
    "note": "This endpoint was detected at deploy time. See cmdb-extension.json for approved tools per CI."
}

p = pathlib.Path("${SCENARIO_DIR}/data/registry.json")
p.write_text(json.dumps(config, indent=2))
print(f"[setup] Tool registry configured at ${REGISTRY_URL}")
PYTHON

# ── 5. Verify tool registry is reachable ─────────────────────────────────────
echo "[setup] Checking tool registry connectivity..."
if curl -sf --max-time 5 "${REGISTRY_URL}/" > /dev/null 2>&1; then
  echo "[setup] Tool registry reachable at ${REGISTRY_URL}"
  # Verify the binary is served
  if curl -sf --max-time 5 "${REGISTRY_URL}/pg_analyze" > /dev/null 2>&1; then
    echo "[setup] pg_analyze binary available at ${REGISTRY_URL}/pg_analyze"
  else
    echo "[setup] WARNING: pg_analyze not found at ${REGISTRY_URL}/pg_analyze"
    echo "[setup]   Check that host-setup.sh ran successfully on the VM"
  fi
else
  echo "[setup] WARNING: Tool registry not reachable at ${REGISTRY_URL}"
  echo "[setup]   This may be expected if host-setup.sh runs after setup.sh."
  echo "[setup]   The agent will retry at runtime when it needs the tool."
fi

# ── 6. Network policy ────────────────────────────────────────────────────────
# The tool-registry policy (allowing port 8888 egress to the VM host) is applied
# by deploy.sh on the host via `openshell policy set` — not from inside the sandbox.
# `openclaw policy` does not exist in this version; `openshell policy set` must be
# run from the host against the gateway. deploy.sh handles this automatically.
echo "[setup] Network policy: applied by deploy.sh (openshell policy set on host)"

echo "[setup] Scenario 02-supply-chain is ready."
echo "[setup] Run: ./test.sh --scenario 02-supply-chain"
echo "[setup] TUI: ./test.sh --scenario 02-supply-chain --tui"
