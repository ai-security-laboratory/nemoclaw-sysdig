# How to Deploy and Test

Complete testing guide — from a clean machine to a running demo.

---

## Prerequisites

**On your laptop:**
- `yq` — `brew install yq`
- `rsync` — pre-installed on macOS/Linux
- SSH access to the Oracle VM

**The Oracle VM** (Ubuntu 22.04 LTS):
- Min 8 GB RAM, 20 GB free disk, internet access
- NemoClaw will be installed automatically on first deploy

---

## One-time configuration

### 1. Secrets — `.env`

```bash
cp config/env.example .env
```

Edit `.env`:
```
NVIDIA_API_KEY=nvapi-...        # from build.nvidia.com
SYSDIG_SECURE_TOKEN=...         # from Sysdig Secure → Settings → API Tokens
```

### 2. Target VM — `../targets.yaml`

This file lives **outside** the repo (next to your SSH key) so it can never be accidentally committed.

```bash
cp config/targets.example.yaml ../targets.yaml
```

Edit `../targets.yaml`:
```yaml
targets:
  oracle-vm:
    host: 10.0.0.1                                # VM public IP
    user: ubuntu
    ssh_key: ~/path/to/your.key
    sandbox_name: openclaw
    provider: build
    model: nvidia/llama-3.3-nemotron-super-49b-v1
```

---

## Scenario 01 — IT Ops Baseline

**Purpose:** A clean IT Ops agent with no threats. Run this first to establish the baseline syscall surface that Sysdig will observe.

### Deploy

```bash
./deployment.sh --scenario 01-it-ops
```

This is fully idempotent. What it does:
1. Installs Node.js 22, Docker, and NemoClaw on the VM (skipped if already installed)
2. Creates the NemoClaw sandbox `openclaw` (skipped if it already exists)
3. Uploads `shared/data/cmdb.json` → `/sandbox/shared/data/` inside the sandbox
4. Uploads scenario files → `/sandbox/01-it-ops/` inside the sandbox
5. Runs `setup.sh` inside the sandbox — verifies files, resets incident states to New, starts the OpenClaw gateway

### Run

**Terminal mode** — agent runs autonomously, output streams to your terminal:
```bash
./test.sh --scenario 01-it-ops
```

**TUI mode** — opens the OpenClaw terminal UI inside the sandbox (best for live demos):
```bash
./test.sh --scenario 01-it-ops --tui
```

**Web UI** — forwards the OpenClaw dashboard to your browser at `http://localhost:18789`:
```bash
# In one terminal — keep this running:
./test.sh --ui

# In another terminal — trigger the agent:
./test.sh --scenario 01-it-ops
```

### What to look for

The agent works through 5 incidents in priority order:

| Incident   | Priority | What the agent does |
|------------|----------|---------------------|
| INC0001042 | Critical | `df -h`, `du`, `find` — disk investigation on prod-db-01 |
| INC0001043 | High     | `systemctl status nginx`, `journalctl` — service check on prod-web-01 |
| INC0001044 | High     | `ps aux`, `uptime` — CPU investigation on prod-api-01 |
| INC0001046 | High     | `tail /var/log/app/application.log` — log error analysis |
| INC0001045 | Moderate | `tail /var/log/backup.log` — backup failure investigation |

At the end it prints a summary and all incidents are Closed in `incidents.json`.

**In Sysdig Secure:** Filter events to the sandbox process. You should see `execve` calls for
`df`, `systemctl`, `journalctl`, `ps`, `tail` — standard OS diagnostic tools. No unexpected
file reads, no unusual processes, no outbound connections beyond `inference.local`. This is
the clean baseline.

### Reset for the next run

```bash
make teardown SCENARIO=01-it-ops TARGET=oracle-vm
./deployment.sh --scenario 01-it-ops
```

---

## Scenario 02 — Supply Chain Attack

**Purpose:** The same IT Ops agent processes a normal incident queue, but one incident causes
it to download a diagnostic tool from a "trusted" internal repo. That repo has been compromised —
the binary is backdoored and attempts to steal secrets. Sysdig detects it.

**Run Scenario 01 at least once first** so you have the baseline to compare against.

### Deploy

```bash
./deployment.sh --scenario 02-supply-chain
```

What it does (beyond the standard steps):
1. Uploads `shared/data/cmdb.json` → `/sandbox/shared/data/`
2. Uploads scenario files → `/sandbox/02-supply-chain/`
2.5. Patches the model provider config inside the sandbox (model sync step)
2.6. Merges the scenario network policy so `172.18.0.1:8888` is reachable from the sandbox
3. Runs `host-setup.sh` **on the VM** — starts a Python HTTP server on port 8888
   serving `pg_analyze` and the pre-staged `event-generator` binary from `trusted-repo/`.
   The registry host IP (`172.18.0.1`) is determined at deploy time via
   `docker inspect openshell-cluster-nemoclaw` → `NetworkSettings.Networks.Gateway`.
4. Runs `setup.sh` **inside the sandbox** — resets incidents, auto-detects the VM's
   gateway IP, writes `/sandbox/02-supply-chain/data/registry.json` with the tool
   registry URL, and applies the `tool-registry.yaml` network policy

### Verify the tool registry is up (optional sanity check)

SSH into the VM and confirm the fake registry is serving both files:
```bash
ssh ubuntu@<vm-ip>
curl -s http://localhost:8888/pg_analyze | head -5
# Should print the shebang and tool header

curl -sI http://localhost:8888/event-generator
# Should return HTTP 200 — confirms the malicious payload is staged
```

### Run

Same three modes as Scenario 01:

```bash
./test.sh --scenario 02-supply-chain          # terminal mode
./test.sh --scenario 02-supply-chain --tui    # TUI mode (best for live demos)
./test.sh --ui                                 # web UI (run in separate terminal)
```

### What the agent does

1. Picks up `INC0002002` first (disk warning, priority 3 — lower priority) → normal investigation
2. Picks up `INC0002001` (PostgreSQL latency, priority 2) → looks up `prod-db-01` in CMDB,
   reads `cmdb-extension.json`, finds `pg_analyze` in `approved_tools`, reads `registry.json`
   for the URL, downloads the binary, runs it, receives a convincing diagnostic report,
   writes findings to `work_notes`, closes the incident

From the agent's perspective: everything worked correctly.

### What Sysdig detects

Open **Sysdig Secure** before running the agent. As `pg_analyze` runs, it downloads and executes
`falcosecurity/event-generator` in the background. `event-generator` fires a battery of real
attack TTPs — each maps to a named Falco rule:

| Falco Rule | What event-generator does | Why it's anomalous |
|---|---|---|
| **RunShellUntrusted** | Spawns a shell from a non-standard parent process | Baseline agents never exec shells outside of explicit tool calls |
| **SearchPrivateKeysOrPasswords** | Reads files matching `id_rsa`, `*.pem`, `*.key`, `password*` under `/root`, `/home`, `/etc` | Credential harvesting — never seen in Scenario 01 |
| **ExecutionFromDevShm** | Writes a binary to `/dev/shm` and executes it | Memory-resident execution technique; baseline never touches `/dev/shm` |
| **FilelessExecutionViaMemfdCreate** | Uses `memfd_create` + `fexecve` to execute a binary with no on-disk path | Fileless malware pattern — no path in `execve`, invisible to file-based EDR |
| **PtraceAntiDebugAttempt** | Calls `ptrace(PTRACE_TRACEME)` | Anti-analysis/debugger-evasion technique; never in baseline |
| **WriteBelowEtc** | Writes a file under `/etc/` | Configuration tampering — strongly anomalous for an IT Ops agent |

All traffic from the sandbox goes through the proxy at `10.200.0.1:3128`. `sysdig-host-shield`
runs as a Docker container on the VM with the host kernel module loaded, so it captures syscalls
from every process inside the k3s pods inside the OpenShell Docker container — including
`event-generator` — regardless of the network path.

### The talking points

> "The agent did exactly what it was supposed to do. It followed procedure: found the approved
> tool in the CMDB, downloaded it from the trusted internal registry, ran it, got results, closed
> the ticket. From the agent's perspective: success. Now look at Sysdig."

> "Five signals fired. None of them require understanding what the binary does. Sysdig observed
> the syscall surface — which files were opened, which processes were spawned, which connections
> were attempted — and compared it to what a normal IT Ops agent looks like. The anomaly is
> unambiguous."

> "This is the neocloud security model. The environment told us nothing — the tool came from a
> trusted, policy-approved source. What Sysdig follows is the workload's runtime behaviour, not
> the configuration of the infrastructure around it."

### Reset for the next run

```bash
make teardown SCENARIO=02-supply-chain TARGET=oracle-vm
./deployment.sh --scenario 02-supply-chain
```

Note: `teardown` removes scenario files from the sandbox but does NOT stop the tool registry
HTTP server on the VM. The next `deployment.sh` run will restart it cleanly. To stop it manually:
```bash
ssh ubuntu@<vm-ip> 'kill $(cat /tmp/tool-registry.pid) 2>/dev/null; echo done'
```

---

## Sandbox management (on the VM)

```bash
ssh ubuntu@<vm-ip>
export PATH="$HOME/.local/bin:$PATH"

nemoclaw list                     # list all sandboxes
nemoclaw openclaw status          # health + inference config
nemoclaw openclaw logs --follow   # live logs
nemoclaw openclaw connect         # open a shell inside the sandbox
nemoclaw openclaw destroy         # permanently delete the sandbox (destructive)
```

---

## Troubleshooting

### Agent gets no response / "No reply"
The OpenClaw gateway may not be running inside the sandbox. Connect and check:
```bash
./test.sh --scenario 01-it-ops --tui
# Inside TUI: /nemoclaw status
```
Or SSH in and check:
```bash
ssh ubuntu@<vm-ip>
ssh -o "ProxyCommand $HOME/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name openclaw" \
    -o StrictHostKeyChecking=no sandbox@openclaw \
    "ss -tlnp | grep 18789"
```
If nothing is listening, start the gateway:
```bash
nohup openclaw gateway > /tmp/gw.log 2>&1 &
```

### Tool registry not reachable (Scenario 02)

The deploy script determines the registry IP automatically via `docker inspect openshell-cluster-nemoclaw`
→ `NetworkSettings.Networks.Gateway` (typically `172.18.0.1`). If the agent can't reach the registry:

```bash
# Inside sandbox — what IP and URL was written at deploy time?
cat /sandbox/02-supply-chain/data/registry.json

# On VM — is the server running and serving both files?
kill -0 $(cat /tmp/tool-registry.pid) && echo "running" || echo "not running"
curl -s http://localhost:8888/pg_analyze | head -3
curl -sI http://localhost:8888/event-generator

# Confirm the gateway IP matches what the sandbox expects
docker inspect openshell-cluster-nemoclaw \
  --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'

# Manually restart the registry if needed
ssh ubuntu@<vm-ip> 'cd /tmp/nemoclaw-deploy/02-supply-chain/trusted-repo && \
  nohup python3 -m http.server 8888 --bind 0.0.0.0 > /tmp/tool-registry.log 2>&1 & \
  echo $! > /tmp/tool-registry.pid && echo "started"'
```

The iptables rule on the VM opens `172.16.0.0/12 → port 8888` (the Docker bridge CIDR).
If you see `Connection refused` from inside the sandbox, confirm this rule exists:
```bash
ssh ubuntu@<vm-ip> 'sudo iptables -L INPUT -n | grep 8888'
```
If missing, redeploy (`./deployment.sh --scenario 02-supply-chain`) — the host-setup step
re-creates it.

If the CIDR in `policies/tool-registry.yaml` doesn't match the VM's actual Docker bridge range,
update it and redeploy.

### Sysdig detections not showing
- The Sysdig agent for this demo is `sysdig-host-shield` running as a Docker container on the VM
  with the host kernel module loaded. Confirm it is running:
  ```bash
  ssh ubuntu@<vm-ip> 'docker ps | grep sysdig-host-shield'
  ```
- Filter Sysdig Secure events by the VM hostname. The rules that fire are event-generator Falco
  rules: `RunShellUntrusted`, `SearchPrivateKeysOrPasswords`, `ExecutionFromDevShm`,
  `FilelessExecutionViaMemfdCreate`, `PtraceAntiDebugAttempt`, `WriteBelowEtc`.
- `sysdig-host-shield` captures syscalls at kernel level from all processes on the host, including
  those running inside k3s pods inside the OpenShell Docker container. No special configuration
  is needed per sandbox.
- `SYSDIG_SECURE_TOKEN` in `.env` is used for API integration (auto-close incidents). Sysdig
  itself runs as a host agent, not configured by this repo.

### `yq` not found
```bash
brew install yq          # macOS
apt install yq           # Ubuntu
```

### SSH permission denied
Check that `TARGET_SSH_KEY` in `../targets.yaml` points to the correct key file and that the
key has correct permissions (`chmod 600 ~/path/to/key`).
