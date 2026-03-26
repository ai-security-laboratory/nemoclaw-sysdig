# Architecture

## Design principles

**1. Scenarios are self-contained**
Each scenario under `scenarios/` is a complete, deployable unit. It has its own agent code, config, test data, and test suite. Scenarios share infrastructure (deploy scripts, common libraries) but are otherwise independent.

**2. Secrets never touch the repo**
The deployment pipeline separates _what to deploy_ (repo) from _secrets_ (`.env`, `config/targets.yaml`). The deploy script uploads `.env` to the remote over SSH at deploy time.

**3. Agent ≠ chatbot**
Scenarios demonstrate genuine agentic behavior: multi-step tool use, autonomous decisions, and state across a session. They are not question-answering demos.

**4. Test-first**
Every scenario ships with unit tests (no credentials needed) and integration tests (marked `@pytest.mark.integration`). The CI pipeline runs unit tests; integration tests run on demand against a live VM.

---

## Deployment flow

```
Local machine                          Target VM
─────────────────────────────────────────────────────
make deploy SCENARIO=X TARGET=Y
  │
  ├─ read config/targets.yaml     →  SSH connection details
  ├─ rsync scenarios/X/           →  /opt/nemoclaw/X/
  ├─ scp .env                     →  /opt/nemoclaw/X/.env
  └─ ssh bash setup.sh            →  python venv + pip install
```

---

## Agent architecture (per scenario)

```
agent.py          — orchestration loop, CLI entry point
  │
  ├── prompts.py  — system prompt, task templates
  ├── tools.py    — tool definitions + implementations
  └── models.py   — Pydantic input/output schemas
```

The agent calls an OpenAI-compatible endpoint (NVIDIA NIM) with structured JSON output, parses the response into a typed `TriageResult`, and acts on the decision.

---

## Adding a new scenario

1. Copy `scenarios/01-security-triage/` to `scenarios/NN-your-scenario/`
2. Update `agent/prompts.py`, `agent/tools.py`, `agent/models.py`
3. Add sample data to `data/`
4. Write tests in `tests/`
5. Update `config/agent.yaml` if needed
6. Add a row to the Scenarios table in `README.md`
