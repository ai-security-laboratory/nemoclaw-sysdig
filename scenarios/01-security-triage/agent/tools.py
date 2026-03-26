"""Tool definitions for the security triage agent.

Each tool is a function the agent can call during reasoning.
Tools that hit external services read credentials from environment variables.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta
from typing import Any

import httpx

# ---------------------------------------------------------------------------
# Tool: Container / pod metadata
# ---------------------------------------------------------------------------

def get_container_metadata(container_id: str) -> dict[str, Any]:
    """Fetch runtime metadata for a container (image, labels, owner workload).

    In production this calls the Sysdig API. In test/dry-run mode it returns
    mock data so the agent can run without live credentials.
    """
    token = os.environ.get("SYSDIG_SECURE_TOKEN")
    base_url = os.environ.get("SYSDIG_URL", "https://secure.sysdig.com")

    if not token or os.environ.get("DRY_RUN", "false").lower() == "true":
        return _mock_container_metadata(container_id)

    try:
        with httpx.Client(timeout=10) as client:
            resp = client.get(
                f"{base_url}/api/v1/activityAudit/containers/{container_id}",
                headers={"Authorization": f"Bearer {token}"},
            )
            resp.raise_for_status()
            return resp.json()
    except Exception as exc:
        return {"error": str(exc), "container_id": container_id}


def _mock_container_metadata(container_id: str) -> dict[str, Any]:
    return {
        "container_id": container_id,
        "image": "nginx:1.25",
        "labels": {"app": "web", "env": "prod"},
        "owner_workload": "deployment/web-frontend",
        "namespace": "production",
        "privileged": False,
        "read_only_root": True,
    }


# ---------------------------------------------------------------------------
# Tool: Related alerts (correlation)
# ---------------------------------------------------------------------------

_alert_store: list[dict[str, Any]] = []  # In-memory for demo; replace with real store


def get_related_alerts(
    container_id: str,
    namespace: str,
    window_seconds: int = 300,
) -> list[dict[str, Any]]:
    """Return alerts from the same container/namespace in the last N seconds."""
    cutoff = datetime.utcnow() - timedelta(seconds=window_seconds)
    return [
        a for a in _alert_store
        if (
            a.get("container_id") == container_id
            or a.get("namespace") == namespace
        )
        and datetime.fromisoformat(a["timestamp"]) >= cutoff
    ]


def register_alert(alert: dict[str, Any]) -> None:
    """Add an alert to the in-memory store for correlation."""
    _alert_store.append(alert)
    # Keep store bounded
    if len(_alert_store) > 10_000:
        _alert_store.pop(0)


# ---------------------------------------------------------------------------
# Tool: MITRE ATT&CK mapping
# ---------------------------------------------------------------------------

# Simplified static mapping — extend with full MITRE dataset as needed
_RULE_TO_MITRE: dict[str, list[str]] = {
    "Terminal shell in container": ["T1059 - Command and Scripting Interpreter"],
    "Sensitive file read": ["T1552 - Unsecured Credentials"],
    "Outbound connection to C2": ["T1071 - Application Layer Protocol"],
    "Privilege escalation detected": ["T1068 - Exploitation for Privilege Escalation"],
    "Crypto mining detected": ["T1496 - Resource Hijacking"],
    "Container escape attempt": ["T1611 - Escape to Host"],
    "Kubectl executed in container": ["T1609 - Container Administration Command"],
}


def map_to_mitre(rule_name: str) -> list[str]:
    """Return MITRE ATT&CK technique IDs for a given Sysdig rule name."""
    for pattern, tactics in _RULE_TO_MITRE.items():
        if pattern.lower() in rule_name.lower():
            return tactics
    return ["Unknown — manual review required"]


# ---------------------------------------------------------------------------
# Tool registry (for agent framework registration)
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "name": "get_container_metadata",
        "description": "Fetch runtime metadata for a container: image, labels, owner workload, privileges.",
        "function": get_container_metadata,
        "parameters": {
            "container_id": {"type": "string", "description": "The container ID from the alert"},
        },
    },
    {
        "name": "get_related_alerts",
        "description": "Find other alerts from the same container or namespace in a recent time window.",
        "function": get_related_alerts,
        "parameters": {
            "container_id": {"type": "string"},
            "namespace": {"type": "string"},
            "window_seconds": {"type": "integer", "default": 300},
        },
    },
    {
        "name": "map_to_mitre",
        "description": "Map a Sysdig rule name to relevant MITRE ATT&CK techniques.",
        "function": map_to_mitre,
        "parameters": {
            "rule_name": {"type": "string", "description": "The Sysdig rule that fired"},
        },
    },
]
