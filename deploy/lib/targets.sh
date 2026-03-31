#!/usr/bin/env bash
# Parse a target from config/targets.yaml and export connection variables.
# Requires: yq (https://github.com/mikefarah/yq)

read_target() {
  local targets_file="$1"
  local target_name="$2"

  [[ -f "${targets_file}" ]] || die "Targets file not found: ${targets_file}
  Create it at the repo's parent directory (e.g. cp config/targets.example.yaml ../targets.yaml) and fill in your values."

  command -v yq &>/dev/null || die "'yq' is required. Install: brew install yq"

  local host user ssh_key remote_base sandbox_name provider model
  host=$(yq ".targets.${target_name}.host" "${targets_file}")
  user=$(yq ".targets.${target_name}.user" "${targets_file}")
  ssh_key=$(yq ".targets.${target_name}.ssh_key" "${targets_file}")
  remote_base=$(yq ".targets.${target_name}.remote_base" "${targets_file}")
  sandbox_name=$(yq ".targets.${target_name}.sandbox_name" "${targets_file}")
  provider=$(yq ".targets.${target_name}.provider" "${targets_file}")
  model=$(yq ".targets.${target_name}.model" "${targets_file}")

  [[ "${host}" != "null" ]] || die "Target '${target_name}' not found in ${targets_file}"

  # Fall back to defaults if yaml value is null
  export TARGET_HOST="${host}"
  export TARGET_USER="${user:-${SSH_USER:-ubuntu}}"
  export TARGET_SSH_KEY="${ssh_key:-${SSH_KEY_PATH:-~/.ssh/id_ed25519}}"
  export TARGET_REMOTE_BASE="${remote_base:-/opt/nemoclaw}"
  export TARGET_SANDBOX_NAME="${sandbox_name:-openclaw}"
  export TARGET_PROVIDER="${provider:-build}"
  export TARGET_MODEL="${model:-nvidia/llama-3.3-nemotron-super-49b-v1}"

  # Expand ~ in ssh key path
  TARGET_SSH_KEY="${TARGET_SSH_KEY/#\~/$HOME}"
}
