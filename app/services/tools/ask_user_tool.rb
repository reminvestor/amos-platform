module Tools
  class AskUserTool < BaseTool
    class ExecutionSuspended < StandardError; end

    def self.metadata
      {
        name: "ask_user",
        description: "Ask the user a question to get missing information or clarification. Use this when you need input to proceed. You can optionally show a preview panel with designs, schemas, or data for the user to review.",
        category: "communication",
        input_schema: {
          type: "object",
          properties: {
            question: {
              type: "string",
              description: "The question to ask the user"
            },
            variable_name: {
              type: "string",
              description: "The name of the variable you are trying to fill (optional)"
            },
            context: {
              type: "object",
              description: "Additional context about why this information is needed"
            },
            canvas_content: {
              type: "object",
              description: "Optional preview content to show alongside the question. Use this to show designs, schemas, field lists, or data for user review. Supported types: 'design_preview' (with fields array), 'module_preview' (with features/canvases/tools), 'data_table' (with headers/rows)."
            },
            canvas_title: {
              type: "string",
              description: "Title for the preview panel (e.g., 'Knowledge Base Schema', 'Module Design')"
            }
          },
          required: ["question"]
        }
      }
    end

    def execute(args)
      question = args["question"]
      variable_name = args["variable_name"]
      context_data = args["context"] || {}
      canvas_content = args["canvas_content"]
      canvas_title = args["canvas_title"]

      Rails.logger.info "🗣️ Agent asking user: #{question}"
      Rails.logger.info "🖼️ Canvas content provided: #{canvas_content.present?}" if canvas_content.present?
      
      # Handle both symbol and string keys (context may be serialized through job queue)
      session_id = context[:session_id] || context["session_id"]
      execution = context[:execution] || context["execution"]
      
      Rails.logger.info "🗣️ AskUserTool session_id: #{session_id.inspect}"
      Rails.logger.info "🗣️ AskUserTool full context keys: #{context.keys.inspect}"

      # Ensure we have an execution context
      unless execution
        return error_response("Cannot ask user: No execution context found")
      end

      # Get agent info for display
      agent_name = execution.agent_plugin&.name || 'Agent'
      agent_icon = execution.agent_plugin&.try(:icon) || '🤖'

      Rails.logger.info "🗣️ Creating AgentInputRequest with session_id: #{session_id.inspect}"

      # Create the input request with session for broadcasts
      input_request = AgentInputRequest.create!(
        agent_plugin_execution: execution,
        question: question,
        variable_name: variable_name,
        context_data: context_data,
        status: 'pending',
        session_id: session_id,
        agent_name: agent_name,
        agent_icon: agent_icon,
        priority: context_data['priority'] || 5, # Default medium priority
        expires_at: context_data['expires_in'] ? Time.current + context_data['expires_in'].to_i.minutes : nil
      )
      
      Rails.logger.info "🗣️ Created AgentInputRequest #{input_request.id} with session_id: #{input_request.session_id.inspect}"

      # Update execution status
      execution.update!(status: 'waiting_for_input')

      # Mark any existing unread work items for this execution as read (superseded by new question)
      existing_work_items = AgentWorkItem.where(
        agent_plugin_execution: execution,
        read: false,
        requires_action: true
      ).where.not(id: nil)
      
      if existing_work_items.any?
        existing_work_items.update_all(
          read: true,
          read_at: Time.current,
          requires_action: false
        )
        Rails.logger.info "📬 Marked #{existing_work_items.count} old work items as superseded"
      end

      # Create a Work Item in the Work Inbox so user can respond
      work_item = AgentWorkItem.create!(
        entity: entity,
        user: user,
        agent_plugin: execution.agent_plugin,
        agent_plugin_execution: execution,
        work_type: 'action_required',
        title: "#{agent_name} needs your input",
        summary: question.truncate(200),
        details: question,
        priority: 'high',
        requires_action: true,
        asset_data: {
          input_request_id: input_request.id,
          variable_name: variable_name,
          context: context_data,
          execution_id: execution.id
        }
      )
      Rails.logger.info "📬 Created work item #{work_item.id} for agent question"

      # Notify the user about the question
      # Use HTTP callback to web server since ActionCable from workers doesn't reach clients
      if session_id.present?
        question_data = {
          id: input_request.id,
          execution_id: execution.id,
          agent_name: agent_name,
          agent_icon: agent_icon,
          question: question,
          variable_name: variable_name,
          work_item_id: work_item.id,
          created_at: input_request.created_at.iso8601,
          canvas_content: canvas_content,
          canvas_title: canvas_title
        }.compact
        
        # Try HTTP callback first (more reliable from background workers)
        begin
          notify_via_http_callback(session_id, question_data)
          Rails.logger.info "📬 Notified question_queue_update via HTTP callback"
        rescue => e
          Rails.logger.warn "⚠️ HTTP callback failed, falling back to ActionCable: #{e.message}"
          # Fallback to direct ActionCable (works if Redis is properly configured)
          ScoutChannel.broadcast_to(session_id, {
            type: 'question_queue_update',
            action: 'added',
            question: question_data,
            pending_count: AgentInputRequest.pending.for_session(session_id).count
          })
          Rails.logger.info "📬 Broadcasted question_queue_update via ActionCable fallback"
        end
      end

      # Raise suspension signal
      # This will be caught by the executor to save state and exit
      raise ExecutionSuspended, "Waiting for user input: #{question}"
    end

    private

    def notify_via_http_callback(session_id, question_data)
      # Use HTTP callback to web server for reliable cross-process notification
      # This is more reliable than ActionCable from background workers
      
      require 'net/http'
      require 'uri'
      
      # Determine callback URL (container network or localhost)
      host = ContainerDetection.web_host
      
      callback_url = "http://#{host}/scout/broadcast_question"
      
      uri = URI.parse(callback_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 5
      
      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'
      request.body = {
        session_id: session_id,
        question: question_data,
        pending_count: AgentInputRequest.pending.for_session(session_id).count
      }.to_json
      
      response = http.request(request)
      
      unless response.is_a?(Net::HTTPSuccess)
        raise "HTTP callback failed with status #{response.code}: #{response.body}"
      end
      
      Rails.logger.info "📡 HTTP callback successful to #{callback_url}"
    end
  end
end

