# frozen_string_literal: true

# ContextGraphInstrumentable - Integrate context graph into agent execution
#
# This module is included in agent executors to capture decision traces
# as the article describes: "in the execution path at commit time"
#
# It provides:
# 1. Precedent injection into agent prompts
# 2. Automatic decision recording
# 3. Exception detection and tracking
# 4. Outcome recording
# 5. Task type tracking for Training-Free GRPO experience learning
#
module ContextGraphInstrumentable
  extend ActiveSupport::Concern

  # Get or create decision recorder for current context
  def decision_recorder
    @decision_recorder ||= begin
      entity = @entity || context&.dig(:entity)
      user = @user || context&.dig(:user)
      agent = @agent_plugin || @agent
      trace = @lightning_store&.trace

      return nil unless entity

      ContextGraph::DecisionRecorder.new(
        entity,
        user,
        agent_plugin: agent,
        lightning_trace: trace
      )
    end
  end

  # Inject precedent context into agent prompts
  def inject_precedent_context(prompt, task_description)
    return prompt unless decision_recorder
    return prompt if task_description.blank?

    precedent_summary = decision_recorder.precedent_summary_for_prompt(task_description)
    return prompt unless precedent_summary

    "#{prompt}\n\n#{precedent_summary}"
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to inject precedents: #{e.message}"
    prompt
  end

  # Record a tool execution as a decision
  # Includes task_type for Training-Free GRPO grouping
  def record_tool_decision(tool_name:, input:, output:, reasoning: nil, task_type: nil)
    return unless decision_recorder
    return unless should_record_decisions?

    decision_recorder.record_tool_decision!(
      tool_name: tool_name,
      tool_input: input,
      tool_output: output,
      reasoning: reasoning,
      task_type: task_type || current_task_type
    )
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to record tool decision: #{e.message}"
  end
  
  # Record a complete task interaction with outcome
  # This is the key data source for Training-Free GRPO semantic advantage extraction
  def record_task_interaction(
    task_type:,
    task_description:,
    outcome:,          # 'success' or 'failure'
    quality_score: nil,
    reasoning: nil,
    tools_used: [],
    context: {}
  )
    return unless decision_recorder
    return unless should_record_decisions?
    
    decision_recorder.record_decision!(
      decision_type: 'synthesis',
      summary: task_description.to_s.truncate(200),
      reasoning: reasoning || "Task completed with outcome: #{outcome}",
      context: context.merge(tools_used: tools_used),
      metadata: {
        task_type: task_type.to_s,
        outcome: outcome,
        quality_score: quality_score,
        tools_used: tools_used,
        recorded_for: 'experience_learning'
      }
    )
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to record task interaction: #{e.message}"
  end
  
  # Update an existing decision trace with outcome (after task completes)
  def record_task_outcome(decision_trace, outcome:, quality_score: nil, details: {})
    return unless decision_trace
    return unless decision_recorder
    
    decision_recorder.record_outcome!(
      decision_trace,
      outcome: outcome,
      quality: quality_score,
      details: details
    )
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to record task outcome: #{e.message}"
  end
  
  # Get current task type from context (for automatic inclusion in decisions)
  def current_task_type
    @current_task_type || context&.dig(:task_type) || 'general'
  end
  
  # Set current task type for this execution context
  def set_task_type(task_type)
    @current_task_type = task_type.to_s
  end

  # Record an agent delegation
  def record_delegation_decision(target_agent:, task:, reasoning:, context: {})
    return unless decision_recorder
    return unless should_record_decisions?

    decision_recorder.record_delegation!(
      target_agent: target_agent,
      task: task,
      reasoning: reasoning,
      context: context
    )
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to record delegation: #{e.message}"
  end

  # Record an escalation to human
  def record_escalation_decision(reason:, context: {}, escalated_to: nil)
    return unless decision_recorder
    return unless should_record_decisions?

    decision_recorder.record_escalation!(
      reason: reason,
      context: context,
      escalated_to: escalated_to
    )
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to record escalation: #{e.message}"
  end

  # Record an exception (when agent deviates from normal policy)
  def record_exception_decision(policy:, action_taken:, justification:, context: {}, precedent_ids: [])
    return unless decision_recorder
    return unless should_record_decisions?

    decision_recorder.record_exception!(
      policy: policy,
      action_taken: action_taken,
      justification: justification,
      context: context,
      precedent_ids: precedent_ids
    )
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to record exception: #{e.message}"
  end

  # Find precedents for current task
  def find_precedents(context_description, limit: 5)
    return [] unless decision_recorder

    decision_recorder.find_precedents(context_description, limit: limit)
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to find precedents: #{e.message}"
    []
  end

  # Find exception precedents
  def find_exception_precedents(context_description, limit: 5)
    return [] unless decision_recorder

    decision_recorder.find_exception_precedents(context_description, limit: limit)
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to find exception precedents: #{e.message}"
    []
  end

  # Check if we should record decisions
  def should_record_decisions?
    # Can be configured per entity or globally
    return false unless decision_recorder
    
    entity = @entity || context&.dig(:entity)
    return false unless entity
    
    # Check entity setting (default to true if not set)
    entity.settings&.dig('context_graph_enabled') != false
  rescue => e
    Rails.logger.debug "[ContextGraph] Config check failed: #{e.message}"
    false
  end

  # Detect if an action might be an exception to policy
  def detect_exception_indicators(response_text)
    exception_indicators = [
      /exception/i,
      /override/i,
      /special case/i,
      /deviation/i,
      /normally.*but/i,
      /policy.*however/i,
      /one-time/i,
      /unusual circumstances/i
    ]

    exception_indicators.any? { |pattern| response_text.match?(pattern) }
  end
end


