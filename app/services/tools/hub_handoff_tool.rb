# frozen_string_literal: true

module Tools
  # HubHandoffTool
  #
  # Allows agents to formally hand off work to humans through the Hub.
  # This creates a structured handoff with clear completed/needed items.
  #
  class HubHandoffTool < BaseTool
    # DEPRECATED: Hub handoffs are no longer used. Amos communicates directly with users.
    
    def self.metadata
      {
        name: "hub_handoff",
        description: "DEPRECATED - DO NOT USE. Use ask_user for getting user input instead.",
        category: "deprecated",
        input_schema: {
          type: "object",
          properties: {
            to_user_id: {
              type: "integer",
              description: "ID of the user to hand off to. If not provided, hands off to the user who started the task."
            },
            summary: {
              type: "string",
              description: "Brief summary of what you've done and what you need from them"
            },
            completed_items: {
              type: "array",
              items: { type: "string" },
              description: "List of things you've completed"
            },
            needed_items: {
              type: "array", 
              items: { type: "string" },
              description: "List of things you need from the human (decisions, approvals, information)"
            },
            next_steps: {
              type: "array",
              items: { type: "string" },
              description: "What you'll do after they provide input"
            },
            urgency: {
              type: "string",
              enum: ["low", "normal", "high", "critical"],
              default: "normal",
              description: "How urgent is this handoff"
            }
          },
          required: ["summary"]
        }
      }
    end

    def execute(args)
      agent = context[:agent_plugin] || context[:execution]&.agent_plugin
      execution = context[:execution]
      
      return error_response("No agent context available") unless agent

      # Find the user to hand off to
      to_user = if args["to_user_id"]
                  User.find_by(id: args["to_user_id"])
                else
                  execution&.user || user
                end

      return error_response("Could not determine user to hand off to") unless to_user

      handoff_service = Hub::HandoffService.new(entity: entity)

      result = handoff_service.request_handoff(
        from_agent: agent,
        to_user: to_user,
        summary: args["summary"],
        completed_items: args["completed_items"] || [],
        needed_items: args["needed_items"] || [],
        next_steps: args["next_steps"] || [],
        urgency: args["urgency"] || "normal",
        execution: execution
      )

      if result[:success]
        # Update execution status
        execution&.update!(status: 'waiting_for_input')

        {
          success: true,
          message: "Handoff request sent to #{to_user.name}. They'll see this in their Hub.",
          thread_id: result[:thread_id],
          awaiting_response: true
        }
      else
        error_response(result[:error] || "Failed to create handoff")
      end
    end

    private

    def error_response(message)
      { success: false, error: message }
    end
  end
end
