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
          Execute an integration action with normalized parameters.
          
          ⚠️ IMPORTANT: Call list_integration_actions FIRST to see available actions and required inputs!
          
          **Workflow:**
          1. list_integration_actions(integration: "stripe")  ← See what's available
          2. execute_integration_action(...)                  ← Execute with correct params
          
          **Common Stripe actions:**
          - list_customers: inputs: { limit: 10 }
          - create_customer: inputs: { email: "...", name: "..." }
          - get_customer: inputs: { customer_id: "cus_xxx" }
          
          **Common Mailgun actions:**
          - send_email: inputs: { to: "...", subject: "...", text: "..." }
          
          **Example:**
          ```
          execute_integration_action(
            integration: "stripe",
            action: "list_customers",
            inputs: { limit: 10 }
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
      # Accept both 'action' and 'operation' for backwards compatibility
      action_name = get_arg(args, :action) || get_arg(args, :operation)
      # Accept both 'inputs' and 'params' for backwards compatibility
      inputs = get_arg(args, :inputs) || get_arg(args, :params) || {}
      connection_id = get_arg(args, :connection_id)

      # Validate required args - accept either action or operation
      unless integration_slug.present? && action_name.present?
        missing = []
        missing << 'integration' unless integration_slug.present?
        missing << 'action (or operation)' unless action_name.present?
        return error_response("Missing required fields: #{missing.join(', ')}")
      end

      begin
        # Find the integration
        integration = find_integration(integration_slug)
        return error_response("Integration '#{integration_slug}' not found") unless integration

        # Find the action - try different formats
        action = IntegrationAction.for_entity(@entity)
                                  .where(integration: integration)
                                  .find_by(action_name: action_name)
        
        # Also try without prefix if action_name includes it (e.g., "stripe.list_customers" -> "list_customers")
        if action.nil? && action_name.include?('.')
          short_name = action_name.split('.').last
          action = IntegrationAction.for_entity(@entity)
                                    .where(integration: integration)
                                    .find_by(action_name: short_name)
        end

        # If no IntegrationAction found, fall back to direct operation execution
        unless action
          Rails.logger.info "[ExecuteIntegrationAction] No action found for '#{action_name}', falling back to direct operation"
          return execute_direct_operation(integration, action_name, inputs, connection_id)
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

    # Fallback to direct operation execution via UniversalIntegrationExecutor
    # This allows the tool to work even without pre-defined IntegrationAction records
    def execute_direct_operation(integration, operation_name, params, connection_id)
      # Find connection
      connection = find_connection(integration, connection_id)
      unless connection
        return error_response(
          "No active connection for #{integration.name}",
          hint: "Connect #{integration.name} first, then retry."
        )
      end

      # Execute via UniversalIntegrationExecutor
      result = UniversalIntegrationExecutor.execute(
        integration: integration,
        operation: operation_name,
        params: params,
        user: @user,
        entity: @entity,
        connection_id: connection.id
      )

      if result[:success]
        # Load canvas for list results
        if result[:data].is_a?(Array)
          load_direct_data_canvas(result[:data], integration, operation_name)
        end

        success_response(
          message: "Operation '#{operation_name}' completed successfully",
          operation: operation_name,
          integration: integration.name,
          data: slim_response(result[:data]),
          row_count: result[:row_count],
          artifact_id: result[:artifact_id]
        )
      else
        error_response(
          "Operation failed: #{result[:error]}",
          operation: operation_name,
          integration: integration.name,
          http_status: result[:status_code]
        )
      end
    end

    def load_direct_data_canvas(data, integration, operation_name)
      return if data.empty?

      columns = select_display_columns(data.first)

      @context[:canvas_suggestion] = "dynamic_canvas"
      @context[:canvas_data] = {
        title: "#{integration.name} - #{operation_name.titleize}",
        content: generate_direct_table_html(data, columns, integration, operation_name)
      }
    end

    def generate_direct_table_html(data, columns, integration, operation_name)
      <<~HTML
        <div class="action-response-data">
          <div class="response-header mb-3">
            <h4>#{operation_name.titleize}</h4>
            <p class="text-muted">Retrieved #{data.length} records from #{integration.name}</p>
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

