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
    
    # Extract Hub context if present
    @hub_thread_id = options[:hub_thread_id] || options['hub_thread_id']
    @hub_message_id = options[:hub_message_id] || options['hub_message_id']
    @respond_in_hub = options[:respond_in_hub] || options['respond_in_hub']

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
        
        # If resuming in Hub context, post the question to Hub
        if @respond_in_hub && @hub_thread_id
          input_request = execution.agent_input_requests.pending.order(created_at: :desc).first
          question_text = input_request&.question || "Waiting for input..."
          post_question_to_hub(@hub_thread_id, agent, question_text, input_request)
        end
        
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
    
    # If resuming in Hub context, post the result to Hub
    if @respond_in_hub && @hub_thread_id
      respond_in_hub_thread(@hub_thread_id, agent, parsed_result)
    end
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
      asset_type, asset_id = extract_asset_info(result, execution)

      update_attrs = {
        work_type: determine_work_type(agent, result),
        title: "#{agent.name} completed",
        summary: summary,
        details: extract_details(result),
        requires_action: false,
        read: false,  # Reset to unread so completion shows as new notification
        metadata: existing_work_item.metadata.merge(
          completed_at: Time.current.iso8601,
          session_id: session_id,
          result_type: result.class.name
        )
      }

      # Update asset info if we found one (either from result or recently created)
      if asset_type.present? && asset_id.present?
        update_attrs[:asset_type] = asset_type
        update_attrs[:asset_id] = asset_id
        Rails.logger.info "📎 Linking work item to #{asset_type} #{asset_id}"
      end

      existing_work_item.update!(update_attrs)
    else
      # Create a new completion work item
      Rails.logger.info "📥 Creating new work item for #{agent.name} completion"

      summary = extract_summary(result)
      work_type = determine_work_type(agent, result)
      asset_type, asset_id = extract_asset_info(result, execution)
      
      AgentWorkItem.create!(
        entity: execution.agent_plugin.entity || execution.user.entity,
        user: execution.user,
        agent_plugin: agent,
        agent_plugin_execution: execution,
        work_type: work_type,
        title: "#{agent.name} completed",
        summary: summary,
        details: extract_details(result),
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

    # Try to find a summary directly in the result
    summary = result[:summary] || result[:message] || result['summary'] || result['message']
    return summary.to_s.truncate(300) if summary.present? && summary.is_a?(String)

    # Check for content field that might contain nested JSON with summary
    content = result[:content] || result['content']
    if content.is_a?(String) && content.start_with?('{')
      begin
        parsed_content = JSON.parse(content)
        nested_summary = parsed_content['summary'] || parsed_content[:summary]
        return nested_summary.to_s.truncate(300) if nested_summary.present?
      rescue JSON::ParserError
        # Not valid JSON, continue to other checks
      end
    end

    # For landing pages
    if result[:landing_page_id] || result['landing_page_id']
      return "Landing page created successfully. Click to view and edit."
    end

    # For content with a title
    if result[:title] || result['title']
      return "Created: #{result[:title] || result['title']}"
    end

    # Check for content field (plain text)
    if content.is_a?(String) && !content.start_with?('{')
      return content.truncate(200)
    end

    "Task completed successfully."
  end

  def extract_details(result)
    # Create human-readable details instead of raw JSON
    return "Task completed" if result.blank?

    if result.is_a?(Hash)
      # Check for content field that might contain the full output
      content = result[:content] || result['content']
      
      # If content is substantial markdown/text, use it directly (don't parse as JSON)
      if content.is_a?(String) && content.length > 100 && !content.start_with?('{')
        return content
      end
      
      lines = []

      # Check if content is nested JSON
      parsed_content = nil
      if content.is_a?(String) && content.start_with?('{')
        begin
          parsed_content = JSON.parse(content)
        rescue JSON::ParserError
          # Not valid JSON - treat as plain text
          return content if content.length > 100
        end
      end

      # Use parsed content if available, otherwise use result
      data = parsed_content || result

      # Add title if present
      if (title = data['title'] || data[:title] || result[:title] || result['title'])
        lines << "Title: #{title}"
      end

      # Add URLs if present
      if (preview_url = data['preview_url'] || data[:preview_url] || result[:preview_url] || result['preview_url'])
        lines << "Preview: #{preview_url}"
      end

      if (edit_url = data['edit_url'] || data[:edit_url] || result[:edit_url] || result['edit_url'])
        lines << "Edit: #{edit_url}"
      end

      # Add message/summary if present (from parsed content or result)
      message = data['summary'] || data[:summary] || data['message'] || data[:message] ||
                result[:message] || result['message'] || result[:summary] || result['summary']
      if message.is_a?(String) && message.present?
        lines << message unless lines.any? { |l| l.include?(message) }
      end

      # Add status if present
      if (status = data['status'] || data[:status] || result[:status] || result['status'])
        lines << "Status: #{status}" if status.is_a?(String)
      end
      
      # If we have content and it wasn't used yet, append it
      if content.is_a?(String) && content.present? && !lines.any? { |l| l.include?(content) }
        lines << content
      end

      return lines.join("\n\n") if lines.present?
    end

    # Return string representation if not a hash - no truncation
    result.to_s
  end

  def extract_asset_info(result, _execution = nil)
    return [nil, nil] unless result.is_a?(Hash)

    # Check for content field that might contain nested JSON
    content = result[:content] || result['content']
    parsed_content = nil
    if content.is_a?(String) && content.start_with?('{')
      begin
        parsed_content = JSON.parse(content)
      rescue JSON::ParserError
        # Not valid JSON
      end
    end

    # Use parsed content if available, otherwise use result
    data = parsed_content || result

    # Landing page
    landing_page_id = data['landing_page_id'] || data[:landing_page_id] ||
                      result[:landing_page_id] || result['landing_page_id']
    if landing_page_id.present?
      return ['LandingPage', landing_page_id]
    end

    # Campaign
    campaign_id = data['campaign_id'] || data[:campaign_id] ||
                  result[:campaign_id] || result['campaign_id']
    if campaign_id.present?
      return ['Campaign', campaign_id]
    end

    [nil, nil]
  end

  def parse_agent_result(result)
    return result if result.is_a?(Hash)

    # Try to parse JSON if it's a string
    if result.is_a?(String)
      begin
        parsed = JSON.parse(result)
        # Return parsed result if it's a Hash, otherwise wrap it
        parsed.is_a?(Hash) ? parsed.with_indifferent_access : { content: parsed }
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
    host = ContainerDetection.web_host
    
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
  
  def post_question_to_hub(hub_thread_id, agent_plugin, question_text, input_request = nil)
    thread = HubThread.find(hub_thread_id)
    
    # Create a Hub message for the agent's question
    message = thread.hub_messages.create!(
      sender: agent_plugin,
      content: question_text,
      message_type: 'text',
      needs_response: true,
      agent_input_request_id: input_request&.id
    )
    
    # Update thread activity
    thread.touch(:last_activity_at)
    thread.increment!(:message_count)
    
    # Broadcast the question to thread subscribers
    HubChannel.broadcast_to_thread(hub_thread_id, {
      type: 'new_message',
      message: {
        id: message.id,
        content: question_text,
        message_type: 'text',
        sender_id: agent_plugin.id,
        sender_type: 'AgentPlugin',
        sender_name: agent_plugin.name,
        needs_response: true,
        created_at: message.created_at.iso8601
      }
    })
    
    Rails.logger.info "❓ [Hub] #{agent_plugin.name} asked a follow-up question in thread #{hub_thread_id}"
  rescue => e
    Rails.logger.error "❌ [Hub] Failed to post question to thread: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")
  end

  def respond_in_hub_thread(hub_thread_id, agent_plugin, result)
    thread = HubThread.find(hub_thread_id)
    
    # Extract the response content from the result
    response_content = if result.is_a?(Hash)
      result[:content] || result['content'] ||
      result[:summary] || result[:message] || result['summary'] || result['message'] ||
      result[:output] || result['output'] ||
      result.to_json
    else
      result.to_s
    end
    
    # Don't send empty responses
    return if response_content.blank?
    
    # Add agent's response to the Hub thread
    message = thread.hub_messages.create!(
      sender: agent_plugin,
      content: response_content,
      message_type: 'text'
    )
    
    # Update thread activity
    thread.touch(:last_activity_at)
    thread.increment!(:message_count)
    
    # Broadcast the message to thread subscribers
    HubChannel.broadcast_to_thread(hub_thread_id, {
      type: 'new_message',
      message: {
        id: message.id,
        content: response_content,
        message_type: 'text',
        sender_id: agent_plugin.id,
        sender_type: 'AgentPlugin',
        sender_name: agent_plugin.name,
        created_at: message.created_at.iso8601
      }
    })
    
    Rails.logger.info "💬 [Hub] #{agent_plugin.name} responded in thread #{hub_thread_id} (#{response_content.length} chars)"
  rescue => e
    Rails.logger.error "❌ [Hub] Failed to respond in thread: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")
  end
end

