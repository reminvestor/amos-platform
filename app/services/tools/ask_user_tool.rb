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
      AgentInputRequest.create!(
        agent_plugin_execution: execution,
        question: question,
        variable_name: variable_name,
        context_data: context_data,
        status: 'pending'
      )

      # Update execution status
      execution.update!(status: 'waiting_for_input')

      # Notify via ActionCable
      if context[:session_id]
        ScoutChannel.broadcast_to(context[:session_id], {
          type: 'agent_question',
          execution_id: execution.id,
          agent_name: execution.agent_plugin.name,
          question: question
        })
      end

      # Raise suspension signal
      # This will be caught by the executor to save state and exit
      raise ExecutionSuspended, "Waiting for user input: #{question}"
    end
  end
end

