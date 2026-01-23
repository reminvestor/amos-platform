# frozen_string_literal: true

module Tools
  # ListIntegrationActionsTool - Discover available actions for an integration
  #
  # Shows what actions are available for an integration, including:
  # - Input schema (what parameters are needed)
  # - Description of what the action does
  # - Success rate and usage stats
  #
  class ListIntegrationActionsTool < BaseTool
    def self.metadata
      {
        name: "list_integration_actions",
        description: <<~DESC.strip,
          List available pre-defined actions for an integration.
          
          Use this to discover what actions are available before calling execute_integration_action.
          
          Returns the action name, description, required inputs, and usage stats.
          
          **Example:**
          ```
          list_integration_actions(integration: "stripe")
          ```
          
          **Returns:**
          - create_customer: Create a new customer (email*, name, phone)
          - charge_card: Charge a payment method (amount*, currency, customer_id*)
          - list_invoices: Get recent invoices (limit, customer_id)
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            integration: {
              type: "string",
              description: 'Integration slug (e.g., "stripe", "coinbase")'
            },
            category: {
              type: "string",
              description: 'Filter by category (e.g., "trading", "crm")'
            },
            include_schema: {
              type: "boolean",
              description: "Include full input schema in response (default: false)"
            }
          },
          required: %w[integration]
        }
      }
    end

    def execute(args)
      log_execution(args)

      integration_slug = get_arg(args, :integration)
      category = get_arg(args, :category)
      include_schema = get_arg(args, :include_schema, false)

      if error = validate_required_args(args, [:integration])
        return error
      end

      begin
        # Find the integration
        integration = Integration.find_for_use(integration_slug, @entity)
        return error_response("Integration '#{integration_slug}' not found") unless integration

        # Get actions
        actions = IntegrationAction.for_entity(@entity)
                                   .where(integration: integration)
                                   .usable
        
        actions = actions.where(category: category) if category.present?
        actions = actions.order(:action_name)

        if actions.empty?
          return success_response(
            message: "No actions defined for #{integration.name}",
            integration: integration.name,
            actions: [],
            hint: "Use execute_integration for raw API calls, or create actions with generate_action_mapping"
          )
        end

        formatted_actions = actions.map do |action|
          format_action(action, include_schema)
        end

        success_response(
          message: "Found #{formatted_actions.length} actions for #{integration.name}",
          integration: integration.name,
          integration_slug: integration.slug,
          actions: formatted_actions
        )

      rescue => e
        Rails.logger.error "ListIntegrationActionsTool error: #{e.message}"
        error_response("Failed to list actions: #{e.message}")
      end
    end

    private

    def format_action(action, include_schema)
      result = {
        action_name: action.action_name,
        description: action.description || action.action_name.titleize,
        required_inputs: format_required_inputs(action),
        optional_inputs: format_optional_inputs(action),
        category: action.category,
        status: action.status,
        success_rate: action.success_rate,
        usage_count: action.usage_count
      }

      if include_schema
        result[:input_schema] = action.input_schema
        result[:sample_input] = action.sample_input
      end

      result
    end

    def format_required_inputs(action)
      action.input_schema
            .select { |f| f['required'] || f[:required] }
            .map { |f| "#{f['name'] || f[:name]} (#{f['type'] || f[:type]})" }
            .join(', ')
    end

    def format_optional_inputs(action)
      action.input_schema
            .reject { |f| f['required'] || f[:required] }
            .map { |f| f['name'] || f[:name] }
    end
  end
end

