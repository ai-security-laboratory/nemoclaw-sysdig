"""Functional tests for the security triage agent.

These tests run against sample data in dry-run mode (no LLM calls needed).
Integration tests that hit a real LLM are marked with @pytest.mark.integration.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

SCENARIO_DIR = Path(__file__).parent.parent
AGENT_DIR = SCENARIO_DIR / "agent"
DATA_DIR = SCENARIO_DIR / "data"


# ---------------------------------------------------------------------------
# Model / tool unit tests
# ---------------------------------------------------------------------------

sys.path.insert(0, str(AGENT_DIR))


def test_alert_model_parses_sample_data():
    from models import Alert, Severity

    raw = json.loads((DATA_DIR / "sample_alerts.json").read_text())
    alerts = [Alert(**a) for a in raw]

    assert len(alerts) == 5
    assert alerts[0].severity == Severity.CRITICAL
    assert alerts[0].rule_name == "Terminal shell in container"


def test_triage_result_model():
    from models import TriageDecision, TriageResult

    result = TriageResult(
        alert_id="test-001",
        decision=TriageDecision.ESCALATE,
        risk_score=90,
        reasoning="Confirmed C2 beacon after shell and credential access.",
        suggested_actions=["Isolate container", "Preserve forensic image"],
        playbook="1. Isolate pod\n2. Collect logs\n3. Page CIRT",
    )
    assert result.risk_score == 90
    assert result.decision == TriageDecision.ESCALATE


def test_mitre_mapping():
    from tools import map_to_mitre

    tactics = map_to_mitre("Terminal shell in container")
    assert any("T1059" in t for t in tactics)

    tactics = map_to_mitre("Crypto mining detected")
    assert any("T1496" in t for t in tactics)

    tactics = map_to_mitre("Some unknown rule")
    assert tactics  # Always returns something


def test_related_alerts_correlation():
    from tools import get_related_alerts, register_alert
    from datetime import datetime

    register_alert({
        "id": "past-001",
        "container_id": "abc123",
        "namespace": "prod",
        "timestamp": datetime.utcnow().isoformat(),
    })

    related = get_related_alerts("abc123", "prod", window_seconds=60)
    assert any(a["id"] == "past-001" for a in related)


# ---------------------------------------------------------------------------
# Agent dry-run test (no LLM)
# ---------------------------------------------------------------------------

def test_agent_dry_run():
    """Run agent CLI in dry-run mode and verify it produces valid JSON output."""
    result = subprocess.run(
        [
            sys.executable,
            str(AGENT_DIR / "agent.py"),
            "--input", str(DATA_DIR / "sample_alerts.json"),
            "--dry-run",
        ],
        capture_output=True,
        text=True,
        env={"PATH": "/usr/bin:/bin", "DRY_RUN": "true"},
    )
    assert result.returncode == 0, f"Agent failed:\n{result.stderr}"
    output = json.loads(result.stdout)
    assert isinstance(output, list)
    assert len(output) == 5
    for item in output:
        assert "alert_id" in item
        assert "decision" in item
        assert "risk_score" in item


# ---------------------------------------------------------------------------
# Integration tests (require live credentials)
# ---------------------------------------------------------------------------

@pytest.mark.integration
def test_agent_live_single_alert():
    """Triage one high-severity alert with a real LLM call."""
    import os
    if not os.environ.get("NVIDIA_API_KEY"):
        pytest.skip("NVIDIA_API_KEY not set")

    sample = json.loads((DATA_DIR / "sample_alerts.json").read_text())
    high_severity = [a for a in sample if a["severity"] >= 3][0]

    with open("/tmp/single_alert.json", "w") as f:
        json.dump([high_severity], f)

    result = subprocess.run(
        [sys.executable, str(AGENT_DIR / "agent.py"), "--input", "/tmp/single_alert.json"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    output = json.loads(result.stdout)
    assert output[0]["risk_score"] >= 50, "High-severity alert should score ≥50"
