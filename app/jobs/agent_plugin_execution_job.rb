class AgentPluginExecutionJob < ApplicationJob
  queue_as :agents

  def perform(execution_id, task_description, context_data = {})
    execution = AgentPluginExecution.find(execution_id)
    agent_plugin = execution.agent_plugin
    user = execution.user

    Rails.logger.info "🤖 Executing AgentPlugin: #{agent_plugin.name} (ID: #{agent_plugin.id})"
    Rails.logger.info "   Task: #{task_description.truncate(100)}"

    begin
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
            # Broadcast the question to the chat
            ScoutChannel.broadcast_to(context_data[:session_id], {
              type: 'agent_question',
              agent_name: agent_plugin.name,
              execution_id: execution.id,
              question: question_text
            })

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

      # Broadcast completion to Scout if we have a session
      if context_data[:session_id]
        broadcast_completion(context_data[:session_id], agent_plugin, execution, result)
      end

      Rails.logger.info "✅ AgentPlugin #{agent_plugin.name} completed successfully"

    rescue => e
      Rails.logger.error "AgentPlugin execution failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")

      execution.mark_failed!(e.message)

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
    completion_message = "✅ #{agent_plugin.name} completed"
    
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
      elsif processed_result['message'].present? || processed_result[:message].present?
        completion_message = processed_result['message'] || processed_result[:message]
      end
    elsif processed_result.is_a?(String)
      # Heuristic: If it looks like our standard JSON format but failed to parse (e.g. truncation),
      # try to extract summary via regex
      if processed_result =~ /"summary":\s*"(.*?)"/
        completion_message = $1
      elsif processed_result.include?("\n---\n")
        # Heuristic: If string has a separator like '---', take the part before it as the summary
        parts = processed_result.split("\n---\n")
        completion_message = parts.first.strip if parts.first.length < 500 # Only if reasonable length
      elsif processed_result.include?("\n#")
        # If it starts with a header, maybe no summary before it? 
        # Or if there is text before the first header
        parts = processed_result.split("\n#", 2)
        if parts.first.present? && parts.first.length < 500
          completion_message = parts.first.strip
        end
      end
    end

    ScoutChannel.broadcast_to(session_id, {
      type: 'task_progress',
      job_id: execution.id,
      status: 'completed',
      agent_type: agent_plugin.slug,
      message: completion_message,
      result: result.is_a?(String) ? result.truncate(200) : result.to_s.truncate(200)
    })

    Rails.logger.info "📢 Broadcasting summary to chat: #{completion_message.truncate(50)}"
    
    # Broadcast conversational summary to the chat
    ScoutChannel.broadcast_to(session_id, {
      type: 'assistant_message',
      content: completion_message,
      metadata: {
        from_agent: true,
        agent_name: agent_plugin.name,
        execution_id: execution.id
      }
    })

      # Check for auto-load canvas on completion
    if agent_plugin.canvas_on_completion.present?
      Rails.logger.info "🎨 Auto-loading canvas: #{agent_plugin.canvas_on_completion}"
      
      # Parse result if it's JSON to extract useful IDs
      canvas_data = { 
        execution_id: execution.id,
        result: result
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
      
      parsed_result = nil
      if result.is_a?(String)
        # Try to parse main result
        if result.strip.start_with?('{')
          begin
            parsed_result = JSON.parse(result)
          rescue JSON::ParserError
            # Ignore
          end
        end
      elsif result.is_a?(Hash)
        parsed_result = result
      end

      if parsed_result
        # check top level
        ids = extract_ids.call(parsed_result)
        canvas_data.merge!(ids.compact)
        
        # Check nested 'content' if present (Universal Output format)
        if parsed_result['content'].present?
          content_data = parsed_result['content']
          
          # If content is string JSON, parse it
          if content_data.is_a?(String) && content_data.strip.start_with?('{')
             begin
               content_data = JSON.parse(content_data)
             rescue JSON::ParserError
             end
          end
          
          if content_data.is_a?(Hash)
            ids = extract_ids.call(content_data)
            canvas_data.merge!(ids.compact)
          end
        end
      end
      
      ScoutChannel.broadcast_to(session_id, {
        type: 'load_canvas',
        canvas_name: agent_plugin.canvas_on_completion,
        canvas_data: canvas_data
      })
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
end
