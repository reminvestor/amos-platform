module Tools
  class ListOperationsTool < BaseTool
    def self.metadata
      {
        name: "list_operations",
        description: "List available operations for a specific connection or integration. Provide either connection_id, integration_id, or integration_slug.",
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            connection_id: {
              type: "integer",
              description: "The ID of the connection to list operations for"
            },
            integration_id: {
              type: "integer",
              description: "The ID of the integration to list operations for"
            },
            integration_slug: {
              type: "string",
              description: "The slug of the integration (e.g., 'stripe', 'mailgun')"
            }
          }
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      Rails.logger.info "🔧 Executing list_operations with args: #{args.inspect}"

      begin
        # Ensure at least one parameter is provided
        if args["connection_id"].blank? && args["integration_id"].blank? && args["integration_slug"].blank?
          return {
            success: false,
            error: "Please provide either connection_id, integration_id, or integration_slug"
          }
        end

        operations = []

        if args["connection_id"]
          # Get operations for a specific connection (scoped to current entity)
          connection = Connection.find_by(id: args["connection_id"], entity: entity)
          return { success: false, error: "Connection not found" } unless connection

          operations = connection.integration.integration_operations.map do |op|
            format_operation(op)
          end

          integration_name = connection.integration.name
          integration_id = connection.integration.id
        elsif args["integration_id"]
          # Get operations for a specific integration by ID
          integration = Integration.find_by(id: args["integration_id"])
          return { success: false, error: "Integration not found" } unless integration

          operations = integration.integration_operations.map do |op|
            format_operation(op)
          end

          integration_name = integration.name
          integration_id = integration.id
        elsif args["integration_slug"]
          # Get operations for a specific integration by slug
          integration = Integration.find_by(slug: args["integration_slug"])
          return { success: false, error: "Integration not found" } unless integration

          operations = integration.integration_operations.map do |op|
            format_operation(op)
          end

          integration_name = integration.name
          integration_id = integration.id
        end

        {
          success: true,
          integration: {
            id: integration_id,
            name: integration_name
          },
          operations: operations,
          total_count: operations.count
        }
      rescue => e
        Rails.logger.error "ListOperationsTool error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        { success: false, error: e.message }
      end
    end

    private

    def format_operation(operation)
      {
        id: operation.id,
        operation_id: operation.operation_id,
        name: operation.name,
        description: operation.description,
        http_method: operation.http_method,
        path_template: operation.path_template,
        request_schema: operation.request_schema || {},
        response_schema: operation.response_schema || {},
        pagination_strategy: operation.pagination_strategy,
        is_idempotent: operation.is_idempotent,
        requires_confirmation: operation.requires_confirmation,
        max_limit: operation.max_limit,
        documentation: operation.documentation,
        examples: operation.examples
      }
    end
  end
end
