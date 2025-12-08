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

    # Update or create work item with completion result
    update_work_item_on_completion(execution, agent, parsed_result, session_id)

    # Broadcast completion
    broadcast_completion(session_id, execution, success: true, result: parsed_result)
  end
  
  def update_work_item_on_completion(execution, agent, result, session_id)
    # Find existing work item for this execution (created when question was asked)
    existing_work_item = AgentWorkItem.find_by(
      agent_plugin_execution: execution
    )
    
    if existing_work_item
      # Update the existing work item with completion info
      Rails.logger.info "📥 Updating work item #{existing_work_item.id} with completion result"
      
      summary = extract_summary(result)
      
      existing_work_item.update!(
        work_type: determine_work_type(agent, result),
        title: "#{agent.name} completed",
        summary: summary,
        details: result.is_a?(Hash) ? result.to_json : result.to_s,
        requires_action: false,
        metadata: existing_work_item.metadata.merge(
          completed_at: Time.current.iso8601,
          session_id: session_id,
          result_type: result.class.name
        )
      )
    else
      # Create a new completion work item
      Rails.logger.info "📥 Creating new work item for #{agent.name} completion"
      
      summary = extract_summary(result)
      work_type = determine_work_type(agent, result)
      asset_type, asset_id = extract_asset_info(result)
      
      AgentWorkItem.create!(
        entity: execution.agent_plugin.entity || execution.user.entity,
        user: execution.user,
        agent_plugin: agent,
        agent_plugin_execution: execution,
        work_type: work_type,
        title: "#{agent.name} completed",
        summary: summary,
        details: result.is_a?(Hash) ? result.to_json : result.to_s,
        asset_type: asset_type,
        asset_id: asset_id,
        priority: 'normal',
        requires_action: false,
        metadata: {
          session_id: session_id,
          completed_at: Time.current.iso8601
        }
      )
    end
  rescue => e
    Rails.logger.error "Failed to update/create work item: #{e.message}"
    # Don't fail the job if work item creation fails
  end
  
  def determine_work_type(agent, result)
    slug = agent.slug.to_s.downcase
    
    case slug
    when /landing_page/
      'landing_page_created'
    when /email/, /campaign/
      result.is_a?(Hash) && result[:sent] ? 'email_sent' : 'email_drafted'
    when /research/, /analyst/
      'research_completed'
    when /weather/
      'info_retrieved'
    when /report/
      'report_generated'
    else
      'task_completed'
    end
  end
  
  def extract_summary(result)
    return "Task completed." unless result.is_a?(Hash)
    
    # Try to find a summary in the result
    summary = result[:summary] || result[:message] || result['summary'] || result['message']
    return summary.to_s.truncate(300) if summary.present?
    
    # For landing pages
    if result[:landing_page_id] || result['landing_page_id']
      return "Landing page created successfully. Click to view and edit."
    end
    
    # For content with a title
    if result[:title] || result['title']
      return "Created: #{result[:title] || result['title']}"
    end
    
    # Check for content field
    if result[:content] || result['content']
      content = result[:content] || result['content']
      return content.to_s.truncate(200)
    end
    
    "Task completed successfully."
  end
  
  def extract_asset_info(result)
    return [nil, nil] unless result.is_a?(Hash)
    
    # Landing page
    if result[:landing_page_id] || result['landing_page_id']
      return ['LandingPage', result[:landing_page_id] || result['landing_page_id']]
    end
    
    # Campaign
    if result[:campaign_id] || result['campaign_id']
      return ['Campaign', result[:campaign_id] || result['campaign_id']]
    end
    
    [nil, nil]
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

    # Broadcast via HTTP callback to ensure cross-process delivery
    if success
      agent_plugin = execution.agent_plugin
      completion_summary = result.is_a?(Hash) ? (result['summary'] || result[:summary]) : nil
      agent_icon = agent_plugin.respond_to?(:icon) && agent_plugin.icon.present? ? agent_plugin.icon : '🤖'
      
      completion_data = {
        id: "completion-#{execution.id}",
        agent_name: agent_plugin.name,
        agent_icon: agent_icon,
        message: completion_summary || "Task completed successfully!",
        execution_id: execution.id,
        completed_at: Time.current.iso8601
      }
      
      # Use HTTP callback for reliable cross-process delivery
      begin
        notify_completion_via_http(session_id, completion_data)
        Rails.logger.info "📬 Notified completion via HTTP callback"
      rescue => e
        Rails.logger.warn "⚠️ HTTP callback failed, falling back to ActionCable: #{e.message}"
        # Fallback to direct ActionCable
        ScoutChannel.broadcast_to(session_id, {
          type: 'question_queue_update',
          action: 'completed',
          completion: completion_data
        })
        ScoutChannel.broadcast_to(session_id, {
          type: 'work_item_notification',
          agent_name: agent_plugin.name,
          status: 'completed',
          summary: completion_summary,
          execution_id: execution.id
        })
      end
    elsif error
      # For failures, broadcast error message
      ScoutChannel.broadcast_to(session_id, {
        type: 'agent_execution_completed',
        execution_id: execution.id,
        agent_name: execution.agent_plugin.name,
        status: 'failed',
        error: error
      })
    end
  end
  
  def notify_completion_via_http(session_id, completion_data)
    require 'net/http'
    require 'uri'
    
    # Determine the host based on environment
    host = if ENV['DOCKER_ENV'] || File.exist?('/.dockerenv')
             'web:3000'
           else
             'localhost:3000'
           end
    
    callback_url = "http://#{host}/scout/broadcast_completion"
    
    uri = URI.parse(callback_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 5
    
    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = {
      session_id: session_id,
      completion: completion_data
    }.to_json
    
    response = http.request(request)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "HTTP callback failed with status #{response.code}: #{response.body}"
    end
    
    Rails.logger.info "📡 HTTP callback successful to #{callback_url}"
  end
end

