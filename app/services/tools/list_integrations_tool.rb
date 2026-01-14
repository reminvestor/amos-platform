module Tools
  class ListIntegrationsTool < BaseTool
    def self.metadata
      {
        name: "list_integrations",
        description: <<~DESC.strip,
          List all connected integrations for this account.
          
          Returns integration name, slug, status, and available operations.
          Use this FIRST if you're unsure what integrations exist or how to use them!
          
          After listing, use list_operations(integration_slug: "xxx") to see 
          detailed operation parameters, or execute_integration to run an operation.
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            include_operations: {
              type: "boolean",
              description: "Include list of available operations for each integration (default: true)"
            },
            category: {
              type: "string",
              description: "Filter by category (payment, crm, communication, marketing, etc.)"
            }
          }
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      include_operations = args["include_operations"] != false
      category_filter = args["category"]

      begin
        # Get all active connections for this entity
        connections = @entity.connections.includes(:integration).active
        
        # Also get available integrations that aren't connected yet
        available_integrations = Integration.for_entity(@entity)
          .where.not(id: connections.map(&:integration_id))
        
        connected = connections.map do |conn|
          format_connection(conn, include_operations)
        end
        
        # Filter by category if specified
        if category_filter.present?
          connected = connected.select { |c| c[:category]&.downcase == category_filter.downcase }
        end

        # Include a few popular available integrations
        available = available_integrations.limit(10).map do |integration|
          {
            name: integration.name,
            slug: integration.slug,
            category: integration.category,
            status: "available",
            description: integration.description&.truncate(100),
            operations_count: integration.integration_operations.count
          }
        end

        success_response(
          message: "Found #{connected.count} connected integrations",
          connected_integrations: connected,
          available_integrations: available.first(5),
          tips: [
            "Use execute_integration(integration: 'slug', operation: 'operation_name', params: {...})",
            "Use list_operations(integration_slug: 'slug') to see all operations and their parameters",
            "Common params: limit (number of records), created (date filter), id (specific record)"
          ]
        )
      rescue => e
        Rails.logger.error "ListIntegrationsTool error: #{e.message}"
        error_response("Failed to list integrations: #{e.message}")
      end
    end

    private

    def format_connection(conn, include_operations)
      result = {
        name: conn.integration.name,
        slug: conn.integration.slug,
        category: conn.integration.category,
        status: conn.status,
        connection_id: conn.id,
        last_used: conn.updated_at&.iso8601
      }

      # Add status explanation
      result[:status_note] = case conn.status
      when "connected"
        "Ready to use"
      when "limited"
        "Working but may be rate limited"
      when "failing"
        "Recent errors detected - try anyway, it may work now"
      when "disconnected"
        "Needs reconnection"
      end

      if include_operations
        operations = conn.integration.integration_operations.enabled.map do |op|
          {
            name: op.name,
            operation_id: op.operation_id,
            method: op.http_method,
            description: op.description&.truncate(80)
          }
        end
        result[:operations] = operations.first(10) # Limit to avoid token bloat
        result[:total_operations] = conn.integration.integration_operations.count
      end

      result
    end
  end
end

