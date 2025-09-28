module Tools
  class ListConnectionsTool < BaseTool
    def self.metadata
      {
        name: 'list_connections',
        description: 'List all available integration connections for the current entity',
        category: 'integration',
        input_schema: {
          type: 'object',
          properties: {
            status: {
              type: 'string',
              enum: ['active', 'inactive', 'all'],
              description: 'Filter by connection status'
            },
            integration_type: {
              type: 'string',
              description: 'Filter by integration type (e.g., payment, email, analytics)'
            }
          }
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      status_filter = get_arg(args, :status, 'all')
      type_filter = get_arg(args, :integration_type)
      
      begin
        # Get connections for the entity
        connections = Connection.includes(:integration)
                               .where(entity: entity)
        
        # Apply status filter
        unless status_filter == 'all'
          connections = connections.where(status: status_filter)
        end
        
        # Apply type filter if provided
        if type_filter.present?
          connections = connections.joins(:integration)
                                   .where(integrations: { category: type_filter })
        end
        
        # Format connections for response
        formatted_connections = connections.map do |connection|
          {
            id: connection.id,
            name: connection.name,
            integration: {
              id: connection.integration.id,
              name: connection.integration.name,
              provider: connection.integration.provider,
              category: connection.integration.category,
              auth_type: connection.integration.auth_type
            },
            status: connection.status,
            created_at: connection.created_at,
            last_used_at: connection.metadata['last_used_at'],
            operations_count: connection.integration.integration_operations.count
          }
        end
        
        # Load integrations canvas
        load_integrations_canvas(formatted_connections)
        
        success_response(
          connections: formatted_connections,
          total_count: formatted_connections.length,
          filter_applied: {
            status: status_filter,
            type: type_filter
          }.compact
        )
      rescue => e
        Rails.logger.error "List connections failed: #{e.message}"
        error_response("Failed to list connections: #{e.message}")
      end
    end
    
    private
    
    def load_integrations_canvas(connections)
      @context[:canvas_suggestion] = 'integrations_manager'
      @context[:canvas_data] = {
        connections: connections,
        can_create_new: true,
        categories: Integration.distinct.pluck(:category).compact
      }
    end
  end
end
