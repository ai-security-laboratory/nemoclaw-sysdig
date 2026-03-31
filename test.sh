#!/usr/bin/env bash
# test.sh — Run a scenario on the NemoClaw sandbox.
#
# Usage:
#   ./test.sh --scenario 01-it-ops
#   ./test.sh --scenario 01-it-ops --target oracle-vm
#   ./test.sh --scenario 01-it-ops --tui
#
# Modes:
#   (default)   Task mode — agent runs autonomously, output streams to terminal
#   --tui       TUI mode  — opens the interactive OpenClaw terminal (recommended for demos)

set -euo pipefail

SCENARIO="01-it-ops"
TARGET="oracle-vm"
TUI=""
UI_MODE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO="$2";    shift 2 ;;
    --target)   TARGET="$2";      shift 2 ;;
    --tui)      TUI="--tui";      shift 1 ;;
    --ui)       UI_MODE="true";   shift 1 ;;
    --help|-h)
      echo "Usage: $0 --scenario <name> [--target <name>] [--tui] [--ui]"
      echo ""
      echo "  --tui   Open the interactive OpenClaw terminal inside the sandbox"
      echo "  --ui    Forward the OpenClaw web UI to http://127.0.0.1:18789 and open it"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${UI_MODE}" == "true" ]]; then
  bash "${REPO_ROOT}/deploy/ui.sh" --target "${TARGET}"
  exit 0
fi

bash "${REPO_ROOT}/deploy/run.sh" --scenario "${SCENARIO}" --target "${TARGET}" ${TUI}
