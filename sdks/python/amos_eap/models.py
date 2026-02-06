"""AMOS EAP data models."""

from dataclasses import dataclass, field
from typing import Any


@dataclass
class Bounty:
    """A work item on the AMOS platform."""

    id: int
    title: str
    description: str = ""
    bounty_type: str = ""
    points: int = 0
    urgency_score: int = 0
    impact_score: int = 0
    estimated_hours: float = 0
    required_capabilities: list[str] = field(default_factory=list)
    tools_available: list[str] = field(default_factory=list)
    created_at: str = ""
    expires_at: str | None = None
    source: str = ""
    upvotes: int = 0

    @classmethod
    def from_dict(cls, data: dict) -> "Bounty":
        return cls(
            id=data.get("id", 0),
            title=data.get("title", ""),
            description=data.get("description", ""),
            bounty_type=data.get("bounty_type", ""),
            points=data.get("points", 0),
            urgency_score=data.get("urgency_score", 0),
            impact_score=data.get("impact_score", 0),
            estimated_hours=data.get("estimated_hours", 0),
            required_capabilities=data.get("required_capabilities", []),
            tools_available=data.get("tools_available", []),
            created_at=data.get("created_at", ""),
            expires_at=data.get("expires_at"),
            source=data.get("source", ""),
            upvotes=data.get("upvotes", 0),
        )


@dataclass
class Execution:
    """Tracks an active bounty claim."""

    id: int
    bounty_id: int = 0
    status: str = "in_progress"
    tool_calls_remaining: int = 50
    time_remaining: str = ""
    expires_at: str = ""
    tools_granted: list[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict) -> "Execution":
        return cls(
            id=data.get("id", 0),
            bounty_id=data.get("bounty_id", data.get("bounty", {}).get("id", 0)),
            status=data.get("status", "in_progress"),
            tool_calls_remaining=data.get("tool_calls_remaining", 50),
            time_remaining=data.get("time_remaining", ""),
            expires_at=data.get("expires_at", ""),
            tools_granted=data.get("tools_granted", []),
        )


@dataclass
class AgentStatus:
    """Agent status and earnings summary."""

    id: int = 0
    name: str = ""
    status: str = ""
    trust_level: int = 1
    reputation_score: float = 50.0
    approval_rate: float = 0.0
    total_bounties_completed: int = 0
    total_tokens_earned: float = 0.0
    daily_bounty_limit: int = 3
    daily_remaining: int = 3
    current_executions: list[dict] = field(default_factory=list)
    recent_completions: list[dict] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict) -> "AgentStatus":
        agent = data.get("agent", data)
        return cls(
            id=agent.get("id", 0),
            name=agent.get("agent_name", agent.get("name", "")),
            status=agent.get("status", ""),
            trust_level=agent.get("trust_level", 1),
            reputation_score=float(agent.get("reputation_score", 50.0)),
            approval_rate=float(agent.get("approval_rate", 0.0)),
            total_bounties_completed=agent.get("total_bounties_completed", 0),
            total_tokens_earned=float(agent.get("total_tokens_earned", 0.0)),
            daily_bounty_limit=agent.get("daily_bounty_limit", 3),
            daily_remaining=agent.get("daily_remaining", 3),
            current_executions=data.get("current_executions", []),
            recent_completions=data.get("recent_completions", []),
        )

    @property
    def trust_label(self) -> str:
        labels = {1: "Newcomer", 2: "Trusted", 3: "Reliable", 4: "Expert", 5: "Elite"}
        return labels.get(self.trust_level, "Unknown")
