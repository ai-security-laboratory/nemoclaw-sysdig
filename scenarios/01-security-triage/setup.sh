#!/usr/bin/env bash
# Remote VM setup for scenario 01-security-triage.
# Runs on the target VM after rsync. Idempotent.

set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCENARIO_DIR}/.venv"

echo "[setup] Installing Python dependencies..."
python3 -m venv "${VENV_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

pip install --quiet --upgrade pip
pip install --quiet -r "${SCENARIO_DIR}/../../requirements.txt"

echo "[setup] Scenario 01-security-triage ready."
echo "[setup] Run with: source .venv/bin/activate && python agent/agent.py --input data/sample_alerts.json"
