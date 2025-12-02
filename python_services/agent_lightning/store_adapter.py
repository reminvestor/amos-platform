"""
Store Adapter for Agent Lightning

Reads training data from Rails PostgreSQL database and populates Agent Lightning's InMemoryLightningStore
"""

import asyncpg
from typing import List, Dict, Any, Optional
from datetime import datetime
import logging
from models import RailsTrace, RailsLlmCall, RailsToolExecution

logger = logging.getLogger(__name__)


class RailsStoreAdapter:
    """Adapter to read training data from Rails PostgreSQL and populate Agent Lightning store"""

    def __init__(self, database_url: str):
        self.database_url = database_url
        self.conn = None

    async def connect(self):
        """Establish database connection"""
        if not self.conn:
            self.conn = await asyncpg.connect(self.database_url)
            logger.info("✅ Connected to Rails database")
        return self.conn

    async def disconnect(self):
        """Close database connection"""
        if self.conn:
            await self.conn.close()
            self.conn = None
            logger.info("✅ Disconnected from Rails database")

    async def load_traces_for_training(
        self,
        entity_id: int,
        trace_ids: Optional[List[str]] = None,
        store: Optional[Any] = None
    ) -> Dict[str, Any]:
        """Load specified traces from Rails DB and populate Agent Lightning store"""

        await self.connect()

        try:
            # Fetch traces
            traces = await self._fetch_traces(entity_id, trace_ids)
            logger.info(f"Loaded {len(traces)} traces for entity {entity_id}")

            rollouts_created = 0
            spans_created = 0

            for trace_data in traces:
                trace = RailsTrace(**trace_data)

                # Convert trace to rollout
                await self._create_rollout(trace, store)
                rollouts_created += 1

                # Fetch and add LLM calls as spans
                llm_calls = await self._fetch_llm_calls(trace.trace_id)
                for llm_call_data in llm_calls:
                    llm_call = RailsLlmCall(**llm_call_data)
                    span = await self._create_span(trace.trace_id, 0, llm_call)
                    if store and span:
                        await store.add_span(trace.trace_id, 0, span)
                        spans_created += 1

                # Fetch and add tool executions as spans
                tool_execs = await self._fetch_tool_executions(trace.trace_id)
                for tool_data in tool_execs:
                    tool = RailsToolExecution(**tool_data)
                    span = await self._create_tool_span(trace.trace_id, 0, tool)
                    if store and span:
                        await store.add_span(trace.trace_id, 0, span)
                        spans_created += 1

            logger.info(f"Created {rollouts_created} rollouts with {spans_created} spans")

            return {
                "success": True,
                "rollouts_created": rollouts_created,
                "spans_created": spans_created,
                "traces_loaded": len(traces)
            }

        except Exception as e:
            logger.error(f"Failed to load traces: {e}")
            raise

    async def _fetch_traces(self, entity_id: int, trace_ids: Optional[List[str]] = None) -> List[Dict]:
        """Fetch traces from database"""

        if trace_ids:
            query = """
                SELECT *
                FROM agent_lightning_traces
                WHERE entity_id = $1
                  AND trace_id = ANY($2)
                  AND status = 'completed'
                  AND reward_signal IS NOT NULL
                ORDER BY created_at DESC
            """
            rows = await self.conn.fetch(query, entity_id, trace_ids)
        else:
            query = """
                SELECT *
                FROM agent_lightning_traces
                WHERE entity_id = $1
                  AND status = 'completed'
                  AND reward_signal IS NOT NULL
                ORDER BY created_at DESC
                LIMIT 100
            """
            rows = await self.conn.fetch(query, entity_id)

        return [dict(row) for row in rows]

    async def _fetch_llm_calls(self, trace_id: str) -> List[Dict]:
        """Fetch LLM calls for a trace"""
        query = """
            SELECT *
            FROM agent_llm_calls
            WHERE trace_id = $1
            ORDER BY called_at ASC
        """
        rows = await self.conn.fetch(query, trace_id)
        return [dict(row) for row in rows]

    async def _fetch_tool_executions(self, trace_id: str) -> List[Dict]:
        """Fetch tool executions for a trace"""
        query = """
            SELECT *
            FROM agent_tool_executions
            WHERE trace_id = $1
            ORDER BY started_at ASC
        """
        rows = await self.conn.fetch(query, trace_id)
        return [dict(row) for row in rows]

    async def _create_rollout(self, trace: RailsTrace, store: Optional[Any]):
        """Convert Rails trace to Agent Lightning rollout"""

        if not store:
            return None

        try:
            from agentlightning import RolloutConfig

            config = RolloutConfig(
                rollout_id=trace.trace_id,
                metadata={
                    "entity_id": trace.entity_id,
                    "workflow_type": trace.workflow_type,
                    "workflow_id": trace.workflow_execution_id,
                    "user_goal": trace.user_goal,
                    "success_rate": trace.success_rate,
                    "cost": trace.cost_estimate,
                    "tokens": trace.token_count
                }
            )

            rollout = await store.create_rollout(config)

            # Add reward signal
            if trace.reward_signal is not None:
                rollout.reward = trace.reward_signal

            logger.debug(f"Created rollout {trace.trace_id} with reward {trace.reward_signal}")
            return rollout

        except Exception as e:
            logger.warning(f"Could not create rollout from trace {trace.trace_id}: {e}")
            return None

    async def _create_span(self, rollout_id: str, attempt_id: int, llm_call: RailsLlmCall) -> Optional[Dict]:
        """Convert Rails LLM call to Agent Lightning span"""

        try:
            return {
                "name": llm_call.purpose or "llm_call",
                "start_time": llm_call.called_at.timestamp(),
                "end_time": llm_call.called_at.timestamp() + (llm_call.latency_ms / 1000.0),
                "status": llm_call.status,
                "metadata": {
                    "type": "llm_call",
                    "model": llm_call.model_id,
                    "input_tokens": llm_call.input_tokens,
                    "output_tokens": llm_call.output_tokens,
                    "cost": llm_call.cost_estimate,
                    "prompt_preview": llm_call.prompt_preview,
                    "response_preview": llm_call.response_preview
                }
            }
        except Exception as e:
            logger.warning(f"Could not create span from LLM call {llm_call.id}: {e}")
            return None

    async def _create_tool_span(self, rollout_id: str, attempt_id: int, tool: RailsToolExecution) -> Optional[Dict]:
        """Convert Rails tool execution to Agent Lightning span"""

        try:
            end_time = tool.completed_at.timestamp() if tool.completed_at else tool.started_at.timestamp()

            return {
                "name": f"tool:{tool.tool_name}",
                "start_time": tool.started_at.timestamp(),
                "end_time": end_time,
                "status": tool.status,
                "metadata": {
                    "type": "tool_execution",
                    "tool_name": tool.tool_name,
                    "duration_ms": tool.duration_ms,
                    "error": tool.error_message
                }
            }
        except Exception as e:
            logger.warning(f"Could not create tool span from tool execution {tool.id}: {e}")
            return None
