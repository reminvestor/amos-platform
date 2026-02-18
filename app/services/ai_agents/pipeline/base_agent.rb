module AiAgents::Pipeline
  class BaseAgent
    attr_reader :agent_execution, :pipeline_execution, :workspace_manager

    def initialize(agent_execution)
      @agent_execution = agent_execution
      @pipeline_execution = agent_execution.pipeline_execution
      @workspace_manager = WorkspaceManager.new(pipeline_execution, agent_execution.agent_id)
    end

    # Main execution method - to be overridden by subclasses
    def execute!
      raise NotImplementedError, "Subclasses must implement execute!"
    end

    # Call LLM via BedrockService (default: Qwen3-Next-80B for cost efficiency)
    def call_claude(system_prompt, user_message, model: 'qwen3-next-80b', max_tokens: 4000, temperature: 0.7)
      bedrock_service = BedrockService.new(
        entity: pipeline_execution.entity
      )

      messages = [
        {
          role: 'user',
          content: user_message
        }
      ]

      result = bedrock_service.send_message(
        system_prompt,
        messages,
        model: model,
        max_tokens: max_tokens,
        temperature: temperature
      )

      # Record token usage
      if result[:usage]
        tokens = result[:usage][:input_tokens] + result[:usage][:output_tokens]
        cost = calculate_cost(model, result[:usage])
        agent_execution.record_tokens(tokens, cost)
      end

      result
    rescue => e
      Rails.logger.error "Claude API call failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Save artifact
    def save_artifact(artifact_type, file_name, content)
      artifact = pipeline_execution.pipeline_artifacts.create!(
        agent_execution: agent_execution,
        artifact_type: artifact_type,
        file_name: file_name,
        content: content,
        file_size: content.bytesize
      )

      agent_execution.append_log("Saved artifact: #{artifact_type} - #{file_name}")
      artifact
    end

    # Get artifact from previous agent
    def get_artifact(artifact_type)
      pipeline_execution.artifacts_of_type(artifact_type).last
    end

    # Log to agent execution
    def log(message)
      agent_execution.append_log(message)
      Rails.logger.info "[#{agent_execution.agent_id}] #{message}"
    end

    protected

    def calculate_cost(model, usage)
      input_tokens = usage[:input_tokens] || 0
      output_tokens = usage[:output_tokens] || 0

      case model
      when 'qwen3-next-80b'
        (input_tokens / 1_000_000.0 * 0.15) + (output_tokens / 1_000_000.0 * 1.20)
      when 'claude-sonnet-4-6', 'claude-sonnet-4-5', 'claude-3-5-sonnet'
        (input_tokens / 1_000_000.0 * 3.00) + (output_tokens / 1_000_000.0 * 15.00)
      when 'claude-opus-4-6', 'claude-opus-4-5'
        (input_tokens / 1_000_000.0 * 5.00) + (output_tokens / 1_000_000.0 * 25.00)
      when 'claude-haiku-4-5', 'claude-3-5-haiku', 'claude-3-haiku'
        (input_tokens / 1_000_000.0 * 1.00) + (output_tokens / 1_000_000.0 * 5.00)
      else
        0.0
      end
    end
  end
end
