# frozen_string_literal: true

module Tools
  # ExecuteIntegrationActionTool - Execute pre-defined integration actions
  #
  # This provides a normalized interface for Amos to call API operations.
  # Instead of guessing at API-specific parameters, Amos uses standard
  # input names and types, and the system handles mapping to API format.
  #
  # Example:
  #   execute_integration_action(
  #     integration: "coinbase",
  #     action: "place_limit_order",
  #     inputs: {
  #       symbol: "BTC/USD",    # Normalized format
  #       side: "buy",          # Always lowercase
  #       quantity: 0.001,      # Always a number
  #       price: 50000.00       # Always in dollars
  #     }
  #   )
  #
  # The system handles:
  # - Input validation against schema
  # - Parameter mapping (symbol → product_id, "buy" → "BUY")
  # - API execution
  # - Response normalization
  #
  class ExecuteIntegrationActionTool < BaseTool
    def self.metadata
      {
        name: "execute_integration_action",
        description: <<~DESC.strip,
          Execute a pre-defined integration action with normalized parameters.
          
          **PREFER THIS over raw execute_integration for consistent, reliable API calls.**
          
          Actions have:
          - Validated input schemas (you'll get clear error messages)
          - Automatic parameter mapping (no guessing API-specific formats)
          - Response normalization (consistent output format)
          
          **To see available actions:** list_integration_actions(integration: "stripe")
          
          **Example:**
          ```
          execute_integration_action(
            integration: "stripe",
            action: "create_customer",
            inputs: { email: "user@example.com", name: "John Doe" }
          )
          ```
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            integration: {
              type: "string",
              description: 'Integration slug (e.g., "stripe", "coinbase", "hubspot")'
            },
            action: {
              type: "string",
              description: 'Action name (e.g., "create_customer", "place_limit_order")'
            },
            inputs: {
              type: "object",
              description: "Action inputs using normalized parameter names. Check input_schema for required fields."
            },
            connection_id: {
              type: "integer",
              description: "Optional: Specific connection ID (auto-selects if not provided)"
            }
          },
          required: %w[integration action inputs]
        }
      }
    end

    def execute(args)
      log_execution(args)

      integration_slug = get_arg(args, :integration)
      action_name = get_arg(args, :action)
      inputs = get_arg(args, :inputs, {})
      connection_id = get_arg(args, :connection_id)

      # Validate required args
      if error = validate_required_args(args, %i[integration action])
        return error
      end

      begin
        # Find the integration
        integration = find_integration(integration_slug)
        return error_response("Integration '#{integration_slug}' not found") unless integration

        # Find the action
        action = IntegrationAction.for_entity(@entity)
                                  .where(integration: integration)
                                  .find_by(action_name: action_name)

        unless action
          # Suggest available actions
          available = IntegrationAction.for_entity(@entity)
                                       .where(integration: integration)
                                       .usable
                                       .pluck(:action_name)
          
          return error_response(
            "Action '#{action_name}' not found for #{integration.name}",
            available_actions: available,
            hint: available.any? ? 
              "Try one of: #{available.first(5).join(', ')}" : 
              "No actions defined. Use execute_integration for raw API calls."
          )
        end

        unless action.active? || action.testing?
          return error_response(
            "Action '#{action_name}' is not active (status: #{action.status})",
            hint: "This action is in #{action.status} status. Contact admin to activate."
          )
        end

        # Find user's connection
        connection = find_connection(integration, connection_id)
        unless connection
          return error_response(
            "No active connection for #{integration.name}",
            hint: "Connect #{integration.name} first, then retry."
          )
        end

        # Execute the action
        execution = action.execute!(
          inputs: inputs,
          connection: connection,
          user: @user,
          entity: @entity
        )

        if execution.success?
          # Load canvas for list results
          if execution.normalized_response.is_a?(Array)
            load_data_canvas(execution.normalized_response, action, execution)
          end

          success_response(
            message: "Action '#{action_name}' completed successfully",
            action: action_name,
            integration: integration.name,
            data: slim_response(execution.normalized_response),
            execution_id: execution.id,
            duration_ms: execution.duration_ms
          )
        else
          error_response(
            "Action failed: #{execution.error_message}",
            action: action_name,
            integration: integration.name,
            execution_id: execution.id,
            http_status: execution.http_status_code
          )
        end

      rescue => e
        Rails.logger.error "ExecuteIntegrationActionTool error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        error_response("Execution failed: #{e.message}")
      end
    end

    private

    def find_integration(slug)
      Integration.find_for_use(slug, @entity)
    end

    def find_connection(integration, connection_id = nil)
      if connection_id
        Connection.find_by(id: connection_id, integration: integration, user: @user, entity: @entity)
      else
        Connection.where(integration: integration, user: @user, entity: @entity)
                  .active
                  .order(created_at: :desc)
                  .first
      end
    end

    def slim_response(data)
      return data unless data.is_a?(Array) && data.length > 10

      {
        _note: "Showing summary of #{data.length} records",
        sample: data.first(5),
        total_count: data.length
      }
    end

    def load_data_canvas(data, action, execution)
      return if data.empty?

      columns = select_display_columns(data.first)

      @context[:canvas_suggestion] = "dynamic_canvas"
      @context[:canvas_data] = {
        title: "#{action.integration.name} - #{action.action_name}",
        content: generate_table_html(data, columns, action),
        execution_id: execution.id
      }
    end

    def select_display_columns(row)
      return [] unless row.is_a?(Hash)

      priority = %w[id email name title description status amount created_at type]
      available = row.keys.map(&:to_s)
      selected = priority & available
      
      if selected.length < 8
        other = available - selected - %w[metadata raw_data object]
        selected += other.first(8 - selected.length)
      end

      selected.first(10)
    end

    def generate_table_html(data, columns, action)
      <<~HTML
        <div class="action-response-data">
          <div class="response-header mb-3">
            <h4>#{action.action_name.titleize}</h4>
            <p class="text-muted">Retrieved #{data.length} records from #{action.integration.name}</p>
          </div>
          <div class="table-responsive">
            <table class="table table-striped table-hover">
              <thead>
                <tr>
                  #{columns.map { |col| "<th>#{col.humanize}</th>" }.join}
                </tr>
              </thead>
              <tbody>
                #{data.first(50).map { |row|
                  "<tr>#{columns.map { |col| 
                    "<td>#{format_cell(row[col] || row[col.to_sym])}</td>"
                  }.join}</tr>"
                }.join}
              </tbody>
            </table>
          </div>
          #{data.length > 50 ? "<p class='text-muted'>Showing first 50 of #{data.length} records</p>" : ''}
        </div>
      HTML
    end

    def format_cell(value)
      case value
      when nil then '<span class="text-muted">-</span>'
      when true then '<span class="badge bg-success">Yes</span>'
      when false then '<span class="badge bg-secondary">No</span>'
      when Time, DateTime, Date then value.strftime("%Y-%m-%d %H:%M")
      when Hash, Array then '<span class="text-muted">[Complex]</span>'
      else ERB::Util.html_escape(value.to_s.truncate(50))
      end
    end
  end
end

