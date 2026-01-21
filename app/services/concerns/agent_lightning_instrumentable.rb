# frozen_string_literal: true

# ⚠️ DEPRECATED: AgentLightningInstrumentable
#
# This module is deprecated in favor of ExecutionLearningBridge.
#
# The native learning stack now handles execution pattern recording:
# - ExecutionLearningBridge#record_successful_execution - for successful tool calls
# - ExecutionLearningBridge#record_unfulfilled_intent - for broken promises
# - ExecutionLearningBridge#record_execution_loop - for stuck loops
# - Collaboration::EnergyTracker#on_execution_complete - for capability updates
#
# To migrate: Include no new files. ExecutionLearningBridge is called
# automatically from ScoutGenericToolsServiceV2.
#
# This file will be removed in a future release.
#
# Module to instrument BedrockService for Agent Lightning training data collection (DEPRECATED)
module AgentLightningInstrumentable
  extend ActiveSupport::Concern
  # @deprecated Use ExecutionLearningBridge instead

  # Record an LLM call for Agent Lightning training
  def record_llm_call_to_lightning(
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
    return unless should_record_lightning_trace?

    lightning_store.record_llm_call(
      model: model,
      agent_role: agent_role,
      system_prompt: system_prompt,
      user_messages: user_messages,
      response_content: response_content,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      latency_ms: latency_ms,
      status: status,
      error_message: error_message,
      parsed_actions: parsed_actions,
      success_score: success_score
    )
  end

  # Get or create lightning store for current entity/user
  def lightning_store
    entity = @entity || context&.dig(:entity)
    user = @user || context&.dig(:user)
    
    @lightning_store ||= if entity && user
      LightningStoreService.new(entity, user)
    else
      nil
    end
  end

  # Check if we should record traces
  def should_record_lightning_trace?
    entity = @entity || context&.dig(:entity)
    user = @user || context&.dig(:user)
    
    return false unless entity && user
    return false unless lightning_store
    
    config = lightning_store.get_config
    config&.enabled? || false
  rescue => e
    Rails.logger.debug "Lightning trace check failed: #{e.message}"
    false
  end

  # Get agent role from context (can be overridden)
  def determine_agent_role(context = {})
    context[:agent_role] || "executor"
  end

  # Parse LLM response for actions (tool calls, decisions)
  def parse_response_actions(response_content)
    return nil unless response_content.is_a?(String)

    # Try to parse JSON actions if present
    begin
      if response_content.include?("[") && response_content.include?("]")
        json_match = response_content.match(/\[[\s\S]*?\]/)
        return JSON.parse(json_match[0]) if json_match
      end
    rescue JSON::ParserError
      # Not JSON, continue
    end

    nil
  end

  # Calculate success score based on response characteristics
  def calculate_success_score(response_content, status)
    return 0.0 if status != "success" || response_content.blank?

    score = 0.5  # Base score for successful response

    # Bonus for response length (indicates thoughtful response)
    score += 0.1 if response_content.length > 500
    score += 0.2 if response_content.length > 2000

    # Bonus for structured output
    score += 0.1 if (response_content.include?("{") && response_content.include?("}")) ||
                    (response_content.include?("[") && response_content.include?("]"))

    # Bonus for action descriptions
    score += 0.1 if response_content.downcase.include?("tool") ||
                    response_content.downcase.include?("action")

    [score, 1.0].min  # Cap at 1.0
  end

  # Record an agent execution (from StandardPluginExecutor)
  def record_agent_execution_to_lightning(
    agent_role:,
    prompt:,
    response:,
    duration_ms:,
    status:,
    tools_used: [],
    error_message: nil
  )
    return unless should_record_lightning_trace?

    # Record as a tool execution (agent execution is a type of tool use)
    lightning_store.record_tool_execution(
      tool_name: "agent_execution:#{agent_role}",
      tool_category: "agent",
      input_arguments: { prompt: prompt.to_s.truncate(2000), tools_available: tools_used },
      output_result: {
        response: response.to_s.truncate(5000),
        success: status == 'success',
        error: error_message
      }.compact,
      execution_time_ms: duration_ms,
      status: status,
      error_message: error_message
    )
  rescue => e
    Rails.logger.warn "Failed to record agent execution to Lightning: #{e.message}"
  end
end
