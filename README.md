# nemoclaw-sysdig

A framework for building, deploying, and testing [NemoClaw](https://github.com/NVIDIA/NeMo) agentic scenarios — with a focus on enterprise security use cases and integration with Sysdig.

Each scenario is a self-contained agentic workflow that can be deployed to a target VM via SSH and exercised with a dedicated test suite.

---

## What is NemoClaw?

NemoClaw is NVIDIA's agentic AI framework built on NeMo, designed for multi-step reasoning and tool-use workflows. This repo explores its capabilities in enterprise security contexts: alert triage, threat investigation, compliance auditing, and more.

---

## Repository Structure

```
nemoclaw-sysdig/
├── scenarios/                  # One directory per use case
│   └── 01-security-triage/     # First scenario: autonomous alert triage
│       ├── agent/              # Agent definition, tools, prompts
│       ├── config/             # Scenario-specific config (no secrets)
│       ├── data/               # Sample/synthetic data for testing
│       └── tests/              # Scenario-specific test suite
├── deploy/                     # Deployment scripts (SSH-based, secret-free)
│   ├── deploy.sh               # Deploy a scenario to a target VM
│   ├── teardown.sh             # Remove a deployed scenario
│   └── lib/                    # Shared shell helpers
├── tests/                      # Cross-scenario and integration tests
│   └── common/                 # Shared fixtures and utilities
├── config/
│   ├── targets.example.yaml    # VM target definitions (template — no IPs/keys)
│   └── env.example             # Required environment variables (template)
├── docs/
│   ├── architecture.md         # System design and agent patterns
│   ├── deployment.md           # How to deploy and configure targets
│   └── scenarios/              # Per-scenario deep-dives
├── Makefile                    # Common workflows: deploy, test, teardown
└── requirements.txt            # Python dependencies
```

---

## Quick Start

### 1. Configure your environment

```bash
cp config/env.example .env
cp config/targets.example.yaml config/targets.yaml
# Edit both files with your actual values — they are gitignored
```

### 2. Deploy a scenario to a VM

```bash
make deploy SCENARIO=01-security-triage TARGET=my-oracle-vm
```

Or directly:

```bash
./deploy/deploy.sh --scenario 01-security-triage --target my-oracle-vm
```

### 3. Run the tests for that scenario

```bash
make test SCENARIO=01-security-triage TARGET=my-oracle-vm
```

---

## Scenarios

| # | Name | Description | Status |
|---|------|-------------|--------|
| 01 | [Security Incident Triage](scenarios/01-security-triage/) | Agent autonomously triages Sysdig security alerts: enriches context, correlates signals, prioritizes, and drafts response actions | In Progress |

---

## Secrets & Security

**No secrets are ever committed to this repository.**

- `.env` — runtime credentials and API keys (gitignored, use `config/env.example` as template)
- `config/targets.yaml` — VM hostnames, SSH users, paths (gitignored, use `config/targets.example.yaml`)
- SSH keys — managed outside the repo; path referenced in `config/targets.yaml`

All deployment scripts read secrets from environment variables or local config files. CI/CD systems should inject secrets via environment, not files.

---

## Development

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Run linting and formatting:

```bash
make lint
make fmt
```

---

## License

Internal use — Sysdig confidential.
