# frozen_string_literal: true

module V3
  module Tools
    # PlatformDoTool - The universal "do something" tool
    #
    # This is the primary action tool in the Intent Engine architecture.
    # The LLM translates user intent into a goal + spec, and this tool
    # delegates to the IntentEngine which either:
    #   1. Matches a pre-built Recipe (fast, zero LLM cost)
    #   2. Falls back to LLM decomposition for novel requests
    #
    # The LLM's job is to understand WHAT the user wants.
    # The platform's job (via IntentEngine) is to figure out HOW.
    #
    # This replaces direct LLM calls to platform_create, platform_update,
    # and platform_execute -- but those tools still exist internally
    # and are used by recipes under the hood.
    #
    class PlatformDoTool < ::Tools::BaseTool
      def self.metadata
        {
          name: "platform_do",
          description: <<~DESC.strip,
            Execute a goal on the platform. Describe WHAT you want to accomplish and the platform figures out HOW.

            This is your primary action tool. Use it for anything that changes platform state:
            creating, updating, deleting, sending, publishing, syncing, building.

            The goal is a short description of what to accomplish. The spec provides the details.

            Examples:
            - platform_do(goal: "create contact", spec: { first_name: "Jane", email: "jane@example.com" })
            - platform_do(goal: "welcome email automation", spec: { trigger: "new_lead", subject: "Welcome!", body: "<h1>Hi!</h1>" })
            - platform_do(goal: "build landing page", spec: { title: "Summer Sale", description: "Promo page for summer campaign" })
            - platform_do(goal: "send campaign", spec: { campaign_id: 7 })
            - platform_do(goal: "create automation", spec: { name: "Follow Up", trigger: "form_submit", action: "send_email", template_id: 5 })
            - platform_do(goal: "sync stripe customers", spec: { integration: "stripe", source: "customers", target: "Contact" })
            - platform_do(goal: "delete contact", spec: { type: "contact", id: 42 })
            - platform_do(goal: "update contact", spec: { type: "contact", id: 42, data: { lifecycle_stage: "customer" } })
            - platform_do(goal: "build app", spec: { name: "CRM", description: "Contact management system" })
            - platform_do(goal: "publish landing page", spec: { landing_page_id: 15 })
            - platform_do(goal: "create scheduled task", spec: { name: "Weekly Report", prompt: "Summarize contacts", schedule: "weekly" })
            - platform_do(goal: "generate csv", spec: { title: "Export", headers: ["Name", "Email"], rows: [["Jane", "jane@co.com"]] })
            - platform_do(goal: "edit landing page section", spec: { landing_page_id: 189, section: "hero", instruction: "Center the text" })
            - platform_do(goal: "add custom field", spec: { model: "contact", field_name: "industry", field_type: "string" })
            - platform_do(goal: "run integration action", spec: { integration: "stripe", operation: "list_charges", inputs: { limit: 10 } })
            - platform_do(goal: "create contact group and add contacts", spec: { group_name: "VIPs", contact_ids: [1, 2, 3] })
            - platform_do(goal: "set up drip campaign", spec: { name: "Onboarding", emails: [{ subject: "Day 1", delay: 0 }, { subject: "Day 3", delay: 3 }] })
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              goal: {
                type: "string",
                description: "What you want to accomplish (e.g., 'create contact', 'welcome email automation', 'build landing page', 'sync stripe customers')"
              },
              spec: {
                type: "object",
                description: "Details and parameters for the goal. Freeform -- include whatever data is needed.",
                additionalProperties: true
              }
            },
            required: ["goal"]
          }
        }
      end

      def execute(args)
        log_execution(args)

        goal = get_arg(args, :goal)&.to_s&.strip
        spec = get_arg(args, :spec, {})

        return error_response("Missing required field: goal") if goal.blank?

        Rails.logger.info "[V3::PlatformDo] Goal: #{goal}"

        # Delegate to IntentEngine
        engine = V3::IntentEngine.new(user: user, entity: entity, context: context, progress_callback: progress_callback)
        result = engine.execute(goal: goal, spec: spec)

        # Propagate canvas suggestions from engine results
        if result.is_a?(Hash) && result[:canvas_type].present?
          @context[:canvas_suggestion] = result[:canvas_type]
        end

        result
      rescue => e
        Rails.logger.error "[V3::PlatformDo] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Failed to execute goal '#{goal}': #{e.message}")
      end
    end
  end
end
