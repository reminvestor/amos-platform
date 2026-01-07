# frozen_string_literal: true

module Tools
  # CheckTicketStatusTool - Allows users to check on their support tickets via AMOS
  #
  class CheckTicketStatusTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: "check_ticket_status",
        description: <<~DESC.strip,
          Check the status of a support ticket or list the user's recent tickets.
          Use when a user asks about the status of an issue they reported.
        DESC
        category: "support",
        input_schema: {
          type: "object",
          properties: {
            ticket_number: {
              type: "string",
              description: "Specific ticket number to check (e.g., 'AMOS-00123'). If not provided, lists recent tickets."
            }
          },
          required: []
        }
      }
    end

    def execute(args)
      log_execution(args)

      ticket_number = get_arg(args, :ticket_number)

      if ticket_number.present?
        check_specific_ticket(ticket_number)
      else
        list_user_tickets
      end
    end

    private

    def check_specific_ticket(ticket_number)
      ticket = SupportTicket.find_by(
        entity: entity,
        ticket_number: ticket_number.upcase
      )

      unless ticket
        return {
          success: false,
          message: "I couldn't find ticket #{ticket_number}. Please check the ticket number and try again."
        }
      end

      # Check if user has access to this ticket
      unless ticket.user_id.nil? || ticket.user_id == user.id
        return {
          success: false,
          message: "You don't have access to view this ticket."
        }
      end

      {
        success: true,
        ticket: {
          number: ticket.ticket_number,
          title: ticket.title,
          status: ticket.status,
          priority: ticket.priority,
          created_at: ticket.created_at,
          updated_at: ticket.updated_at
        },
        message: format_ticket_status(ticket)
      }
    end

    def list_user_tickets
      tickets = SupportTicket.where(entity: entity, user: user)
        .order(created_at: :desc)
        .limit(10)

      if tickets.empty?
        return {
          success: true,
          tickets: [],
          message: "You don't have any open support tickets. Let me know if you'd like to report an issue!"
        }
      end

      {
        success: true,
        tickets: tickets.map do |t|
          {
            number: t.ticket_number,
            title: t.title,
            status: t.status,
            created_at: t.created_at
          }
        end,
        message: format_ticket_list(tickets)
      }
    end

    def format_ticket_status(ticket)
      status_emoji = case ticket.status
                     when 'open' then '🔵'
                     when 'investigating', 'debugging' then '🔍'
                     when 'fixing', 'testing' then '🔧'
                     when 'pr_submitted', 'pr_approved' then '📝'
                     when 'resolved', 'closed' then '✅'
                     when 'wont_fix' then '⏹️'
                     else '⚪'
                     end

      message = "#{status_emoji} **#{ticket.ticket_number}**: #{ticket.title}\n\n"
      message += "**Status:** #{ticket.status.humanize}\n"
      message += "**Priority:** #{ticket.priority.humanize}\n"
      message += "**Created:** #{ticket.created_at.strftime('%B %d, %Y')}\n"

      if ticket.resolved_at
        message += "**Resolved:** #{ticket.resolved_at.strftime('%B %d, %Y')}\n"
        message += "**Resolution:** #{ticket.resolution_notes}" if ticket.resolution_notes.present?
      elsif ticket.respond_to?(:has_pending_pr?) && ticket.has_pending_pr?
        message += "\n*A fix has been submitted and is pending review.*"
      elsif ticket.status == 'investigating'
        message += "\n*We're actively investigating this issue.*"
      end

      message
    end

    def format_ticket_list(tickets)
      message = "Here are your recent support tickets:\n\n"

      tickets.each do |t|
        emoji = t.respond_to?(:is_open?) && t.is_open? ? '🔵' : '✅'
        message += "#{emoji} **#{t.ticket_number}** - #{t.title.truncate(50)} (#{t.status.humanize})\n"
      end

      message += "\nAsk me about a specific ticket number for more details."
      message
    end
  end
end
