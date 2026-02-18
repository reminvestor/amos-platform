# frozen_string_literal: true

# ⚠️ DEPRECATED: LightningStoreService
#
# This service is deprecated in favor of the native notification system:
#
# - SystemNotificationService - Stores notifications and patterns
# - SystemNotification model - Persistent storage with read tracking
# - ExecutionLearningBridge - Records patterns to Energy System
#
# Trace storage is no longer needed because:
# 1. Capability updates happen in real-time via EnergyTracker
# 2. Pattern detection happens via ExecutionGuardService
# 3. Historical data is stored in SystemNotification
#
# This file will be removed in a future release.
#
# Agent Lightning store service for collecting and managing training data (DEPRECATED)
# This service instruments agent executions and stores traces for RL-based optimization
class LightningStoreService
  # @deprecated Use SystemNotificationService and ExecutionLearningBridge instead
  attr_reader :entity, :user, :trace

  def initialize(entity, user)
    @entity = entity
    @user = user
    @trace = nil
  end

  # Start recording a new trace for a workflow execution
  def start_workflow_trace(workflow_execution, task_session, request_text)
    @trace = AgentLightningTrace.create!(
      entity: entity,
      user: user,
      workflow_execution: workflow_execution,
      task_session: task_session,
      trace_id: SecureRandom.uuid,
      trace_type: "workflow",
      status: "pending",
      input_data: { request_text: request_text, timestamp: Time.current.to_i },
      started_at: Time.current,
      metadata: { workflow_id: workflow_execution.id }
    )
    @trace
  end

  # Record an LLM call
  def record_llm_call(
    model:,
    agent_role:,
    system_prompt:,
    user_messages:,
    response_content:,
    input_tokens:,
    output_tokens:,
    latency_ms:,
    status: "success",
    error_message: nil,
    parsed_actions: nil,
    success_score: nil
  )
    return unless @trace

    call = AgentLLMCall.create!(
      entity: entity,
      agent_lightning_trace: @trace,
      call_id: SecureRandom.uuid,
      model: model,
      agent_role: agent_role,
      system_prompt: system_prompt,
      user_messages: user_messages,
      response_content: response_content,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens,
      latency_ms: latency_ms,
      status: status,
      error_message: error_message,
      parsed_actions: parsed_actions,
      success_score: success_score,
      called_at: Time.current,
      cost: calculate_token_cost(model, input_tokens, output_tokens)
    )

    # Update trace with token and cost information
    @trace.update!(
      token_count: (@trace.token_count || 0) + call.total_tokens,
      cost_estimate: (@trace.cost_estimate || 0) + (call.cost || 0)
    )

    # Phase 3: Emit span to Agent Lightning in real-time
    emit_llm_call_span(call)

    Rails.logger.info "⚡ LLM call recorded successfully - call_id: #{call.call_id}, tokens: #{call.total_tokens}, cost: $#{call.cost}"
    call
  end

  # Record a tool execution
  def record_tool_execution(
    tool_name:,
    tool_category:,
    input_arguments:,
    output_result:,
    status: "success",
    execution_time_ms: 0,
    error_message: nil,
    result_met_expectations: nil,
    sequence_number: 0,
    llm_call: nil,
    parent_execution: nil
  )
    return unless @trace

    execution = AgentToolExecution.create!(
      entity: entity,
      agent_lightning_trace: @trace,
      agent_llm_call: llm_call,
      execution_id: SecureRandom.uuid,
      tool_name: tool_name,
      tool_category: tool_category,
      input_arguments: input_arguments,
      output_result: output_result,
      status: status,
      execution_time_ms: execution_time_ms,
      error_message: error_message,
      result_met_expectations: result_met_expectations,
      sequence_number: sequence_number,
      parent_tool_execution: parent_execution,
      started_at: Time.current,
      completed_at: status != "running" ? Time.current : nil
    )

    # Phase 3: Emit span to Agent Lightning in real-time
    emit_tool_execution_span(execution)

    execution
  end

  # Record a phase execution
  def record_phase_execution(
    phase_id:,
    phase_type:,
    workflow_execution:,
    phase_input:,
    status: "running",
    attempts: 1,
    duration_ms: 0,
    phase_output: {},
    success_criteria_met: nil,
    phase_success_score: nil,
    failure_reason: nil
  )
    return unless @trace

    phase_exec = AgentPhaseExecution.create!(
      entity: entity,
      workflow_execution: workflow_execution,
      agent_lightning_trace: @trace,
      phase_id: phase_id,
      phase_type: phase_type,
      status: status,
      attempts: attempts,
      duration_ms: duration_ms,
      phase_input: phase_input,
      phase_output: phase_output,
      met_success_criteria: success_criteria_met,
      phase_success_score: phase_success_score,
      failure_reason: failure_reason,
      started_at: Time.current,
      completed_at: (status == "success" || status == "failed") ? Time.current : nil
    )

    phase_exec
  end

  # Update phase execution
  def update_phase_execution(phase_execution, **attributes)
    phase_execution.update!(attributes)
    phase_execution
  end

  # Add an intermediate step to the trace
  def add_step(step_description:, status: "running", metadata: {})
    return unless @trace

    steps = @trace.intermediate_steps || []
    steps << {
      step: step_description,
      status: status,
      timestamp: Time.current.to_i,
      metadata: metadata
    }
    @trace.update!(intermediate_steps: steps)
  end

  # Complete the trace with results
  def complete_trace(output_data:, duration_ms: nil, status: "completed")
    return unless @trace

    @trace.update!(
      output_data: output_data,
      duration_ms: duration_ms || ((Time.current - @trace.started_at) * 1000).to_i,
      status: status,
      completed_at: Time.current
    )

    @trace
  end

  # Record a reward signal for the trace
  def record_reward(
    reward_type:,
    reward_value:,
    source: "automated",
    reason: nil,
    metadata: {}
  )
    # For benchmark rewards, we may not have a trace - create a standalone reward
    trace_to_use = @trace
    
    # If no trace, try to find a recent one or create a benchmark trace
    if trace_to_use.nil? && source == 'bob_benchmark'
      trace_to_use = find_or_create_benchmark_trace(metadata)
    end
    
    return unless trace_to_use

    reward = AgentReward.create!(
      entity: entity,
      agent_lightning_trace: trace_to_use,
      user: user,
      reward_type: reward_type,
      reward_value: reward_value.to_d,
      source: source,
      reason: reason,
      metadata: metadata,
      assigned_at: Time.current
    )

    # Update trace with highest reward signal
    if !trace_to_use.reward_signal || reward_value > trace_to_use.reward_signal
      trace_to_use.update!(reward_signal: reward_value.to_d, reward_source: source)
    end

    reward
  end

  # Find or create a trace for benchmark rewards
  def find_or_create_benchmark_trace(metadata)
    task_id = metadata[:task_id]
    
    # Try to find a recent trace for this task
    recent_trace = entity.agent_lightning_traces
      .where('created_at > ?', 1.hour.ago)
      .where("metadata->>'task_id' = ?", task_id.to_s)
      .order(created_at: :desc)
      .first
    
    return recent_trace if recent_trace

    # Create a new trace for this benchmark task
    AgentLightningTrace.create!(
      entity: entity,
      user: user,
      trace_id: SecureRandom.uuid,
      trace_type: "benchmark",
      status: "completed",
      input_data: { task_id: task_id, task_name: metadata[:task_name] },
      output_data: { success: metadata[:success], grounded: metadata[:grounded] },
      started_at: Time.current,
      completed_at: Time.current,
      duration_ms: metadata[:elapsed_ms],
      metadata: metadata.except(:elapsed_ms)
    )
  end

  # Mark trace as ready for training
  def mark_training_ready
    return unless @trace
    @trace.mark_training_ready
  end

  # Get current trace
  def current_trace
    @trace
  end

  # Get Agent Lightning config for entity
  def get_config
    @config ||= entity.agent_lightning_config || create_default_config
  end

  # Create default config for entity
  def create_default_config
    AgentLightningConfig.create!(
      entity: entity,
      enabled: true,
      mode: "observing",
      training_strategy: "prompt_optimization",
      retrain_frequency_hours: 24,
      trace_retention_days: 90,
      min_traces_for_training: 100,
      optimization_targets: {
        "reduce_token_usage" => 0.3,
        "improve_success_rate" => 0.5,
        "reduce_latency" => 0.2
      },
      learning_parameters: {
        "learning_rate" => 0.001,
        "batch_size" => 32,
        "num_epochs" => 3
      }
    )
  end

  # Check if training should run
  def should_train?
    config = get_config
    config.should_retrain? && config.ready_for_training?
  end

  # Get training data for LLM optimization
  def get_training_data
    traces = entity.agent_lightning_traces
      .completed
      .with_reward
      .order(created_at: :desc)
      .limit(1000)

    traces.map do |trace|
      {
        trace_id: trace.trace_id,
        input: trace.input_data,
        output: trace.output_data,
        llm_calls: trace.agent_llm_calls.map(&:execution_summary),
        tool_executions: trace.agent_tool_executions.map(&:execution_summary),
        phase_executions: trace.agent_phase_executions.map(&:execution_summary),
        reward: trace.reward_signal,
        success_rate: trace.success_rate,
        total_cost: trace.total_cost,
        duration_ms: trace.duration_ms
      }
    end
  end

  # Phase 3: Emit LLM call as span to Agent Lightning service
  def emit_llm_call_span(llm_call)
    return unless @trace && PythonAgentLightningClient.available?

    begin
      span_data = {
        name: llm_call.agent_role || "llm_call",
        type: "llm_call",
        model: llm_call.model,
        input_tokens: llm_call.input_tokens,
        output_tokens: llm_call.output_tokens,
        total_tokens: llm_call.total_tokens,
        cost: llm_call.cost,
        latency_ms: llm_call.latency_ms,
        status: llm_call.status
      }

      PythonAgentLightningClient.add_span(
        @trace.trace_id,
        0,
        span_data
      )

      Rails.logger.debug("✅ Emitted LLM call span to Agent Lightning: #{llm_call.call_id}")
    rescue PythonAgentLightningClient::ServiceUnavailableError => e
      Rails.logger.warn("Could not emit LLM span - service unavailable: #{e.message}")
    rescue => e
      Rails.logger.warn("Error emitting LLM span: #{e.message}")
    end
  end

  # Phase 3: Emit tool execution as span to Agent Lightning service
  def emit_tool_execution_span(tool_execution)
    return unless @trace && PythonAgentLightningClient.available?

    begin
      span_data = {
        name: "tool:#{tool_execution.tool_name}",
        type: "tool_execution",
        tool_name: tool_execution.tool_name,
        tool_category: tool_execution.tool_category,
        duration_ms: tool_execution.execution_time_ms,
        status: tool_execution.status,
        error: tool_execution.error_message
      }

      PythonAgentLightningClient.add_span(
        @trace.trace_id,
        0,
        span_data
      )

      Rails.logger.debug("✅ Emitted tool span to Agent Lightning: #{tool_execution.execution_id}")
    rescue PythonAgentLightningClient::ServiceUnavailableError => e
      Rails.logger.warn("Could not emit tool span - service unavailable: #{e.message}")
    rescue => e
      Rails.logger.warn("Error emitting tool span: #{e.message}")
    end
  end

  # Calculate cost for LLM tokens (using Anthropic pricing)
  # Adjust these based on current Anthropic pricing
  def calculate_token_cost(model, input_tokens, output_tokens)
    case model
    when "claude-sonnet-4.6", "claude-sonnet-4.5"
      input_cost = input_tokens * (3.0 / 1_000_000)  # $3 per 1M input tokens
      output_cost = output_tokens * (15.0 / 1_000_000)  # $15 per 1M output tokens
      (input_cost + output_cost).round(8)
    when "claude-haiku-4.5"
      input_cost = input_tokens * (0.8 / 1_000_000)  # $0.80 per 1M input tokens
      output_cost = output_tokens * (4.0 / 1_000_000)  # $4 per 1M output tokens
      (input_cost + output_cost).round(8)
    else
      0
    end
  end
end
