"""Security Incident Triage Agent — main entry point.

Usage:
    python agent/agent.py --input data/sample_alerts.json
    python agent/agent.py --input data/sample_alerts.json --dry-run
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path

import yaml
from openai import OpenAI  # NIM is OpenAI-compatible

from models import Alert, TriageDecision, TriageResult
from prompts import SYSTEM_PROMPT, TRIAGE_TASK_TEMPLATE
from tools import TOOLS, register_alert

logger = logging.getLogger(__name__)


def load_config(config_path: Path) -> dict:
    with open(config_path) as f:
        return yaml.safe_load(f)


def build_client(config: dict) -> OpenAI:
    """Build an OpenAI-compatible client for NVIDIA NIM."""
    return OpenAI(
        base_url=os.environ.get("NEMO_BASE_URL", "https://integrate.api.nvidia.com/v1"),
        api_key=os.environ.get("NVIDIA_API_KEY", ""),
    )


def triage_alert(
    alert: Alert,
    client: OpenAI,
    model: str,
    dry_run: bool = False,
) -> TriageResult:
    """Run the triage agent on a single alert and return a decision."""

    register_alert(alert.model_dump(mode="json"))

    task_prompt = TRIAGE_TASK_TEMPLATE.format(
        alert_id=alert.id,
        timestamp=alert.timestamp.isoformat(),
        severity=alert.severity.name,
        rule_name=alert.rule_name,
        description=alert.description,
        container_name=alert.container_name or "unknown",
        container_id=alert.container_id or "unknown",
        namespace=alert.namespace or "unknown",
        process_name=alert.process_name or "unknown",
        process_cmdline=alert.process_cmdline or "",
        user_name=alert.user_name or "unknown",
    )

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": task_prompt},
    ]

    if dry_run:
        logger.info("[DRY RUN] Would call LLM for alert %s", alert.id)
        return TriageResult(
            alert_id=alert.id,
            decision=TriageDecision.QUEUE,
            risk_score=50,
            reasoning="Dry run — no LLM call made.",
            suggested_actions=["Review manually"],
        )

    response = client.chat.completions.create(
        model=model,
        messages=messages,
        temperature=0.0,
        response_format={"type": "json_object"},
    )

    raw = json.loads(response.choices[0].message.content)
    return TriageResult(**raw)


def main() -> None:
    parser = argparse.ArgumentParser(description="Security triage agent")
    parser.add_argument("--input", required=True, help="Path to JSON file with alerts")
    parser.add_argument("--dry-run", action="store_true", help="Skip LLM calls")
    parser.add_argument("--config", default="config/agent.yaml")
    parser.add_argument("--log-level", default=os.environ.get("TEST_LOG_LEVEL", "INFO"))
    args = parser.parse_args()

    logging.basicConfig(
        level=args.log_level,
        format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
    )

    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = Path(__file__).parent.parent / config_path

    config = load_config(config_path)
    model_name = config["model"]["name"]

    if args.dry_run:
        os.environ["DRY_RUN"] = "true"

    client = build_client(config)

    with open(args.input) as f:
        raw_alerts = json.load(f)

    results = []
    for raw in raw_alerts:
        alert = Alert(**raw)
        logger.info("Triaging alert %s: %s", alert.id, alert.rule_name)
        result = triage_alert(alert, client, model_name, dry_run=args.dry_run)
        results.append(result.model_dump(mode="json"))
        logger.info(
            "  → %s (score=%d): %s",
            result.decision,
            result.risk_score,
            result.reasoning[:80],
        )

    print(json.dumps(results, indent=2, default=str))


if __name__ == "__main__":
    main()
