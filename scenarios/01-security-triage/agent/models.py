"""Data models for the security triage agent."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class Severity(int, Enum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3
    CRITICAL = 4


class TriageDecision(str, Enum):
    AUTO_CLOSE = "auto_close"
    QUEUE = "queue"
    DRAFT_PLAYBOOK = "draft_playbook"
    ESCALATE = "escalate"


class Alert(BaseModel):
    id: str
    timestamp: datetime
    severity: Severity
    rule_name: str
    description: str
    container_id: str | None = None
    container_name: str | None = None
    namespace: str | None = None
    pod_name: str | None = None
    process_name: str | None = None
    process_cmdline: str | None = None
    user_name: str | None = None
    raw: dict[str, Any] = Field(default_factory=dict)


class EnrichedAlert(BaseModel):
    alert: Alert
    container_metadata: dict[str, Any] = Field(default_factory=dict)
    related_alerts: list[str] = Field(default_factory=list)
    mitre_tactics: list[str] = Field(default_factory=list)
    risk_score: int = Field(ge=0, le=100, default=0)
    risk_reasoning: str = ""


class TriageResult(BaseModel):
    alert_id: str
    decision: TriageDecision
    risk_score: int
    reasoning: str
    suggested_actions: list[str] = Field(default_factory=list)
    playbook: str | None = None
    escalation_target: str | None = None
    processed_at: datetime = Field(default_factory=datetime.utcnow)
