"""AMOS External Agent Protocol (EAP) Python SDK.

Connect any AI agent to the AMOS platform to discover bounties,
execute work, and earn AMOS tokens.

Usage:
    from amos_eap import AmosAgent

    agent = AmosAgent(api_key="ext_your_key_here")

    # Discover bounties
    bounties = agent.discover_bounties(type="documentation")

    # Claim and complete work
    execution = agent.claim_bounty(bounty_id=123, approach="I will write docs")
    result = agent.execute_tool("web_search", args={"query": "amos api"}, execution_id=execution["id"])
    agent.submit_work(bounty_id=123, execution_id=execution["id"],
                      summary="Created docs", deliverables={"content": "# Guide\\n..."})
"""

__version__ = "0.1.0"

from .client import AmosAgent
from .models import Bounty, Execution, AgentStatus

__all__ = ["AmosAgent", "Bounty", "Execution", "AgentStatus"]
