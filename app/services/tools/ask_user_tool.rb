module Tools
  class AskUserTool < BaseTool
    class ExecutionSuspended < StandardError; end

    def self.metadata
      {
        name: "ask_user",
        description: "Ask the user a question to get missing information or clarification. Use this when you need input to proceed.",
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

      Rails.logger.info "🗣️ Agent asking user: #{question}"
      
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
          created_at: input_request.created_at.iso8601
        }
        
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
      
      # Determine callback URL (web container in Docker, or localhost in dev)
      host = if ENV['DOCKER_ENV'] || File.exist?('/.dockerenv')
               'web:3000'
             else
               'localhost:3000'
             end
      
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

