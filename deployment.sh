#!/usr/bin/env bash
# deployment.sh — Full end-to-end deployment.
#
# Usage:
#   ./deployment.sh --scenario 01-it-ops
#   ./deployment.sh --scenario 01-it-ops --target oracle-vm
#
# What this does (all steps are idempotent):
#   1. Installs Node.js 22, Docker, and NemoClaw CLI on the VM
#   2. Creates the NemoClaw sandbox (skipped if already exists)
#   3. Deploys the scenario into the sandbox
#
# After this, run:
#   ./test.sh --scenario <name>        # task mode — agent runs autonomously
#   ./test.sh --scenario <name> --tui  # TUI mode  — interactive OpenClaw terminal

set -euo pipefail

SCENARIO="01-it-ops"
TARGET="oracle-vm"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO="$2"; shift 2 ;;
    --target)   TARGET="$2";   shift 2 ;;
    --help|-h)
      echo "Usage: $0 --scenario <name> [--target <name>]"
      echo ""
      echo "Options:"
      echo "  --scenario   Scenario to deploy (default: 01-it-ops)"
      echo "  --target     Target VM defined in ../targets.yaml (default: oracle-vm)"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/3] Installing NemoClaw on ${TARGET}..."
bash "${REPO_ROOT}/deploy/install-nemoclaw.sh" --target "${TARGET}"

echo ""
echo "==> [2/3] Ensuring sandbox is ready on ${TARGET}..."
bash "${REPO_ROOT}/deploy/onboard.sh" --target "${TARGET}"

echo ""
echo "==> [3/3] Deploying scenario '${SCENARIO}' to ${TARGET}..."
bash "${REPO_ROOT}/deploy/deploy.sh" --scenario "${SCENARIO}" --target "${TARGET}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scenario '${SCENARIO}' deployed on ${TARGET}. To run it:"
echo ""
echo "  ./test.sh --scenario ${SCENARIO}        # task mode"
echo "  ./test.sh --scenario ${SCENARIO} --tui  # TUI mode"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
