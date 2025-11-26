module Tools
  class UpdateIntegrationTool < BaseTool
    def self.metadata
      {
        name: "update_integration",
        description: <<~DESC.strip,
          Updates an existing Integration. You can modify the integration's name, description,
          base URL, category, or add new operations.
          
          Note: You can only update integrations that your entity created. System integrations
          cannot be modified by non-admins.
          
          Use this tool when:
          - The API base URL has changed
          - You need to add new operations to an existing integration
          - You want to update the integration's description or category
          - You need to activate or deactivate an integration
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            integration_identifier: {
              type: "string",
              description: "Integration ID, slug, or name to update"
            },
            name: {
              type: "string",
              description: "New display name for the integration"
            },
            description: {
              type: "string",
              description: "New description"
            },
            base_url: {
              type: "string",
              description: "New base URL for the API"
            },
            category: {
              type: "string",
              enum: %w[payment ecommerce crm communication productivity marketing analytics custom],
              description: "New category"
            },
            is_active: {
              type: "boolean",
              description: "Whether the integration is active"
            },
            operations: {
              type: "array",
              description: "New operations to add (existing operations are not modified)",
              items: {
                type: "object",
                properties: {
                  name: { type: "string", description: "Operation name" },
                  path: { type: "string", description: "API path" },
                  method: { type: "string", enum: %w[GET POST PUT PATCH DELETE] },
                  description: { type: "string" },
                  parameters: { type: "object" }
                },
                required: %w[name path]
              }
            }
          },
          required: %w[integration_identifier]
        }
      }
    end

    def execute(args)
      log_execution(args)

      factory = Factories::IntegrationFactory.new(user: @user, entity: @entity)

      result = factory.update(
        args["integration_identifier"],
        name: args["name"],
        description: args["description"],
        base_url: args["base_url"],
        category: args["category"],
        is_active: args["is_active"],
        operations: args["operations"]
      )

      if result[:success]
        integration = result[:integration]
        operations = result[:operations_created] || []

        response = {
          success: true,
          integration_id: integration.id,
          integration_slug: integration.slug,
          integration_name: integration.name,
          operations_added: operations.map { |op| { name: op.name, operation_id: op.operation_id } }
        }

        if result[:warnings].present?
          response[:warnings] = result[:warnings]
        end

        success_response(**response)
      else
        error_response("Integration update failed: #{result[:errors].join(', ')}")
      end
    rescue => e
      Rails.logger.error "UpdateIntegrationTool error: #{e.message}"
      error_response("Failed to update integration: #{e.message}")
    end
  end
end

