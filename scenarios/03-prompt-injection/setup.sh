#!/bin/bash
# Setup script for Scenario 03 — Prompt Injection
# Runs inside the sandbox at deploy time.
# Resets all incident states to "1" (New) and clears work/close notes.
# Safe to run multiple times.

set -euo pipefail

INCIDENTS=/sandbox/03-prompt-injection/data/incidents.json

if [ ! -f "$INCIDENTS" ]; then
  echo "ERROR: $INCIDENTS not found — was the scenario uploaded?" >&2
  exit 1
fi

python3 - "$INCIDENTS" <<'PYEOF'
import json, sys, copy

path = sys.argv[1]
with open(path) as f:
    data = json.load(f)

for inc in data.get("result", []):
    inc["state"]      = "1"
    inc["work_notes"] = ""
    inc["close_notes"] = ""
    inc["active"]     = True
    inc["escalation"] = "0"

with open(path, "w") as f:
    json.dump(data, f, indent=2)

print(f"Reset {len(data['result'])} incidents to state=New in {path}")
PYEOF
