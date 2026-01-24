# frozen_string_literal: true

module Tools
  class RespondToAgentTool < BaseTool
    # DEPRECATED: Agent responses are no longer used. Amos handles all tasks directly.
    
    def self.metadata
      {
        name: "respond_to_agent",
        description: "DEPRECATED - DO NOT USE. Agent responses have been removed. Amos now handles all communication directly.",
        category: "deprecated",
        input_schema: {
          type: "object",
          properties: {
            work_item_id: {
              type: "integer",
              description: "The ID of the work item containing the agent's question (from get_work_inbox)"
            },
            execution_id: {
              type: "integer",
              description: "The ID of the agent execution waiting for input (alternative to work_item_id)"
            },
            response: {
              type: "string",
              description: "The user's response or answer to the agent's question"
            }
          },
          required: ["response"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      work_item_id = get_arg(args, :work_item_id)
      execution_id = get_arg(args, :execution_id)
      response = get_arg(args, :response)

      return error_response("Response is required") if response.blank?

      begin
        # Find the execution and input request
        execution = nil
        input_request = nil
        work_item = nil

        if work_item_id.present?
          work_item = AgentWorkItem.find_by(id: work_item_id, user: @user, entity: @entity)
          return error_response("Work item not found or doesn't belong to you") unless work_item
          
          execution_id = work_item.asset_data&.dig('execution_id')
          input_request_id = work_item.asset_data&.dig('input_request_id')
          
          if input_request_id
            input_request = AgentInputRequest.find_by(id: input_request_id)
          end
        end

        if execution_id.present?
          execution = AgentPluginExecution.find_by(id: execution_id, user: @user)
          return error_response("Execution not found or doesn't belong to you") unless execution

          # Find the pending input request for this execution
          input_request ||= AgentInputRequest.where(agent_plugin_execution: execution, status: 'pending').first
        end

        return error_response("No pending input request found. The agent may have already received a response or timed out.") unless input_request
        return error_response("This request has already been answered.") if input_request.status == 'answered'

        agent_name = execution&.agent_plugin&.name || 'Agent'

        # Answer the input request
        input_request.answer!(response)
        Rails.logger.info "✅ Answered input request #{input_request.id} for execution #{execution.id}"

        # Mark work item as handled if we have one
        if work_item
          work_item.update!(
            requires_action: false,
            read: true,
            asset_data: work_item.asset_data.merge('response' => response, 'responded_at' => Time.current.iso8601)
          )
        end

        # Resume the execution by updating status and re-queuing the job
        if execution.status == 'waiting_for_input'
          execution.update!(status: 'running')
          
          # Re-queue the job to continue execution
          AgentPluginExecutionJob.perform_later(
            execution.id,
            execution.input_context['task'],
            {
              entity: @entity,
              user_id: @user.id,
              session_id: context[:session_id],
              resumed_with_input: response,
              previous_state: execution.output_data
            }
          )
          Rails.logger.info "🔄 Resumed execution #{execution.id} with user input"
        end

        # Broadcast update to the Tasks canvas
        if context[:session_id]
          ScoutChannel.broadcast_to(context[:session_id], {
            type: 'task_progress',
            task_id: execution.id,
            status: 'running',
            message: "Received your response, #{agent_name} is continuing...",
            progress: 60
          })
        end

        success_response(
          message: "Your response has been delivered to #{agent_name}. The agent will continue its work with your input.",
          execution_id: execution.id,
          agent_name: agent_name,
          response_delivered: true
        )

      rescue => e
        Rails.logger.error "Error responding to agent: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Failed to respond to agent: #{e.message}")
      end
    end
  end
end

