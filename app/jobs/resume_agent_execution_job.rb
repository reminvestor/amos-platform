# frozen_string_literal: true

# Job to resume an agent execution after receiving user input
# Uses the existing conversation context mechanism in StandardPluginExecutor
class ResumeAgentExecutionJob < ApplicationJob
  queue_as :agents

  def perform(execution_id, response_content, options = {})
    execution = AgentPluginExecution.find_by(id: execution_id)
    
    unless execution
      Rails.logger.error "ResumeAgentExecutionJob: Execution #{execution_id} not found"
      return
    end

    unless execution.status == 'waiting_for_input'
      Rails.logger.info "ResumeAgentExecutionJob: Execution #{execution_id} is not waiting for input (status: #{execution.status})"
      return
    end

    Rails.logger.info "🔄 Resuming agent execution #{execution_id} with user response"

    variable_name = options[:variable_name] || options['variable_name']
    skipped = options[:skipped] || options['skipped'] || false

    resume_execution(execution, response_content, variable_name, skipped: skipped)
  rescue => e
    Rails.logger.error "ResumeAgentExecutionJob failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    execution&.update(
      status: 'failed', 
      output_result: { error: true, message: "Failed to resume: #{e.message}" }
    )
  end

  private

  def resume_execution(execution, response_content, variable_name, skipped: false)
    # Update execution status back to running
    execution.update!(status: 'running')

    # Get the agent and context
    agent = execution.agent_plugin
    user = execution.user
    entity = agent.entity || user.entity

    # Get the session ID for broadcasting (stored in input_context)
    session_id = execution.input_context&.dig('session_id') || execution.input_context&.dig(:session_id)

    Rails.logger.info "🤖 Resuming agent #{agent.name} with user input for #{variable_name}"

    # Build the continuation prompt
    continuation_prompt = if skipped
      "The user has chosen to skip this question. Please continue with the best available approach or make a reasonable default decision."
    else
      "The user has provided the following information:\n\n**#{variable_name || 'Response'}**: #{response_content}\n\nPlease continue with the task using this information."
    end

    # Create executor context
    executor_context = {
      user: user,
      entity: entity,
      agent_plugin: agent,
      execution: execution,
      session_id: session_id,
      user_inputs: { variable_name => response_content }.compact
    }

    # Instantiate the executor
    executor = Agents::StandardPluginExecutor.new(
      role: agent.role,
      capabilities: agent.capabilities_definition['capabilities'] || [],
      system_prompt: agent.system_prompt,
      config: agent.model_config || {},
      context: executor_context
    )

    # Run the continuation
    result = executor.run(continuation_prompt)

    # Handle the result
    if result.is_a?(Hash)
      if result[:status] == 'suspended'
        # Agent needs more input - it will create another AgentInputRequest
        Rails.logger.info "⏸️ Agent suspended again for more input"
        execution.update!(status: 'waiting_for_input')
        return
      elsif result[:error]
        error_msg = result[:error_message] || result[:content] || "Unknown error"
        execution.update!(
          status: 'failed',
          output_result: { error: true, message: error_msg },
          completed_at: Time.current
        )
        broadcast_completion(session_id, execution, success: false, error: error_msg)
        return
      end
    end

    # Parse and store result
    parsed_result = parse_agent_result(result)
    
    execution.update!(
      status: 'completed',
      output_result: parsed_result,
      completed_at: Time.current
    )

    # Broadcast completion
    broadcast_completion(session_id, execution, success: true, result: parsed_result)
  end

  def parse_agent_result(result)
    return result if result.is_a?(Hash)
    return { content: result } if result.is_a?(String)
    
    # Try to parse JSON
    if result.is_a?(String)
      begin
        JSON.parse(result)
      rescue JSON::ParserError
        { content: result }
      end
    else
      { content: result.to_s }
    end
  end

  def broadcast_completion(session_id, execution, success:, result: nil, error: nil)
    return unless session_id.present?

    message = {
      type: 'agent_execution_completed',
      execution_id: execution.id,
      agent_name: execution.agent_plugin.name,
      status: success ? 'completed' : 'failed'
    }

    if success && result
      message[:result] = result
      message[:summary] = result['summary'] || result[:summary] if result.is_a?(Hash)
    elsif error
      message[:error] = error
    end

    ScoutChannel.broadcast_to(session_id, message)

    # Also broadcast a chat message if there's a summary
    if success && result.is_a?(Hash) && result['summary'].present?
      ScoutChannel.broadcast_to(session_id, {
        type: 'assistant_message',
        content: "✅ **#{execution.agent_plugin.name}** completed:\n\n#{result['summary']}"
      })
    end
  end
end

