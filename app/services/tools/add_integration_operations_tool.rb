module Tools
  class AddIntegrationOperationsTool < BaseTool
    def self.metadata
      {
        name: "add_integration_operations",
        description: <<~DESC.strip,
          **STAGE 4 of 4: Add Integration Operations**
          
          Adds API operations (endpoints) to a connected integration.
          Auth must be configured and tested before this step.
          
          **Before calling this tool:**
          1. test_integration_auth must have passed (Stage 3)
          2. Research the API endpoints from documentation
          3. Identify common operations users will need
          
          **For each operation, provide:**
          - name: Human-readable name (e.g., "List Boards")
          - path: API path with placeholders (e.g., "/1/members/me/boards")
          - method: HTTP method (GET, POST, PUT, DELETE)
          - description: What the operation does
          - parameters: Request parameters (optional)
          
          **Path Parameters:**
          Use {placeholder} syntax for dynamic parts:
          - /boards/{boardId}/cards
          - /company/{companyId}/invoices
          
          **You can call this multiple times** to add more operations later.
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            integration_id: {
              type: "integer",
              description: "Integration ID from previous stages"
            },
            operations: {
              type: "array",
              description: "Operations to add",
              items: {
                type: "object",
                properties: {
                  name: { 
                    type: "string", 
                    description: "Operation name (e.g., 'List Boards', 'Create Card')" 
                  },
                  path: { 
                    type: "string", 
                    description: "API path (e.g., '/1/boards/{boardId}')" 
                  },
                  method: { 
                    type: "string", 
                    enum: %w[GET POST PUT PATCH DELETE],
                    description: "HTTP method" 
                  },
                  description: { 
                    type: "string", 
                    description: "What this operation does" 
                  },
                  parameters: { 
                    type: "object", 
                    description: "Request parameters as name:type pairs (e.g., {name: 'string', limit: 'integer'})" 
                  },
                  pagination_strategy: { 
                    type: "string", 
                    enum: %w[no_pagination cursor page offset],
                    description: "How pagination works for list endpoints"
                  }
                },
                required: %w[name path method]
              }
            }
          },
          required: %w[integration_id operations]
        }
      }
    end

    def execute(args)
      log_execution(args)

      factory = Factories::IntegrationFactory.new(user: @user, entity: @entity)

      result = factory.add_operations(
        integration_id: args["integration_id"],
        operations: args["operations"]
      )

      if result[:success]
        integration = result[:integration]
        operations = result[:operations_created] || []
        
        success_response(
          message: "✅ Operations added! The integration is now fully configured.",
          integration_id: integration.id,
          integration_name: integration.name,
          integration_slug: integration.slug,
          operations_created: operations.compact.map { |op|
            {
              name: op.name,
              operation_id: op.operation_id,
              method: op.http_method,
              path: op.path_template
            }
          },
          total_operations: integration.integration_operations.count,
          status: "ready",
          next_steps: [
            "The integration is ready to use!",
            "Use execute_integration to call operations",
            "Example: execute_integration(integration: '#{integration.slug}', operation: '#{operations.first&.operation_id&.split('.')&.last || 'operation_name'}', params: {})"
          ]
        )
      else
        error_response(
          "Failed to add operations: #{result[:errors].join(', ')}",
          warnings: result[:warnings]
        )
      end
    rescue => e
      Rails.logger.error "AddIntegrationOperationsTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to add operations: #{e.message}")
    end
  end
end

