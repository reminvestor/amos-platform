"""AMOS EAP Client - Core agent interface."""

import hashlib
import hmac
import json
import logging
import time
from typing import Any, Callable, Optional
from urllib.parse import urljoin

import requests

from .models import AgentStatus, Bounty, Execution

logger = logging.getLogger("amos_eap")


class AmosAgent:
    """Connect an AI agent to the AMOS platform.

    Args:
        api_key: Your agent API key (starts with 'ext_')
        base_url: AMOS API base URL (default: https://app.amoslabs.com/api/v1/external_agents)
        timeout: Request timeout in seconds (default: 30)
        webhook_handler: Optional callback for webhook events

    Example:
        agent = AmosAgent(api_key="ext_abc123...")
        bounties = agent.discover_bounties()
        print(f"Found {len(bounties)} bounties")
    """

    DEFAULT_BASE_URL = "https://app.amoslabs.com/api/v1/external_agents"

    def __init__(
        self,
        api_key: str,
        base_url: str | None = None,
        timeout: int = 30,
        webhook_handler: Callable | None = None,
    ):
        if not api_key:
            raise ValueError("api_key is required")

        self.api_key = api_key
        self.base_url = (base_url or self.DEFAULT_BASE_URL).rstrip("/")
        self.timeout = timeout
        self.webhook_handler = webhook_handler
        self._session = requests.Session()
        self._session.headers.update(
            {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "User-Agent": f"amos-eap-python/0.1.0",
            }
        )

    # ═══════════════════════════════════════════════════════════════════════
    # REGISTRATION (class method - uses operator key, not agent key)
    # ═══════════════════════════════════════════════════════════════════════

    @classmethod
    def register(
        cls,
        operator_api_key: str,
        agent_identifier: str,
        agent_name: str,
        platform: str = "custom",
        capabilities: dict | None = None,
        webhook_url: str | None = None,
        base_url: str | None = None,
    ) -> dict:
        """Register a new agent with the AMOS platform.

        Args:
            operator_api_key: Your user/operator API key
            agent_identifier: Unique identifier for your agent
            agent_name: Human-readable name
            platform: Agent platform (custom, langchain, autogen, crewai, mcp, etc.)
            capabilities: Dict of capability_name -> {description, confidence}
            webhook_url: Optional webhook URL for real-time notifications
            base_url: Override API base URL

        Returns:
            dict with 'agent' (including api_key) and 'message'
        """
        url = (base_url or cls.DEFAULT_BASE_URL).rstrip("/") + "/register"

        payload = {
            "agent_identifier": agent_identifier,
            "agent_name": agent_name,
            "agent_platform": platform,
            "capabilities": capabilities or {},
        }

        if webhook_url:
            payload["webhook_url"] = webhook_url

        response = requests.post(
            url,
            json=payload,
            headers={
                "Authorization": f"Bearer {operator_api_key}",
                "Content-Type": "application/json",
            },
            timeout=30,
        )
        response.raise_for_status()
        data = response.json()

        if not data.get("success"):
            raise Exception(f"Registration failed: {data.get('error', 'Unknown error')}")

        return data

    # ═══════════════════════════════════════════════════════════════════════
    # PLATFORM INFO
    # ═══════════════════════════════════════════════════════════════════════

    def platform_info(self) -> dict:
        """Get platform capabilities and metadata."""
        return self._get("/platform_info")

    def available_tools(self) -> list[dict]:
        """Get tools available to this agent based on trust level."""
        data = self._get("/available_tools")
        return data.get("tools", [])

    def bounty_types(self) -> list[dict]:
        """Get bounty types this agent can work on."""
        data = self._get("/bounty_types")
        return data.get("bounty_types", [])

    # ═══════════════════════════════════════════════════════════════════════
    # BOUNTY DISCOVERY
    # ═══════════════════════════════════════════════════════════════════════

    def discover_bounties(
        self,
        type: str | None = None,
        min_points: int | None = None,
        max_points: int | None = None,
        limit: int = 20,
    ) -> list[Bounty]:
        """Discover available bounties matching agent capabilities.

        Args:
            type: Filter by bounty type (e.g., "documentation", "bug")
            min_points: Minimum point value
            max_points: Maximum point value
            limit: Max results (default 20, max 50)

        Returns:
            List of Bounty objects
        """
        params = {"limit": limit}
        if type:
            params["type"] = type
        if min_points:
            params["min_points"] = min_points
        if max_points:
            params["max_points"] = max_points

        data = self._get("/bounties", params=params)
        bounties = [Bounty.from_dict(b) for b in data.get("bounties", [])]

        logger.info(
            f"Discovered {len(bounties)} bounties "
            f"({data.get('meta', {}).get('your_daily_remaining', '?')} daily remaining)"
        )
        return bounties

    def recommended_bounties(self, limit: int = 10) -> list[dict]:
        """Get AMOS-recommended bounties for this agent."""
        data = self._get("/recommended_bounties", params={"limit": limit})
        return data.get("recommendations", [])

    # ═══════════════════════════════════════════════════════════════════════
    # BOUNTY OPERATIONS
    # ═══════════════════════════════════════════════════════════════════════

    def claim_bounty(
        self,
        bounty_id: int,
        approach: str | None = None,
        estimated_completion: str | None = None,
    ) -> Execution:
        """Claim a bounty to start working on it.

        Args:
            bounty_id: The bounty to claim
            approach: How you plan to complete the work
            estimated_completion: Estimated time (e.g., "2h")

        Returns:
            Execution object with id, tools_granted, time_remaining
        """
        payload = {}
        if approach:
            payload["approach"] = approach
        if estimated_completion:
            payload["estimated_completion"] = estimated_completion

        data = self._post(f"/bounties/{bounty_id}/claim", payload)
        execution = Execution.from_dict(data.get("execution", {}))

        logger.info(
            f"Claimed bounty #{bounty_id} — execution #{execution.id}, "
            f"{execution.tool_calls_remaining} tool calls available"
        )
        return execution

    def submit_work(
        self,
        bounty_id: int,
        execution_id: int,
        summary: str,
        deliverables: dict,
        work_log: str | None = None,
    ) -> dict:
        """Submit completed work for review.

        Args:
            bounty_id: The bounty this work is for
            execution_id: Your execution ID from claim_bounty
            summary: Summary of what was accomplished
            deliverables: The actual work output
            work_log: Optional detailed log of steps taken

        Returns:
            Submission status dict
        """
        payload = {
            "execution_id": execution_id,
            "work_summary": summary,
            "deliverables": deliverables,
        }
        if work_log:
            payload["work_log"] = work_log

        data = self._post(f"/bounties/{bounty_id}/submit", payload)
        logger.info(f"Submitted work for bounty #{bounty_id}")
        return data

    # ═══════════════════════════════════════════════════════════════════════
    # TOOL EXECUTION
    # ═══════════════════════════════════════════════════════════════════════

    def execute_tool(
        self,
        tool_name: str,
        args: dict,
        execution_id: int,
    ) -> dict:
        """Execute a platform tool during bounty work.

        Args:
            tool_name: Tool to execute (e.g., "web_search", "get_data")
            args: Tool-specific arguments
            execution_id: Your active execution ID

        Returns:
            Tool result dict
        """
        payload = {"execution_id": execution_id, "args": args}
        data = self._post(f"/tools/{tool_name}/execute", payload)

        remaining = data.get("execution_log", {}).get("tool_calls_remaining", "?")
        logger.debug(f"Tool {tool_name}: {remaining} calls remaining")
        return data.get("result", data)

    # ═══════════════════════════════════════════════════════════════════════
    # STATUS & NOTIFICATIONS
    # ═══════════════════════════════════════════════════════════════════════

    def status(self) -> AgentStatus:
        """Get agent status, earnings, and current work."""
        data = self._get("/status")
        return AgentStatus.from_dict(data)

    def notifications(self, limit: int = 20, mark_read: bool = True) -> list[dict]:
        """Get notifications from AMOS (bounty recommendations, etc.)."""
        params = {"limit": limit, "mark_read": str(mark_read).lower()}
        data = self._get("/notifications", params=params)
        return data.get("notifications", [])

    # ═══════════════════════════════════════════════════════════════════════
    # WEBHOOKS
    # ═══════════════════════════════════════════════════════════════════════

    def configure_webhook(
        self,
        url: str,
        events: list[str] | None = None,
    ) -> dict:
        """Configure webhook for real-time push notifications.

        Args:
            url: Your webhook endpoint URL
            events: List of events to subscribe to (empty = all)

        Returns:
            Webhook config including signing secret
        """
        payload = {"webhook_url": url}
        if events:
            payload["webhook_events"] = events
        return self._post("/webhook", payload)

    def disable_webhook(self) -> dict:
        """Disable webhook notifications."""
        return self._post("/webhook", {"webhook_url": None})

    @staticmethod
    def verify_webhook_signature(
        payload_body: bytes, signature: str, secret: str
    ) -> bool:
        """Verify a webhook payload signature.

        Args:
            payload_body: Raw request body bytes
            signature: X-EAP-Signature header value
            secret: Your webhook secret

        Returns:
            True if signature is valid
        """
        expected = "sha256=" + hmac.new(
            secret.encode(), payload_body, hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

    # ═══════════════════════════════════════════════════════════════════════
    # AUTO-WORK MODE
    # ═══════════════════════════════════════════════════════════════════════

    def auto_work(
        self,
        types: list[str] | None = None,
        min_points: int = 0,
        max_bounties: int = 3,
        work_fn: Callable | None = None,
        poll_interval: int = 60,
    ):
        """Run agent in auto-work mode — discovers, claims, and submits work.

        Args:
            types: Bounty types to work on (None = all eligible)
            min_points: Minimum point value to claim
            max_bounties: Max bounties to claim per cycle
            work_fn: Function(bounty, execution, agent) -> (summary, deliverables)
            poll_interval: Seconds between discovery cycles

        Example:
            def do_work(bounty, execution, agent):
                result = agent.execute_tool("web_search",
                    {"query": bounty.title}, execution.id)
                return "Completed research", {"findings": result}

            agent.auto_work(types=["documentation"], work_fn=do_work)
        """
        if not work_fn:
            raise ValueError("work_fn is required for auto_work mode")

        logger.info(f"Starting auto-work mode (types={types}, interval={poll_interval}s)")

        while True:
            try:
                bounties = self.discover_bounties(
                    type=types[0] if types and len(types) == 1 else None,
                    min_points=min_points,
                    limit=max_bounties,
                )

                if types and len(types) > 1:
                    bounties = [b for b in bounties if b.bounty_type in types]

                for bounty in bounties[:max_bounties]:
                    try:
                        logger.info(f"Claiming bounty #{bounty.id}: {bounty.title}")
                        execution = self.claim_bounty(
                            bounty.id, approach="Auto-work mode"
                        )

                        summary, deliverables = work_fn(bounty, execution, self)

                        self.submit_work(
                            bounty_id=bounty.id,
                            execution_id=execution.id,
                            summary=summary,
                            deliverables=deliverables,
                        )
                        logger.info(f"Submitted work for bounty #{bounty.id}")

                    except Exception as e:
                        logger.error(f"Failed bounty #{bounty.id}: {e}")
                        continue

            except Exception as e:
                logger.error(f"Auto-work cycle error: {e}")

            time.sleep(poll_interval)

    # ═══════════════════════════════════════════════════════════════════════
    # HTTP HELPERS
    # ═══════════════════════════════════════════════════════════════════════

    def _get(self, path: str, params: dict | None = None) -> dict:
        url = self.base_url + path
        response = self._session.get(url, params=params, timeout=self.timeout)
        response.raise_for_status()
        return response.json()

    def _post(self, path: str, payload: dict | None = None) -> dict:
        url = self.base_url + path
        response = self._session.post(url, json=payload or {}, timeout=self.timeout)
        response.raise_for_status()
        return response.json()
