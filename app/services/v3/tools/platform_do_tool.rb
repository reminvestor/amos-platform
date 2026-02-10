# frozen_string_literal: true

module V3
  module Tools
    # PlatformDoTool - Complex multi-step workflow executor
    #
    # Phase 6A/6C: This tool is now for COMPLEX workflows only.
    # Simple single-object CRUD goes through platform_create/platform_update directly.
    #
    # platform_do delegates to IntentEngine -> PlatformBrain (Claude agent loop).
    # Use it for goals that require multiple steps, planning, or external integrations.
    #
    class PlatformDoTool < ::Tools::BaseTool
      def self.metadata
        {
          name: "platform_do",
          description: <<~DESC.strip,
            Execute a complex, multi-step goal on the platform. The execution engine plans and executes the steps.

            Use this for workflows that require MULTIPLE steps, planning, or external integrations:
            - Building complete landing pages with multiple sections
            - Setting up automations (template + trigger + action)
            - Integration operations (pulling data from Stripe, syncing with HubSpot)
            - Any goal that needs to query first, then create/update based on results
            - Compound goals ("pull customers from Stripe AND add as contacts")

            For SIMPLE single-object operations, prefer platform_create or platform_update instead (faster, no delegation).

            Put a short action summary in `goal` and the user's FULL detailed request in `spec.user_request`.
            Do NOT paraphrase — pass the user's exact words so the execution engine has all the details.

            Examples:
            - goal: "build landing page", spec: { user_request: "create a page for email signups with bright colors", title: "Join Us" }
            - goal: "pull last 10 stripe customers", spec: { integration: "stripe", operation: "list_customers", inputs: { limit: 10 } }
            - goal: "welcome email automation", spec: { user_request: "set up an automation that sends a welcome email when a new contact is created" }
            - goal: "extend CRM schema", spec: { user_request: "Add fields for Middle Name, Preferred Name, marital status..." }
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              goal: {
                type: "string",
                description: "What you want to accomplish (e.g., 'create contact', 'create 5 new contacts', 'welcome email automation', 'build landing page', 'run integration action')"
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
