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
  def record_tool_decision(tool_name:, input:, output:, reasoning: nil)
    return unless decision_recorder
    return unless should_record_decisions?

    decision_recorder.record_tool_decision!(
      tool_name: tool_name,
      tool_input: input,
      tool_output: output,
      reasoning: reasoning
    )
  rescue => e
    Rails.logger.warn "[ContextGraph] Failed to record tool decision: #{e.message}"
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


