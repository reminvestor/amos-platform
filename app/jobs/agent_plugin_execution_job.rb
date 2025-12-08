class AgentPluginExecutionJob < ApplicationJob
  queue_as :agents

  def perform(execution_id, task_description, context_data = {})
    execution = AgentPluginExecution.find(execution_id)
    agent_plugin = execution.agent_plugin
    user = execution.user

    Rails.logger.info "🤖 Executing AgentPlugin: #{agent_plugin.name} (ID: #{agent_plugin.id})"
    Rails.logger.info "   Task: #{task_description.truncate(100)}"

    # Initialize energy tracker for collaboration system
    @energy_tracker = Collaboration::EnergyTracker.new(agent_plugin)

    begin
      # Track execution start
      @energy_tracker.on_execution_start(execution)

      # Instantiate the agent with full context
      agent = agent_plugin.instantiate(
        entity: context_data[:entity] || user.entity,
        user: user,
        session_id: context_data[:session_id],
        execution: execution,
        config: context_data[:additional_context] || {}
      )

      # Execute the agent with the task
      result = agent.run(task_description, context_data)

      # Check if execution was suspended (waiting for input)
      if result.is_a?(Hash)
        if result[:status] == 'suspended'
          Rails.logger.info "⏸️ AgentPlugin #{agent_plugin.name} suspended: #{result[:content]}"
          
          # Fetch the actual question from the input request
          input_request = execution.agent_input_requests.pending.order(created_at: :desc).first
          question_text = input_request&.question || "Waiting for input..."
          
          # Broadcast suspension to Scout if we have a session
          if context_data[:session_id]
            # Note: agent_question is already broadcast by AskUserTool when creating the input request
            # We only need to update the task progress here to avoid duplicate questions in chat
            
            # Update task monitor
            ScoutChannel.broadcast_to(context_data[:session_id], {
              type: 'task_progress',
              job_id: execution.id,
              status: 'waiting_for_input',
              agent_type: agent_plugin.slug,
              message: "❓ #{agent_plugin.name} is asking a question...",
              progress: 50
            })
          end
          
          return # Exit without marking completed
        elsif result[:error]
          # Handle explicit error returned by executor
          raise StandardError, result[:error_message] || result[:content] || "Unknown execution error"
        end
      end

      # Mark execution as completed with the result
      execution.mark_completed!(
        output: result,
        result_data: {
          task: task_description,
          completed_at: Time.current
        }
      )

      # Track successful completion - earn energy
      @energy_tracker.on_execution_complete(execution, result)

      # Create work item for the completed task
      create_completion_work_item(execution, agent_plugin, task_description, result, context_data)

      # Broadcast completion to Scout if we have a session
      if context_data[:session_id]
        broadcast_completion(context_data[:session_id], agent_plugin, execution, result)
      end

      Rails.logger.info "✅ AgentPlugin #{agent_plugin.name} completed successfully"

    rescue => e
      Rails.logger.error "AgentPlugin execution failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")

      execution.mark_failed!(e.message)

      # Track failure - penalize energy
      @energy_tracker.on_execution_failed(execution, e)

      # Broadcast failure to Scout if we have a session
      if context_data[:session_id]
        broadcast_failure(context_data[:session_id], agent_plugin, execution, e)
      end

      raise
    end
  end

  private

  def broadcast_completion(session_id, agent_plugin, execution, result)
    ScoutChannel.broadcast_to(session_id, {
      type: 'agent_plugin_completed',
      execution_id: execution.id,
      agent_name: agent_plugin.name,
      result: result.is_a?(String) ? result : result.to_s,
      duration_ms: execution.duration_ms,
      tokens_used: execution.tokens_used
    })

    # Also broadcast task progress update
    # Extract meaningful completion message from result
    completion_message = nil
    has_meaningful_summary = false
    
    # Process result to extract summary if possible
    processed_result = result
    
    if result.is_a?(String)
      # Try to parse as JSON first
      if result.strip.start_with?('{')
        begin
          processed_result = JSON.parse(result)
        rescue JSON::ParserError
          # Keep as string
        end
      end
    end
    
    # If result is a Hash (or parsed JSON), check for a summary/message for the chat
    if processed_result.is_a?(Hash)
      if processed_result['summary'].present? || processed_result[:summary].present?
        completion_message = processed_result['summary'] || processed_result[:summary]
        has_meaningful_summary = true
      elsif processed_result['message'].present? || processed_result[:message].present?
        completion_message = processed_result['message'] || processed_result[:message]
        has_meaningful_summary = true
      end
    elsif processed_result.is_a?(String)
      # Heuristic: If it looks like our standard JSON format but failed to parse (e.g. truncation),
      # try to extract summary via regex
      if processed_result =~ /"summary":\s*"(.*?)"/
        completion_message = $1
        has_meaningful_summary = true
      elsif processed_result.include?("\n---\n")
        # Heuristic: If string has a separator like '---', take the part before it as the summary
        parts = processed_result.split("\n---\n")
        if parts.first.length < 500
          completion_message = parts.first.strip
          has_meaningful_summary = true
        end
      elsif processed_result.include?("\n#")
        parts = processed_result.split("\n#", 2)
        if parts.first.present? && parts.first.length < 500
          completion_message = parts.first.strip
          has_meaningful_summary = true
        end
      end
    end
    
    # Default message for task progress (but NOT for chat)
    progress_message = completion_message || "#{agent_plugin.name} finished"

    ScoutChannel.broadcast_to(session_id, {
      type: 'task_progress',
      job_id: execution.id,
      status: 'completed',
      agent_type: agent_plugin.slug,
      message: progress_message,
      result: result.is_a?(String) ? result.truncate(200) : result.to_s.truncate(200)
    })

    # Broadcast work item notification and question queue update via HTTP callback
    # This ensures cross-process delivery from worker to web server
    Rails.logger.info "📢 Broadcasting completion notification for #{agent_plugin.name}"
    
    agent_icon = agent_plugin.respond_to?(:icon) && agent_plugin.icon.present? ? agent_plugin.icon : '🤖'
    completion_data = {
      id: "completion-#{execution.id}",
      agent_name: agent_plugin.name,
      agent_icon: agent_icon,
      message: has_meaningful_summary ? completion_message : "Task completed successfully!",
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
        type: 'work_item_notification',
        agent_name: agent_plugin.name,
        status: 'completed',
        summary: has_meaningful_summary ? completion_message : nil,
        execution_id: execution.id
      })
      
      ScoutChannel.broadcast_to(session_id, {
        type: 'question_queue_update',
        action: 'completed',
        completion: completion_data
      })
    end

    # Determine canvas to load
    # Priority: 1) Agent's configured canvas, 2) Default based on content type
    canvas_name = agent_plugin.canvas_on_completion
    canvas_name = nil if canvas_name.blank? # Treat empty string as nil
    
    Rails.logger.info "🎨 [broadcast_completion] Agent canvas_on_completion: #{canvas_name.inspect}"
    Rails.logger.info "🎨 [broadcast_completion] Result type: #{result.class}, length: #{result.to_s.length}"
    
    # Parse result to determine content and appropriate canvas
    parsed_result = nil
    if result.is_a?(String)
      if result.strip.start_with?('{')
        begin
          parsed_result = JSON.parse(result)
        rescue JSON::ParserError
          # Keep as string
        end
      end
    elsif result.is_a?(Hash)
      parsed_result = result
    end
    
    # Extract content for canvas display
    content_for_canvas = nil
    content_format = 'markdown'
    
    if parsed_result.is_a?(Hash)
      content_for_canvas = parsed_result['content'] || parsed_result[:content]
      content_format = parsed_result['format'] || parsed_result[:format] || 'markdown'
    elsif result.is_a?(String) && result.length > 200
      content_for_canvas = result
    end
    
    Rails.logger.info "🎨 [broadcast_completion] Parsed result type: #{parsed_result.class}"
    Rails.logger.info "🎨 [broadcast_completion] Content for canvas present: #{content_for_canvas.present?}, length: #{content_for_canvas.to_s.length}"
    
    # If no canvas specified but we have substantial content, use dynamic_canvas
    if canvas_name.blank? && content_for_canvas.present?
      canvas_name = 'dynamic_canvas'
      Rails.logger.info "🎨 No canvas configured, defaulting to dynamic_canvas for content display"
    elsif canvas_name.blank? && result.to_s.length > 500
      # Fallback: if we have a long result string but couldn't extract content, still show it
      canvas_name = 'dynamic_canvas'
      content_for_canvas = result.to_s
      Rails.logger.info "🎨 No canvas configured, using raw result for dynamic_canvas (length: #{result.to_s.length})"
    end
    
    if canvas_name.present?
      Rails.logger.info "🎨 Auto-loading canvas: #{canvas_name}"
      
      # Build canvas data
      canvas_data = { 
        execution_id: execution.id,
        agent_name: agent_plugin.name,
        title: "#{agent_plugin.name} Results"
      }
      
      # Helper to extract IDs from a hash
      extract_ids = ->(data) {
        ids = {}
        if data.is_a?(Hash)
          ids[:landing_page_id] = data['id'] || data[:id] || data['landing_page_id'] || data[:landing_page_id]
          ids[:campaign_id] = data['campaign_id'] || data[:campaign_id]
        end
        ids
      }

      if parsed_result
        # Check top level for IDs
        ids = extract_ids.call(parsed_result)
        canvas_data.merge!(ids.compact)
        
        # For dynamic_canvas, include the content
        if canvas_name == 'dynamic_canvas'
          canvas_data[:content] = content_for_canvas
          canvas_data[:format] = content_format
          canvas_data[:title] = parsed_result['title'] || parsed_result[:title] || "#{agent_plugin.name} Results"
        end
        
        # Check nested 'content' if present (Universal Output format)
        if parsed_result['content'].present? && parsed_result['content'].is_a?(String)
          content_data = parsed_result['content']
          
          # If content is string JSON, parse it
          if content_data.strip.start_with?('{')
             begin
               content_data = JSON.parse(content_data)
               if content_data.is_a?(Hash)
                 ids = extract_ids.call(content_data)
                 canvas_data.merge!(ids.compact)
               end
             rescue JSON::ParserError
               # Content is not JSON, use as-is
             end
          end
        end
      end
      
      ScoutChannel.broadcast_to(session_id, {
        type: 'load_canvas',
        canvas_name: canvas_name,
        canvas_data: canvas_data
      })
    else
      Rails.logger.info "⚠️ No canvas to load - agent has no canvas_on_completion and result has no substantial content"
    end
  end

  def broadcast_failure(session_id, agent_plugin, execution, error)
    ScoutChannel.broadcast_to(session_id, {
      type: 'agent_plugin_failed',
      execution_id: execution.id,
      agent_name: agent_plugin.name,
      error: error.message
    })

    # Also broadcast task progress update
    ScoutChannel.broadcast_to(session_id, {
      type: 'task_progress',
      job_id: execution.id,
      status: 'failed',
      agent_type: agent_plugin.slug,
      message: "❌ #{agent_plugin.name} failed: #{error.message}"
    })
  end

  def create_completion_work_item(execution, agent_plugin, task_description, result, context_data)
    # Check if a work item was already created by a tool during this execution
    # (e.g., generate_excel creates a work item with download_url in metadata)
    existing_work_item = AgentWorkItem.where(
      user: execution.user,
      entity: execution.agent_plugin.entity || execution.user.entity
    ).where("created_at >= ?", execution.created_at)
     .where("metadata->>'download_url' IS NOT NULL")
     .order(created_at: :desc)
     .first
    
    if existing_work_item
      # Update the existing work item with completion info
      Rails.logger.info "📥 Found existing work item #{existing_work_item.id} with download_url, updating with completion info"
      
      existing_work_item.update!(
        title: "#{agent_plugin.name} completed",
        agent_plugin: agent_plugin,
        agent_plugin_execution: execution,
        details: result.is_a?(Hash) ? result.to_json : result.to_s,
        metadata: existing_work_item.metadata.merge(
          task_description: task_description,
          session_id: context_data[:session_id],
          duration_ms: execution.duration_ms,
          tokens_used: execution.tokens_used
        )
      )
      return
    end
    
    # Extract useful info from the result
    work_type = determine_work_type(agent_plugin, result)
    title = "#{agent_plugin.name} completed"
    summary = extract_summary(result, task_description)
    
    # Get asset info if available (e.g., landing page ID)
    asset_type, asset_id, asset_data = extract_asset_info(result)
    
    # Create the work item
    begin
      work_item = AgentWorkItem.create!(
        entity: execution.agent_plugin.entity || execution.user.entity,
        user: execution.user,
        agent_plugin: agent_plugin,
        agent_plugin_execution: execution,
        work_type: work_type,
        title: title,
        summary: summary,
        details: result.is_a?(Hash) ? result.to_json : result.to_s,
        asset_type: asset_type,
        asset_id: asset_id,
        asset_data: asset_data || {},
        priority: 'normal',
        requires_action: false,
        metadata: {
          task_description: task_description,
          session_id: context_data[:session_id],
          duration_ms: execution.duration_ms,
          tokens_used: execution.tokens_used
        }
      )
      
      Rails.logger.info "📥 Created work item #{work_item.id} for #{agent_plugin.name} completion"
    rescue => e
      Rails.logger.error "Failed to create work item: #{e.message}"
      # Don't fail the job if work item creation fails
    end
  end

  def determine_work_type(agent_plugin, result)
    # Determine work type based on agent and result
    slug = agent_plugin.slug.to_s.downcase
    
    case slug
    when /landing_page/
      'landing_page_created'
    when /email/, /campaign/
      result.is_a?(Hash) && result[:sent] ? 'email_sent' : 'email_drafted'
    when /research/, /analyst/
      'research_completed'
    when /agent.*creator/, /architect/
      'agent_created'
    when /tool.*creator/
      'tool_created'
    when /visual/, /chart/, /graph/
      'visualization_created'
    when /report/
      'report_generated'
    when /analysis/, /analytics/
      'analysis_completed'
    else
      'task_completed'
    end
  end

  def extract_summary(result, task_description)
    # Try to extract a meaningful summary from the result
    if result.is_a?(Hash)
      # Look for common summary fields
      summary = result[:summary] || result[:message] || result['summary'] || result['message']
      return summary.to_s.truncate(300) if summary.present?
      
      # For landing pages
      if result[:landing_page_id] || result['landing_page_id']
        return "Landing page created successfully. Click to view and edit."
      end
      
      # For other results with a title
      if result[:title] || result['title']
        return "Created: #{result[:title] || result['title']}"
      end
    end
    
    # Default to task description
    "Completed: #{task_description.to_s.truncate(200)}"
  end

  def extract_asset_info(result)
    return [nil, nil, nil] unless result.is_a?(Hash)
    
    # Landing page
    if (lp_id = result[:landing_page_id] || result['landing_page_id'] || result[:id])
      if result[:preview_url] || result['preview_url']
        return [
          'LandingPage',
          lp_id,
          {
            preview_url: result[:preview_url] || result['preview_url'],
            edit_url: result[:edit_url] || result['edit_url'],
            title: result[:title] || result['title']
          }
        ]
      end
    end
    
    # Email/Campaign
    if result[:campaign_id] || result['campaign_id']
      return ['Campaign', result[:campaign_id] || result['campaign_id'], result.slice(:status, :recipients_count)]
    end
    
    # Generic asset
    if result[:asset_type] && result[:asset_id]
      return [result[:asset_type], result[:asset_id], result[:asset_data] || {}]
    end
    
    [nil, nil, nil]
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
    
    Rails.logger.info "📡 HTTP completion callback successful to #{callback_url}"
  end
end
