# NVIDIA NemoClaw — Quick Reference

> **Reading order:** Start with [README.md](README.md) for the overview and component definitions, then read this file before running anything.

NemoClaw is the upstream NVIDIA open-source project this framework is built on.

- **Repo:** https://github.com/NVIDIA/NemoClaw
- **Docs:** https://docs.nvidia.com/nemoclaw/latest/
- **Status:** Alpha (available since March 16, 2026)
- **License:** Apache 2.0

---

## What NemoClaw provides

| Layer | What it is |
|---|---|
| **OpenClaw** | The AI agent — persistent memory, 50+ integrations, TUI, self-modifying skills |
| **OpenShell** | NVIDIA Agent Toolkit sandbox runtime — manages the container lifecycle |
| **NemoClaw** | Reference stack on top of OpenShell — onboarding, inference routing, hardened blueprint |

---

## Sandbox security layers

| Layer | Mechanism |
|---|---|
| Filesystem isolation | Landlock — agent can only write to `/sandbox` and `/tmp` |
| Syscall filtering | seccomp — restricts available kernel calls |
| Network isolation | Network namespaces + deny-by-default egress policy |
| Capability dropping | All Linux capabilities dropped; only required ones re-added |
| Process limits | Max 512 processes per user (fork-bomb protection) |

---

## Key CLI commands (run on VM)

```bash
# Lifecycle
nemoclaw onboard                  # interactive wizard: create sandbox, configure inference
nemoclaw list                     # list all sandboxes
nemoclaw <name> status            # sandbox health + inference config
nemoclaw <name> connect           # open a shell inside the sandbox
nemoclaw <name> logs --follow     # stream sandbox logs
nemoclaw <name> destroy           # stop and delete sandbox

# Policy
nemoclaw <name> policy-list       # list available and applied policy presets
nemoclaw <name> policy-add        # add a preset (discord, slack, github, …)

# Inside the sandbox (after nemoclaw <name> connect)
openclaw tui                                         # open terminal UI
openclaw agent --agent main --json -m "your task"    # send a one-shot message (gateway mode)
/nemoclaw status                                     # show sandbox state in-chat
```

---

## Non-interactive onboard

```bash
export NVIDIA_API_KEY="nvapi-..."
export NEMOCLAW_NON_INTERACTIVE=1
export NEMOCLAW_SANDBOX_NAME="openclaw"
export NEMOCLAW_PROVIDER="build"            # build.nvidia.com
export NEMOCLAW_MODEL="nvidia/llama-3.3-nemotron-super-49b-v1"
nemoclaw onboard
```

---

## Inference routing

The agent inside the sandbox communicates with `inference.local`.
OpenShell routes that to the configured NVIDIA NIM endpoint on the host.
API keys never enter the container.

```
OpenClaw → inference.local → OpenShell gateway → integrate.api.nvidia.com
```

Default model: `nvidia/llama-3.3-nemotron-super-49b-v1`

Provider name: `build` (for build.nvidia.com)

---

## Sandbox access from VM

Sandboxes are **not** standalone Docker containers. They are managed by the OpenShell cluster
container (`openshell-cluster-nemoclaw`). Access is always via SSH ProxyCommand:

```bash
# SSH into sandbox
ssh -o "ProxyCommand $HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name <sandbox>" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    sandbox@<sandbox-name>

# Upload files into sandbox
openshell sandbox upload --no-git-ignore <sandbox-name> <local-path> <dest-path>
```

---

## OpenClaw gateway

The gateway process runs inside the sandbox at `127.0.0.1:18789`.

```bash
# Check if running
ss -tlnp | grep 18789

# Start (if not running)
nohup openclaw gateway > /tmp/gw.log 2>&1 &

# Auth token (for web UI)
python3 -c "import json; c=json.load(open('/sandbox/.openclaw/openclaw.json')); print(c['gateway']['auth']['token'])"
```

---

## Filesystem layout inside sandbox

```
/sandbox/                 read-write (agent home)
  └── <scenario>/
      ├── data/           scenario data files
      ├── policies/       scenario network policy additions
      └── prompt.md       task instructions
/tmp/                     read-write (ephemeral)
/proc/                    read-only (system info: df, free, uptime)
/var/log/                 read-only (log files)
/usr/ /etc/ /app/         read-only (system paths)
```
