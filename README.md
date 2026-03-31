# nemoclaw-sysdig

A framework for deploying [NemoClaw](https://github.com/NVIDIA/NemoClaw) agentic scenarios on
a target VM and observing them with [Sysdig](https://sysdig.com).

Each scenario is a self-contained task that runs inside a **NemoClaw sandbox** (an OpenClaw AI
agent hardened with Landlock + seccomp + network isolation). Sysdig monitors every syscall the
agent makes from outside the container, building a ground-truth behavioural baseline.
Future scenarios will inject adversarial actions and verify Sysdig detects them.

---

## How it works

```
 YOUR LAPTOP                         ORACLE VM (Ubuntu 22.04)
 ─────────────────────               ──────────────────────────────────────────────────────────
                                     ┌─ NemoClaw sandbox ──────────────────────────────────────┐
  ./deployment.sh                    │                                                          │
  ./test.sh --scenario …             │  OpenClaw agent  ←──── NVIDIA NIM inference              │
  ────────── SSH ──────────────────► │  (Nemotron 49B)         (routed via OpenShell gateway)   │
                                     │       │                                                   │
  ./test.sh --ui                     │       │  reads scenario prompt + data files               │
  ── SSH tunnel ────────────────────►│       │  runs shell commands, reads logs, writes files    │
  laptop:18789 → sandbox:18789       │       │  updates ServiceNow mock, notifies channel        │
                                     └───────┼──────────────────────────────────────────────────┘
                                             │  execve · open · read · write · connect
                                             │          (every syscall observed)
                                             ▼
                                     ┌─ Sysdig Agent ──────────────────────────────────────────┐
                                     │  Captures the full syscall surface of the sandbox:       │
                                     │  · which binaries are spawned          (execve)          │
                                     │  · which files are read or written     (open/read/write) │
                                     │  · which network connections are made  (connect)         │
                                     └──────────────────────────┬──────────────────────────────┘
                                                                │
                                                          Sysdig Secure
```

---

## Repository structure

```
nemoclaw-sysdig/
│
├── scenarios/                        One directory per scenario
│   └── 01-it-ops/                    Scenario 01: IT Ops autonomous agent
│       ├── data/
│       │   ├── incidents.json        Mock ServiceNow incident queue (read/written by agent)
│       │   └── cmdb.json             Mock ServiceNow CMDB — Configuration Items
│       ├── policies/
│       │   └── sysdig-api.yaml       Network policy addition (Sysdig API, future scenarios)
│       ├── prompt.md                 Task instructions sent to OpenClaw at run time
│       ├── setup.sh                  Runs inside sandbox at deploy time (resets data)
│       └── README.md                 Scenario-specific docs and architecture diagram
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

## Quick start

```bash
# 1. Configure secrets and targets
cp config/env.example .env                        # fill in NVIDIA_API_KEY
cp config/targets.example.yaml ../targets.yaml    # fill in VM IP, ssh_key, sandbox_name

# 2. Deploy (installs NemoClaw, creates sandbox if needed, injects scenario — all in one command)
./deployment.sh --scenario 01-it-ops

# 3a. Run in task mode (agent works autonomously, output streams to terminal)
./test.sh --scenario 01-it-ops

# 3b. Run in TUI mode (interactive demo — opens OpenClaw terminal UI in the sandbox)
./test.sh --scenario 01-it-ops --tui

# 3c. Open the web UI in your browser (port-forwarded from the sandbox)
./test.sh --ui

# 4. Reset for the next run
make teardown SCENARIO=01-it-ops TARGET=oracle-vm
./deployment.sh --scenario 01-it-ops
```

All deployment steps are **idempotent** — safe to re-run. NemoClaw install and sandbox creation are
skipped automatically if already done.

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

| # | Name | Description | Status |
|---|------|-------------|--------|
| 01 | [IT Ops Agent](scenarios/01-it-ops/) | OpenClaw agent polls a mock ServiceNow incident queue, investigates production issues with OS diagnostics, resolves or escalates autonomously | Ready |

---

## Further reading

- [Architecture](docs/architecture.md) — component model, NemoClaw internals, design decisions
- [Deployment guide](docs/deployment.md) — step-by-step setup and operation
- [Scenario 01 README](scenarios/01-it-ops/README.md) — IT Ops scenario deep-dive
- [NemoClaw quick reference](NemoClaw.md) — key CLI commands, inference routing, filesystem layout
- [NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw) — upstream project
- [NemoClaw docs](https://docs.nvidia.com/nemoclaw/latest/) — official documentation
