# frozen_string_literal: true

module Tools
  # CreateSupportTicketTool - Creates rich, actionable support tickets
  #
  # AMOS creates tickets from user reports (bugs, feature requests).
  # The system has access to platform context (errors, modules, integrations)
  # so tickets should be well-structured from the start.
  #
  # AMOS should gather:
  # - Clear title and description (from user)
  # - Steps to reproduce (ask user or infer from conversation)
  # - Expected vs actual behavior (from user context)
  # - Category and priority (AMOS determines from context)
  # - Affected component (AMOS infers from conversation/errors)
  # - Acceptance criteria (AMOS generates)
  #
  class CreateSupportTicketTool < BaseTool
    def self.metadata
      {
        name: "create_support_ticket",
        description: <<~DESC.strip,
          Create a support ticket for a bug report, feature request, or issue.
          Use this when a user reports a problem or wants a new feature.

          IMPORTANT: Create RICH tickets with all available context. You have access
          to the platform state — use it! Include:
          - Clear, specific title (not "bug" or "broken")
          - Detailed description with context
          - Steps to reproduce (bugs) or user story (features)
          - Expected behavior vs actual behavior
          - Acceptance criteria (how to verify the fix)
          - Affected component (infer from conversation)

          Better tickets = better bounties = better results for the user.
        DESC
        category: "support",
        input_schema: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "Clear, specific title. BAD: 'bug'. GOOD: 'Email notifications not sent after contact form submission'"
            },
            description: {
              type: "string",
              description: "Detailed description including context, what the user was doing, and what went wrong"
            },
            category: {
              type: "string",
              description: "Issue category",
              enum: %w[bug performance feature_request security ui_issue data_issue agent_error integration_error documentation]
            },
            priority: {
              type: "string",
              description: "Priority based on impact and urgency",
              enum: %w[low medium high critical]
            },
            steps_to_reproduce: {
              type: "string",
              description: "For bugs: numbered steps to reproduce. For features: user story (As a X, I want Y, so that Z)"
            },
            expected_behavior: {
              type: "string",
              description: "What SHOULD happen (bugs) or what the feature SHOULD do"
            },
            actual_behavior: {
              type: "string",
              description: "For bugs: what ACTUALLY happens instead"
            },
            acceptance_criteria: {
              type: "array",
              items: { type: "string" },
              description: "List of criteria to verify the fix/feature is complete. E.g., ['Email is sent within 5 minutes', 'Sender name matches contact name']"
            },
            affected_component: {
              type: "string",
              description: "Which part of the platform is affected (e.g., 'Email system', 'Dashboard', 'API', 'Workflow engine')"
            },
            error_message: {
              type: "string",
              description: "Any error message observed"
            },
            affected_url: {
              type: "string",
              description: "URL where the issue occurs (if applicable)"
            },
            user_story: {
              type: "string",
              description: "For feature requests: 'As a [role], I want [capability] so that [benefit]'"
            },
            business_value: {
              type: "string",
              description: "For feature requests: why this matters to users/business"
            },
            suggested_approach: {
              type: "string",
              description: "Optional: how you think this could be fixed/implemented"
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

      # Validate required args
      if error = validate_required_args(args, [:title, :description])
        return error
      end

      begin
        # Build the full description with all structured context
        full_description = build_rich_description(args)

        # Create the ticket with all structured fields
        ticket = SupportTicket.create!(
          entity: entity,
          user: user,
          scout_conversation: context[:conversation],
          title: title,
          description: full_description,
          source: 'user_reported',
          category: category,
          priority: priority,
          error_message: get_arg(args, :error_message),
          steps_to_reproduce: get_arg(args, :steps_to_reproduce),
          expected_behavior: get_arg(args, :expected_behavior),
          actual_behavior: get_arg(args, :actual_behavior),
          acceptance_criteria: get_arg(args, :acceptance_criteria) || [],
          affected_component: get_arg(args, :affected_component),
          affected_url: get_arg(args, :affected_url),
          user_story: get_arg(args, :user_story),
          business_value: get_arg(args, :business_value),
          suggested_approach: get_arg(args, :suggested_approach),
          error_context: {
            reported_via: 'amos_chat',
            conversation_id: context[:conversation]&.id,
            session_id: context[:session_id]
          }
        )

        # Run qualification immediately — system enrichment fills gaps
        qualification = TicketQualificationService.qualify!(ticket, auto_enrich: true)

        # Start automated debugging for bugs
        auto_message = ""
        if ticket.is_bug? && ticket.can_auto_process?
          PlatformEvolution::DebugAgentJob.perform_later(ticket.id)
          auto_message = " I've started an automated investigation."
        elsif ticket.is_feature_request?
          auto_message = " Feature requests need admin approval before work begins."
        end

        # Bounty eligibility message
        bounty_message = if qualification[:eligible]
          " This ticket is ready to become a bounty (readiness: #{qualification[:readiness_score]}/100)."
        else
          " Readiness: #{qualification[:readiness_score]}/100 — #{qualification[:gaps].first}" if qualification[:gaps].any?
        end

        {
          success: true,
          ticket_number: ticket.ticket_number,
          status: ticket.status,
          priority: ticket.priority,
          category: ticket.category,
          readiness_score: qualification[:readiness_score],
          bounty_eligible: qualification[:eligible],
          message: "Created ticket #{ticket.ticket_number} (#{ticket.category&.humanize}).#{auto_message}#{bounty_message}",
          canvas: 'support_tickets',
          canvas_data: {}
        }
      rescue => e
        Rails.logger.error "[CreateSupportTicketTool] Failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        {
          success: false,
          error: "Sorry, I couldn't create the ticket right now. Please try again."
        }
      end
    end

    private

    def build_rich_description(args)
      parts = [get_arg(args, :description)]

      steps = get_arg(args, :steps_to_reproduce)
      if steps.present?
        parts << "\n\n### Steps to Reproduce\n#{steps}"
      end

      expected = get_arg(args, :expected_behavior)
      if expected.present?
        parts << "\n\n### Expected Behavior\n#{expected}"
      end

      actual = get_arg(args, :actual_behavior)
      if actual.present?
        parts << "\n\n### Actual Behavior\n#{actual}"
      end

      error_msg = get_arg(args, :error_message)
      if error_msg.present?
        parts << "\n\n### Error Message\n```\n#{error_msg}\n```"
      end

      criteria = get_arg(args, :acceptance_criteria)
      if criteria.present? && criteria.any?
        parts << "\n\n### Acceptance Criteria\n#{criteria.map { |c| "- [ ] #{c}" }.join("\n")}"
      end

      component = get_arg(args, :affected_component)
      if component.present?
        parts << "\n\n**Affected Component:** #{component}"
      end

      story = get_arg(args, :user_story)
      if story.present?
        parts << "\n\n### User Story\n#{story}"
      end

      value = get_arg(args, :business_value)
      if value.present?
        parts << "\n\n### Business Value\n#{value}"
      end

      approach = get_arg(args, :suggested_approach)
      if approach.present?
        parts << "\n\n### Suggested Approach\n#{approach}"
      end

      parts << "\n\n---\n*Reported via AMOS chat*"
      parts.join
    end
  end
end
