# frozen_string_literal: true

module Tools
  # CreateSupportTicketTool - Allows AMOS to create support tickets from user reports
  #
  # When users say "I found a bug" or "Something isn't working", AMOS can use
  # this tool to create a ticket that feeds into the Platform Evolution Engine.
  #
  class CreateSupportTicketTool < BaseTool
    def self.metadata
      {
        name: "create_support_ticket",
        description: <<~DESC.strip,
          Create a support ticket for a bug report, feature request, or issue.
          Use this when a user reports a problem, describes unexpected behavior,
          or wants to request a new feature.
          
          The ticket will be tracked and may be automatically investigated and fixed.
        DESC
        category: "support",
        input_schema: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "Brief title describing the issue (e.g., 'Email not sending', 'Dashboard loading slowly')"
            },
            description: {
              type: "string",
              description: "Detailed description of the issue, including what the user expected vs what happened"
            },
            category: {
              type: "string",
              description: "Category of the issue",
              enum: %w[bug performance feature_request ui_issue data_issue agent_error integration_error documentation]
            },
            priority: {
              type: "string",
              description: "Priority level (only set to 'high' or 'critical' if user indicates urgency)",
              enum: %w[low medium high critical]
            },
            steps_to_reproduce: {
              type: "string",
              description: "Steps the user took that led to the issue"
            },
            error_message: {
              type: "string",
              description: "Any error message the user saw"
            }
          },
          required: ["title", "description"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      title = get_arg(args, :title)
      description = get_arg(args, :description)
      category = get_arg(args, :category, 'bug')
      priority = get_arg(args, :priority, 'medium')
      steps_to_reproduce = get_arg(args, :steps_to_reproduce)
      error_message = get_arg(args, :error_message)

      # Validate required args
      if error = validate_required_args(args, [:title, :description])
        return error
      end

      begin
        # Create the ticket
        ticket = SupportTicket.create!(
          entity: entity,
          user: user,
          scout_conversation: context[:conversation],
          title: title,
          description: build_full_description(description, steps_to_reproduce, error_message),
          source: 'user_reported',
          category: category,
          priority: priority,
          error_message: error_message,
          error_context: {
            steps_to_reproduce: steps_to_reproduce,
            reported_via: 'amos_chat',
            conversation_id: context[:conversation]&.id
          }
        )

        # Start automated debugging for bugs (feature requests need admin approval first)
        auto_debug_message = ""
        if ticket.is_bug? && ticket.can_auto_process?
          PlatformEvolution::DebugAgentJob.perform_later(ticket.id)
          auto_debug_message = " I've started an automated investigation."
        elsif ticket.is_feature_request?
          auto_debug_message = " Feature requests need admin approval before work begins."
        end

        {
          success: true,
          ticket_number: ticket.ticket_number,
          status: ticket.status,
          priority: ticket.priority,
          category: ticket.category,
          message: "I've created ticket #{ticket.ticket_number} to track this #{ticket.category&.humanize || 'issue'}.#{auto_debug_message}",
          canvas: 'support_tickets',
          canvas_data: {}
        }
      rescue => e
        Rails.logger.error "[CreateSupportTicketTool] Failed to create ticket: #{e.message}"
        {
          success: false,
          error: "Sorry, I couldn't create the ticket right now. Please try again or contact support directly."
        }
      end
    end

    private

    def build_full_description(description, steps, error_message)
      parts = [description]

      if steps.present?
        parts << "\n\n### Steps to Reproduce\n#{steps}"
      end

      if error_message.present?
        parts << "\n\n### Error Message\n```\n#{error_message}\n```"
      end

      parts << "\n\n---\n*Reported via AMOS chat*"

      parts.join
    end
  end
end
