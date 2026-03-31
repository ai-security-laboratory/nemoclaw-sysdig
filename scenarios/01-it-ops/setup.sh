#!/usr/bin/env bash
# setup.sh — Initialise scenario 01-it-ops inside the NemoClaw sandbox.
#
# This script runs INSIDE the sandbox container (via docker exec),
# called automatically by deploy.sh after data files are injected.
# It is idempotent — safe to run multiple times.

set -euo pipefail

SCENARIO_DIR="/sandbox/01-it-ops"

echo "[setup] Initialising scenario 01-it-ops..."

# ── Ensure data directory and files are present ───────────────────────────────
[[ -f "${SCENARIO_DIR}/data/incidents.json" ]] \
  || { echo "[setup] ERROR: incidents.json not found at ${SCENARIO_DIR}/data/"; exit 1; }

[[ -f "${SCENARIO_DIR}/data/cmdb.json" ]] \
  || { echo "[setup] ERROR: cmdb.json not found at ${SCENARIO_DIR}/data/"; exit 1; }

echo "[setup] Data files verified:"
echo "  incidents : $(python3 -c "import json; d=json.load(open('${SCENARIO_DIR}/data/incidents.json')); print(len(d['result']), 'incidents')" 2>/dev/null || echo 'present')"
echo "  cmdb      : $(python3 -c "import json; d=json.load(open('${SCENARIO_DIR}/data/cmdb.json')); print(len(d['result']), 'CIs')" 2>/dev/null || echo 'present')"

# ── Reset incident states to New so each demo run starts fresh ───────────────
python3 - <<'PYTHON'
import json, pathlib

incidents_path = pathlib.Path("/sandbox/01-it-ops/data/incidents.json")
data = json.loads(incidents_path.read_text())

reset_count = 0
for inc in data["result"]:
    if inc.get("state") in ("2", "6"):          # In Progress or Closed
        inc["state"] = "1"                       # Reset to New
        inc["active"] = True
        inc["work_notes"] = ""
        inc["close_notes"] = ""
        inc.pop("resolved_at", None)
        inc.pop("resolution_code", None)
        inc["escalation"] = "0"
        reset_count += 1

incidents_path.write_text(json.dumps(data, indent=2))
print(f"[setup] Reset {reset_count} incident(s) to New")
PYTHON

echo "[setup] Scenario 01-it-ops is ready."
echo "[setup] To start: make run SCENARIO=01-it-ops TARGET=<target>"
echo "[setup] For TUI:  make tui SCENARIO=01-it-ops TARGET=<target>"
