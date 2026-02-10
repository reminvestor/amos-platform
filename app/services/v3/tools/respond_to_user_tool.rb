# frozen_string_literal: true

module V3
  module Tools
    # RespondToUserTool - The explicit "just talk" escape hatch
    #
    # When tool_choice is set to { any: {} }, the model MUST call a tool.
    # This tool is the escape hatch for conversational responses where
    # no platform action is needed. Instead of returning bare text,
    # the model calls respond_to_user with its message.
    #
    # The agent loop intercepts this tool and streams the message
    # as regular chat content — the user never sees the tool call.
    #
    class RespondToUserTool < ::Tools::BaseTool
      def self.metadata
        {
          name: "respond_to_user",
          description: <<~DESC.strip,
            Send text to the user. By default this ENDS your turn (final: true).
            Set final: false to send a message and keep working (e.g., "Let me look into that...").
            Use other tools first if you need to look anything up before your final response.
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "The text message to send to the user. Supports markdown formatting."
              },
              final: {
                type: "boolean",
                description: "Set false to keep working after sending this message. Default true (ends turn)."
              },
              canvas_name: {
                type: "string",
                description: "Optional: open a canvas alongside the message (e.g., 'dashboard', 'contact_viewer')"
              },
              canvas_data: {
                type: "object",
                description: "Optional: data to pass to the canvas",
                additionalProperties: true
              }
            },
            required: ["message"]
          }
        }
      end

      def execute(args)
        message = args["message"] || args[:message] || ""
        canvas_name = args["canvas_name"] || args[:canvas_name]
        canvas_data = args["canvas_data"] || args[:canvas_data] || {}

        result = { success: true, message: message }
        result[:canvas_name] = canvas_name if canvas_name.present?
        result[:canvas_data] = canvas_data if canvas_name.present?
        result
      end
    end
  end
end
