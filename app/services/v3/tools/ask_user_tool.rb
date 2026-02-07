# frozen_string_literal: true

module V3
  module Tools
    # AskUserTool - V3 version for synchronous streaming flow
    #
    # Unlike V2's ask_user which requires AgentPluginExecution context,
    # V3's version works within the streaming chat flow by returning
    # a structured question response that the frontend can display.
    #
    # The model should include this question in its text response,
    # and the user will reply in their next message.
    #
    class AskUserTool < ::Tools::BaseTool
      def self.read_only?
        true
      end

      def self.metadata
        {
          name: "ask_user",
          description: <<~DESC.strip,
            Ask the user a clarifying question when you need more information to proceed.
            The question will be displayed to the user and they can reply in their next message.
            
            Use this when:
            - You need specific details to complete a task
            - There are multiple valid approaches and you want user preference
            - You need confirmation before a destructive action
            
            You can optionally show a preview panel with designs, schemas, or data for review.
          DESC
          category: "v3_core",
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

        return error_response("Missing required field: question") if question.blank?

        Rails.logger.info "[V3::AskUser] Asking: #{question}"

        # Build the response that will be displayed to the user
        response = {
          success: true,
          type: "question",
          question: question,
          variable_name: variable_name,
          context: context_data,
          message: "Please respond to continue: #{question}"
        }

        # Include canvas content if provided (for visual preview)
        if canvas_content.present?
          response[:canvas_content] = canvas_content
          response[:canvas_title] = canvas_title
        end

        # The question is returned as part of the tool result
        # The agent loop will include this in the final response
        # and the user can respond in their next message
        response
      end
    end
  end
end
