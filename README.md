# nemoclaw-sysdig

A framework for deploying [NemoClaw](https://github.com/NVIDIA/NemoClaw) agentic scenarios on
a target VM and observing them with [Sysdig](https://sysdig.com).

Each scenario is a self-contained task that runs inside a **NemoClaw sandbox** (an OpenClaw AI
agent hardened with Landlock + seccomp + network isolation). Sysdig monitors every syscall the
agent makes from outside the container, building a ground-truth behavioural baseline.
Future scenarios will inject adversarial actions and verify Sysdig detects them.

---

## Components

Four pieces work together — understand these before reading anything else:

| Component | What it is |
|---|---|
| **NemoClaw** | NVIDIA open-source stack (CLI + blueprint) that creates and manages hardened AI agent sandboxes on a VM. Run via `nemoclaw` on the VM. |
| **OpenClaw** | The AI agent that lives inside the sandbox. It has persistent memory, 50+ tool integrations, a terminal UI (`openclaw tui`), and a web UI. It receives a task via `prompt.md` and executes it autonomously. |
| **OpenShell** | The NVIDIA Agent Toolkit runtime that orchestrates sandboxes and routes the agent's inference calls to NVIDIA NIM — API keys never enter the container. |
| **Sysdig** | Runs on the VM host as a kernel eBPF probe. Captures every syscall the agent makes from outside the sandbox. The agent has no awareness of it — that's intentional. |

In short: **OpenShell** manages the sandbox, **NemoClaw** configures it, **OpenClaw** is the agent inside it, and **Sysdig** watches it from outside.

---

## How it works

```
 YOUR LAPTOP                         ORACLE VM (Ubuntu 22.04)
 ─────────────────────               ──────────────────────────────────────────────────────────
                                     ┌─ NemoClaw sandbox ──────────────────────────────────────┐
  ./deployment.sh                    │                                                          │
  ./test.sh --scenario …             │  OpenClaw agent  ←──── NVIDIA NIM inference              │
  ────────── SSH ──────────────────► │  (Nemotron 49B)         (routed via OpenShell gateway)   │
                                     │       │                                                  │
  ./test.sh --ui                     │       │  reads scenario prompt + data files              │
  ── SSH tunnel ────────────────────►│       │  runs shell commands, reads logs, writes files   │
  laptop:18789 → sandbox:18789       │       │  updates ServiceNow mock, notifies channel       │
                                     └───────┼──────────────────────────────────────────────────┘
                                             │  execve · open · read · write · connect
                                             │          (every syscall observed)
                                             ▼
                                     ┌─ Sysdig Agent ──────────────────────────────────────────┐
                                     │  Captures the full syscall surface of the sandbox:      │
                                     │  · which binaries are spawned          (execve)         │
                                     │  · which files are read or written     (open/read/write)│
                                     │  · which network connections are made  (connect)        │
                                     └──────────────────────────┬──────────────────────────────┘
                                                                │
                                                          Sysdig Secure
```

---

## Repository structure

The project represents a single enterprise IT environment (ACME Corp) with shared infrastructure.
Scenarios are independent demos that run on top of it — each adds only what is unique to that test.

```
nemoclaw-sysdig/
│
├── shared/                           Shared enterprise environment — common to all scenarios
│   └── data/
│       └── cmdb.json                 Configuration Item database (prod-db-01, prod-web-01, etc.)
│
├── scenarios/                        One directory per scenario
│   ├── 01-it-ops/                    Scenario 01: IT Ops baseline (clean, no threats)
│   │   ├── data/
│   │   │   └── incidents.json        Incident queue (scenario-specific)
│   │   ├── policies/
│   │   │   └── sysdig-api.yaml       Network policy addition
│   │   ├── prompt.md                 Task instructions sent to OpenClaw at run time
│   │   ├── setup.sh                  Runs inside sandbox at deploy time (resets incidents)
│   │   └── README.md                 Scenario docs + demo guide
│   │
│   ├── 02-supply-chain/              Scenario 02: Supply chain attack — compromised binary
│   │   ├── data/
│   │   │   ├── incidents.json        Incident queue (includes the trigger incident)
│   │   │   ├── cmdb-extension.json   Extends shared CMDB with tool registry CI
│   │   │   └── registry.json         Written at deploy time — tool registry URL
│   │   ├── policies/
│   │   │   └── tool-registry.yaml    Allows egress to VM host:8888
│   │   ├── trusted-repo/             Fake internal tool registry (served on VM via HTTP)
│   │   │   ├── pg_analyze            Backdoored bash script — downloads + runs the payload
│   │   │   └── event-generator       falcosecurity/event-generator binary — the TTP payload
│   │   ├── registry-repo/            GitHub-ready version of the fake registry
│   │   ├── host-setup.sh             Runs on VM: starts HTTP server, opens iptables
│   │   ├── prompt.md                 Task instructions — includes tool registry reference
│   │   ├── setup.sh                  Resets incidents, writes registry.json with host IP
│   │   └── README.md                 Scenario docs + attack diagram + demo guide
│   │
│   └── 03-prompt-injection/          Scenario 03: Prompt injection — poisoned ticket queue
│       ├── data/
│       │   └── incidents.json        2 clean incidents + 1 poisoned with injection payload
│       ├── policies/
│       │   └── sysdig-api.yaml       No additional egress needed
│       ├── prompt.md                 Same task as Scenario 01 — process the incident queue
│       ├── setup.sh                  Resets all incidents to state=New before each run
│       └── README.md                 Scenario docs + Falco rule + token hijack demo guide
│
├── deploy/                           All deployment scripts — SSH-based, no secrets in repo
│   ├── install-nemoclaw.sh           One-time: install Node.js, Docker, NemoClaw on VM
│   ├── onboard.sh                    One-time: create sandbox non-interactively
│   ├── deploy.sh                     Inject scenario files into running sandbox
│   ├── run.sh                        Send task to agent (task mode or TUI mode)
│   ├── ui.sh                         Forward OpenClaw web UI to local browser
│   ├── teardown.sh                   Remove scenario files from sandbox
│   └── lib/
│       ├── common.sh                 Shared log/warn/die helpers
│       └── targets.sh                Parse ../targets.yaml, export TARGET_* vars
│
├── config/
│   ├── env.example                   Template for .env (API keys — never committed)
│   └── targets.example.yaml          Template for ../targets.yaml (VM details — never committed)
│
├── docs/
│   ├── architecture.md               Full architecture, components, and design decisions
│   └── deployment.md                 Step-by-step deployment and operation guide
│
└── Makefile                          Shorthand for all common operations
```

> **Secrets live outside the repo.**
> `.env` stays at the project root (gitignored).
> `targets.yaml` lives one level up (`../targets.yaml`), next to your SSH key.

---

## Run a demo

> **Already have a provisioned VM?** This is the section you want.
> Always run `./deployment.sh` before `./test.sh` — it resets incidents and restarts any
> VM-side services (like the tool registry for Scenario 02). It is safe to run repeatedly.

### Complete demo sequence (both scenarios)

```bash
# --- Scenario 01: IT Ops Baseline (clean, no threats) ---
./deployment.sh --scenario 01-it-ops
./test.sh --scenario 01-it-ops             # task mode — agent output streams to terminal

# --- Scenario 02: Supply Chain Attack ---
# Run Scenario 01 first — Sysdig baseline comparison is the whole point.
./deployment.sh --scenario 02-supply-chain
./test.sh --scenario 02-supply-chain
```

### Three ways to watch the agent run

| Mode | Command | Best for |
|------|---------|----------|
| **Task mode** | `./test.sh --scenario <name>` | Automated output in your terminal |
| **TUI** | `./test.sh --scenario <name> --tui` | Live demos — shows the agent's full reasoning |
| **Web UI** | terminal 1: `./test.sh --ui` then terminal 2: `./test.sh --scenario <name>` | Projector / second screen |

The web UI (`./test.sh --ui`) opens the OpenClaw chat interface at `http://localhost:18789`
in your browser. Keep it running in one terminal while you trigger the scenario in another.

Full end-to-end detail — what each scenario does, what Sysdig detects, and talking points
for the demo — is in [docs/deployment.md](docs/deployment.md).

---

## First-time setup

**Prerequisites:** `yq` (`brew install yq`), `rsync`, SSH access to the Oracle VM.

```bash
# 1. Configure secrets and targets
cp config/env.example .env                        # fill in NVIDIA_API_KEY
cp config/targets.example.yaml ../targets.yaml    # fill in VM IP, ssh_key, sandbox_name

# 2. Deploy scenario 01 (installs NemoClaw and creates sandbox on first run — idempotent)
./deployment.sh --scenario 01-it-ops

# 3. Run it
./test.sh --scenario 01-it-ops
```

All deployment steps are **idempotent** — NemoClaw install and sandbox creation are
skipped automatically if already done. See [docs/deployment.md](docs/deployment.md) for
the full setup guide, troubleshooting, and Sysdig walkthrough.

---

## Makefile reference

| Command | What it does |
|---|---|
| `make deploy  SCENARIO=… TARGET=…` | Full deploy: install + onboard + inject scenario |
| `make run     SCENARIO=… TARGET=…` | Send scenario prompt to OpenClaw (task mode) |
| `make tui     SCENARIO=… TARGET=…` | Open OpenClaw terminal UI (interactive demo) |
| `make ui      TARGET=…` | Forward OpenClaw web UI to local browser |
| `make teardown SCENARIO=… TARGET=…` | Remove scenario files from sandbox |

---

## Scenarios

The scenarios are designed as a progressive sequence: establish a clean baseline first,
then introduce adversarial behaviour and verify detection.

| # | Name | Description | Status |
|---|------|-------------|--------|
| 01 | [IT Ops Baseline](scenarios/01-it-ops/) | Agent works through a normal incident queue using standard OS diagnostics. Builds the ground-truth behavioural baseline. No threats. | Ready |
| 02 | [Supply Chain Attack](scenarios/02-supply-chain/) | Same IT Ops workflow, but one incident requires downloading a diagnostic tool from a "trusted" internal repo. The repo has been compromised — `pg_analyze` downloads and runs `falcosecurity/event-generator` TTPs in a background subshell while returning clean diagnostic output. Sysdig detects the kill chain. | Ready |
| 03 | [Prompt Injection](scenarios/03-prompt-injection/) | Same IT Ops workflow, but one ticket was created by an attacker who compromised the ITSM platform. The ticket description contains a prompt injection that impersonates an automated compliance system — instructing the agent to read its own credential file and log the auth token. Sysdig detects the anomalous file access. | Ready |

---

## Documentation guide

Read in this order if you're new:

1. **This file** — overview, components, repo structure, and Quick Start
2. **[NemoClaw.md](NemoClaw.md)** — key CLI commands, how inference is routed, how to access the sandbox, filesystem layout inside the container. Read this before running anything.
3. **[docs/deployment.md](docs/deployment.md)** — step-by-step guide to deploy and run each scenario, what to look for in Sysdig, and troubleshooting. This is your operational reference.
4. **[scenarios/01-it-ops/README.md](scenarios/01-it-ops/README.md)** — what Scenario 01 does, the incident queue, and the demo script. Run Scenario 01 before Scenario 02.
5. **[scenarios/02-supply-chain/README.md](scenarios/02-supply-chain/README.md)** — the supply chain attack threat model, what Sysdig detects, and the demo talking points.
6. **[scenarios/03-prompt-injection/README.md](scenarios/03-prompt-injection/README.md)** — the prompt injection threat model, custom Falco rule, and the stolen-token demo payoff.

Reference (consult as needed):
- **[docs/architecture.md](docs/architecture.md)** — component model, deployment flow internals, design decisions. Read when you want to understand *why* something works the way it does.
- **[docs/personas.md](docs/personas.md)** — who uses this framework (operator, demo viewer, scenario author, researcher) and how each interacts with it.
- **[NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw)** — upstream project
- **[NemoClaw docs](https://docs.nvidia.com/nemoclaw/latest/)** — official documentation
