# Scenario 01: Security Incident Triage Agent

An autonomous agent that triages Sysdig security alerts without human prompting.

## What makes this a real agent (not a reactive LLM)

| Capability | How it's used here |
|---|---|
| **Multi-step reasoning** | Alert → enrich → correlate → risk score → decision |
| **Tool use** | Calls Sysdig API, container metadata, CVE lookup, MITRE ATT&CK |
| **State management** | Tracks alert history, deduplicates, maintains triage queue |
| **Autonomous decisions** | Auto-close noise, escalate high risk, draft response playbook |
| **Memory** | Learns which alert patterns are true positives in this environment |

## Architecture

```
                    ┌─────────────────────────────────┐
   Sysdig Alerts    │      Triage Agent (NemoClaw)     │
   ──────────────►  │                                  │
                    │  1. Ingest & deduplicate alerts   │
                    │  2. Enrich with context           │
                    │     - Container / pod metadata    │
                    │     - Process lineage             │
                    │     - CVE / vulnerability data    │
                    │     - MITRE ATT&CK mapping        │
                    │  3. Correlate across time window  │
                    │  4. Score risk (LOW/MED/HIGH/CRIT)│
                    │  5. Decide & act:                 │
                    │     - LOW  → auto-close + note    │
                    │     - MED  → queue for analyst    │
                    │     - HIGH → draft playbook       │
                    │     - CRIT → escalate + page      │
                    └─────────────────────────────────┘
```

## Directory layout

```
01-security-triage/
├── agent/
│   ├── agent.py          # Main agent loop
│   ├── tools.py          # Tool definitions (Sysdig API, enrichment)
│   ├── prompts.py        # System prompt and task templates
│   └── models.py         # Pydantic models for alerts, decisions
├── config/
│   └── agent.yaml        # Non-secret agent config (thresholds, models)
├── data/
│   └── sample_alerts.json  # Synthetic alert data for testing
├── tests/
│   ├── test_triage.py    # Functional tests against sample data
│   ├── test_tools.py     # Unit tests for individual tools
│   └── fixtures/         # Test fixtures
└── setup.sh              # Remote VM setup (Python env, deps)
```

## Running locally

```bash
cd scenarios/01-security-triage
pip install -r ../../requirements.txt
python agent/agent.py --input data/sample_alerts.json --dry-run
```

## Running tests

```bash
# From repo root:
make test SCENARIO=01-security-triage

# Or directly:
cd scenarios/01-security-triage
pytest tests/ -v
```

## Deploying to a VM

```bash
# From repo root:
make deploy SCENARIO=01-security-triage TARGET=my-oracle-vm
```
