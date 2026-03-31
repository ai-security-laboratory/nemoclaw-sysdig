# Deployment and Testing

Complete instructions from scratch.

---

## Prerequisites

**Local machine:**
- `yq`: `brew install yq`
- `rsync`: pre-installed on macOS/Linux
- SSH access to the Oracle VM

**Oracle VM:**
- Ubuntu 22.04 LTS, min 8 GB RAM, 20 GB free disk, internet access

---

## One-time setup

### 1. Configure secrets

```bash
cp config/env.example .env
```

Edit `.env` and fill in:
- `NVIDIA_API_KEY` — from [build.nvidia.com](https://build.nvidia.com)
- `SYSDIG_SECURE_TOKEN` — from Sysdig Secure → Settings → API Tokens

### 2. Configure the target VM

`../targets.yaml` lives outside the repo, next to your SSH key. Verify it looks like this:

```yaml
targets:
  oracle-vm:
    host: <vm-ip>
    user: ubuntu
    ssh_key: ~/path/to/your.key
    remote_base: /opt/nemoclaw
    sandbox_name: openclaw
    provider: build
    model: nvidia/llama-3.3-nemotron-super-49b-v1
```

---

## Deploy

A single command does everything — installs NemoClaw, creates the sandbox (if needed), and deploys the scenario:

```bash
./deployment.sh --scenario 01-it-ops
```

All steps are **idempotent** — safe to run multiple times. The sandbox is only created on the first run; subsequent runs skip straight to deploying the scenario.

What it does internally:
1. Installs Node.js 22, Docker, and the NemoClaw CLI on the VM over SSH
2. Creates the NemoClaw sandbox (skipped if it already exists)
3. Injects the scenario data, prompt, and network policies into the sandbox

---

## Run

**Task mode** — agent works autonomously, output streams to your terminal:
```bash
./test.sh --scenario 01-it-ops
```

**TUI mode** — opens the OpenClaw terminal inside the sandbox (recommended for demos):
```bash
./test.sh --scenario 01-it-ops --tui
```

**Web UI** — forwards the OpenClaw dashboard to your local browser:
```bash
./test.sh --ui
```

Press `Ctrl+C` to exit and return to your laptop. The sandbox keeps running.

---

## Reset between runs

```bash
make teardown SCENARIO=01-it-ops TARGET=oracle-vm
./deployment.sh --scenario 01-it-ops
```

---

## Sandbox management (on the VM)

```bash
nemoclaw list                    # list sandboxes
nemoclaw openclaw status         # health + inference config
nemoclaw openclaw logs --follow  # live logs
nemoclaw openclaw connect        # open a shell inside the sandbox
nemoclaw openclaw destroy        # permanently delete the sandbox
```
