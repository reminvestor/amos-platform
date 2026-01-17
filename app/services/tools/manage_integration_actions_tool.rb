# frozen_string_literal: true

module Tools
  # ManageIntegrationActionsTool - Admin tool for managing integration actions
  #
  # Allows admins to:
  # - Audit which operations are missing actions
  # - Generate actions for operations (with or without AI)
  # - Activate/deactivate actions
  # - View action details
  #
  class ManageIntegrationActionsTool < BaseTool
    def self.metadata
      {
        name: "manage_integration_actions",
        description: <<~DESC.strip,
          Admin tool to manage integration actions.
          
          **Actions:**
          - `audit`: See which operations are missing actions
          - `generate`: Generate action for an operation (use_ai: true for AI-generated mapping)
          - `generate_all`: Generate actions for all operations in an integration
          - `activate`: Activate a draft action
          - `list`: List all actions for an integration
          - `test`: Test an action's mapping code
        DESC
        category: "admin",
        input_schema: {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[audit generate generate_all activate list test],
              description: "Action to perform"
            },
            integration_slug: {
              type: "string",
              description: "Integration slug (required for most actions)"
            },
            operation_id: {
              type: "string",
              description: "For generate: The operation to create an action for"
            },
            action_id: {
              type: "integer",
              description: "For activate/test: The action ID"
            },
            use_ai: {
              type: "boolean",
              description: "For generate: Use AI to generate smarter mapping code"
            },
            test_inputs: {
              type: "object",
              description: "For test: Sample inputs to test mapping"
            }
          },
          required: %w[action]
        }
      }
    end

    def execute(args)
      log_execution(args)

      action = get_arg(args, :action)

      case action
      when 'audit' then audit_actions(args)
      when 'generate' then generate_action(args)
      when 'generate_all' then generate_all_actions(args)
      when 'activate' then activate_action(args)
      when 'list' then list_actions(args)
      when 'test' then test_action(args)
      else
        error_response("Unknown action: #{action}")
      end
    end

    private

    def audit_actions(args)
      integration_slug = get_arg(args, :integration_slug)
      
      results = Integrations::ActionGeneratorService.audit(integration_slug)

      success_response(
        message: "Audit complete: #{results[:missing_actions]} operations missing actions",
        total_operations: results[:total_operations],
        with_actions: results[:with_actions],
        missing_actions: results[:missing_actions],
        missing: results[:missing].first(20)  # Limit to 20 for readability
      )
    end

    def generate_action(args)
      operation_id = get_arg(args, :operation_id)
      use_ai = get_arg(args, :use_ai, false)

      return error_response("operation_id is required") if operation_id.blank?

      operation = IntegrationOperation.find_by(operation_id: operation_id)
      return error_response("Operation not found: #{operation_id}") unless operation

      result = Integrations::ActionGeneratorService.generate_for_operation(
        operation,
        use_ai: use_ai,
        entity_id: @entity&.id,
        user_id: @user&.id
      )

      if result[:success]
        action = result[:action]
        success_response(
          message: "Created action: #{action.slug}",
          action_id: action.id,
          action_name: action.action_name,
          slug: action.slug,
          status: action.status,
          input_schema: action.input_schema,
          mapping_code: action.mapping_code
        )
      else
        error_response(result[:error])
      end
    end

    def generate_all_actions(args)
      integration_slug = get_arg(args, :integration_slug)
      use_ai = get_arg(args, :use_ai, false)

      return error_response("integration_slug is required") if integration_slug.blank?

      results = Integrations::ActionGeneratorService.backfill_for_integration(
        integration_slug,
        use_ai: use_ai,
        entity_id: @entity&.id,
        user_id: @user&.id
      )

      success_response(
        message: "Backfill complete for #{integration_slug}",
        created: results[:created],
        skipped: results[:skipped],
        errors: results[:errors]
      )
    end

    def activate_action(args)
      action_id = get_arg(args, :action_id)
      integration_slug = get_arg(args, :integration_slug)

      if action_id.present?
        action = IntegrationAction.find_by(id: action_id)
        return error_response("Action not found: #{action_id}") unless action
        
        action.update!(status: :active)
        success_response(message: "Activated action: #{action.slug}")
      elsif integration_slug.present?
        integration = Integration.find_by(slug: integration_slug)
        return error_response("Integration not found") unless integration
        
        count = IntegrationAction.where(integration: integration, status: :draft).update_all(status: :active)
        success_response(message: "Activated #{count} draft actions for #{integration.name}")
      else
        error_response("action_id or integration_slug is required")
      end
    end

    def list_actions(args)
      integration_slug = get_arg(args, :integration_slug)
      return error_response("integration_slug is required") if integration_slug.blank?

      integration = Integration.find_by(slug: integration_slug)
      return error_response("Integration not found") unless integration

      actions = IntegrationAction.where(integration: integration).order(:action_name).map do |action|
        {
          id: action.id,
          name: action.action_name,
          slug: action.slug,
          status: action.status,
          inputs: action.input_field_names,
          usage: action.usage_count,
          success_rate: action.success_rate
        }
      end

      success_response(
        message: "#{actions.length} actions for #{integration.name}",
        integration: integration.name,
        actions: actions
      )
    end

    def test_action(args)
      action_id = get_arg(args, :action_id)
      test_inputs = get_arg(args, :test_inputs, {})

      return error_response("action_id is required") if action_id.blank?

      action = IntegrationAction.find_by(id: action_id)
      return error_response("Action not found") unless action

      # Validate inputs
      validation = action.validate_inputs(test_inputs)
      unless validation[:valid]
        return error_response("Invalid inputs: #{validation[:errors].join(', ')}")
      end

      # Test mapping
      result = action.test_mapping(test_inputs)

      if result[:success]
        success_response(
          message: "Mapping test passed",
          action: action.action_name,
          inputs: result[:inputs],
          mapped_params: result[:mapped_params]
        )
      else
        error_response("Mapping failed: #{result[:error]}")
      end
    end
  end
end

