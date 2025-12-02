"""
Pydantic models for Rails database records

Maps Rails agent_lightning_* tables to Python Agent Lightning data structures
"""

from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime


class RailsTrace(BaseModel):
    """Maps to agent_lightning_traces table"""
    id: int
    entity_id: int
    trace_id: str
    workflow_execution_id: Optional[int] = None
    workflow_type: Optional[str] = None
    user_goal: Optional[str] = None
    status: str
    reward_signal: Optional[float] = None
    success_rate: Optional[float] = None
    cost_efficiency_score: Optional[float] = None
    user_rating: Optional[int] = None
    token_count: Optional[int] = None
    cost_estimate: Optional[float] = None
    duration_ms: Optional[int] = None
    created_at: datetime
    metadata: Optional[Dict[str, Any]] = {}

    class Config:
        from_attributes = True


class RailsLlmCall(BaseModel):
    """Maps to agent_llm_calls table"""
    id: int
    trace_id: str
    model_id: str
    purpose: Optional[str] = None
    input_tokens: int
    output_tokens: int
    total_tokens: int
    cost_estimate: float
    latency_ms: int
    status: str
    prompt_preview: Optional[str] = None
    response_preview: Optional[str] = None
    called_at: datetime
    metadata: Optional[Dict[str, Any]] = {}

    class Config:
        from_attributes = True


class RailsToolExecution(BaseModel):
    """Maps to agent_tool_executions table"""
    id: int
    trace_id: str
    tool_name: str
    status: str
    duration_ms: Optional[int] = None
    started_at: datetime
    completed_at: Optional[datetime] = None
    error_message: Optional[str] = None

    class Config:
        from_attributes = True
