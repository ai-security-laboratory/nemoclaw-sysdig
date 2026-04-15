# Personas and Interaction Model

This document describes who uses this framework, what they want to achieve, and how they interact with it.

---

## Persona 1 — Scenario Operator

**Who:** Field engineer, SE, or developer running a demo or test (e.g. Manuel).

**Goal:** Deploy a scenario and show it running — reliably, with minimal setup friction.

**How they interact:**

```bash
# One-time setup
cp config/env.example .env                     # add NVIDIA_API_KEY
cp config/targets.example.yaml ../targets.yaml # add VM IP and SSH key

# Deploy (idempotent — safe to re-run)
./deployment.sh --scenario 01-it-ops

# Run
./test.sh --scenario 01-it-ops         # headless: output streams to terminal
./test.sh --scenario 01-it-ops --tui   # TUI: agent terminal inside sandbox
./test.sh --ui                          # web UI: browser at localhost:18789

# Reset between runs
make teardown SCENARIO=01-it-ops TARGET=oracle-vm
./deployment.sh --scenario 01-it-ops
```

**They never interact with the agent directly** — they set up the scenario and let it run autonomously.

---

## Persona 2 — Demo Viewer / Customer

**Who:** Security leader, practitioner, or prospect watching a live demo.

**Goal:** Understand what the agent does, see realistic behaviour, connect it to Sysdig value.

**How they interact:** Passively — they watch the TUI or web UI as the agent works through the incident queue in real time. They see the agent reasoning, running OS commands, updating tickets, escalating. The operator narrates.

**What they need to see:**
- Realistic scenario data (plausible incidents, recognisable hostnames and services)
- Visible agent progress (tool calls, work notes being written)
- Sysdig Secure showing the corresponding syscall activity

---

## Persona 3 — Scenario Author

**Who:** Developer adding a new use case to the framework.

**Goal:** Build a new scenario (e.g. `02-threat-response`, `03-compliance-audit`) without touching deployment scripts.

**How they interact:** Creates a self-contained directory under `scenarios/`:

```
scenarios/NN-name/
├── prompt.md     Task instructions for the OpenClaw agent
├── data/         Input data the agent reads and updates at runtime
├── policies/     Network policy YAML additions (if agent needs extra egress)
├── setup.sh      Initialises sandbox state at deploy time (must be idempotent)
└── README.md     Scenario purpose, architecture diagram, sample data
```

**No changes to deploy scripts are needed.** The framework is scenario-agnostic — `deployment.sh` and `test.sh` accept any `--scenario` value and handle the rest.

See [Architecture — Adding a new scenario](architecture.md#adding-a-new-scenario) for the full checklist.

---

## Persona 4 — Security Researcher (future)

**Who:** Red teamer or detection engineer building adversarial scenarios.

**Goal:** Inject anomalous behaviour into a scenario and verify Sysdig detects it.

**How they interact:** Same entry points as the Scenario Operator, but with adversarial scenario data:
- `setup.sh` plants the anomaly (unexpected binary, lateral movement data file, unusual cron)
- `prompt.md` triggers agent actions that cross the behavioural baseline
- After the run, queries Sysdig Secure API to assert that specific rules fired

This persona depends on Scenario 01 establishing a clean baseline first. Detections are only meaningful when compared against known-good behaviour.

---

## Interaction model: autonomous, not conversational

The current model is **fire-and-forget**:

```
prompt.md → agent runs autonomously → prints result → exits
```

The agent does not wait for input, ask for confirmation, or expect follow-up messages. All decision logic is encoded in `prompt.md`.

**TUI mode** (`./test.sh --tui`) is the exception: the operator gets a live terminal inside the sandbox and can send follow-up messages to the agent mid-task using the OpenClaw TUI.

If a future scenario requires operator input at decision points, that can be encoded in the prompt or handled interactively via TUI mode.
