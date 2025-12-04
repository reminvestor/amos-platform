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

      # Ensure we have an execution context
      unless context[:execution]
        return error_response("Cannot ask user: No execution context found")
      end

      execution = context[:execution]

      # Create the input request
      input_request = AgentInputRequest.create!(
        agent_plugin_execution: execution,
        question: question,
        variable_name: variable_name,
        context_data: context_data,
        status: 'pending'
      )

      # Update execution status
      execution.update!(status: 'waiting_for_input')

      # Create a Work Item in the Work Inbox so user can respond
      agent_name = execution.agent_plugin&.name || 'Agent'
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

      # Notify via ActionCable - broadcast to session AND work inbox
      if context[:session_id]
        ScoutChannel.broadcast_to(context[:session_id], {
          type: 'agent_question',
          execution_id: execution.id,
          agent_name: agent_name,
          question: question,
          work_item_id: work_item.id
        })
      end

      # Raise suspension signal
      # This will be caught by the executor to save state and exit
      raise ExecutionSuspended, "Waiting for user input: #{question}"
    end
  end
end

