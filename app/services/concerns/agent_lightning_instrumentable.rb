# Module to instrument BedrockService for Agent Lightning training data collection
module AgentLightningInstrumentable
  extend ActiveSupport::Concern

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
    @lightning_store ||= if @entity && @user
      LightningStoreService.new(@entity, @user)
    else
      nil
    end
  end

  # Check if we should record traces
  def should_record_lightning_trace?
    return false unless @entity && @user
    config = lightning_store.get_config
    config.enabled?
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
end
