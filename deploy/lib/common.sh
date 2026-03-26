#!/usr/bin/env bash
# Shared helpers for deploy scripts.

log()  { echo "[$(date '+%H:%M:%S')] [INFO]  $*" >&2; }
warn() { echo "[$(date '+%H:%M:%S')] [WARN]  $*" >&2; }
die()  { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; exit 1; }

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") --scenario <scenario-name> --target <target-name>

Options:
  --scenario   Name of the scenario directory under scenarios/
  --target     Name of the target defined in config/targets.yaml
  --help       Show this message

Environment:
  SCENARIO     Alternative to --scenario
  TARGET       Alternative to --target
EOF
}

load_env() {
  local env_file="$1"
  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  fi
}
