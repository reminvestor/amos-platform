module Tools
  class InvokeOperationTool < BaseTool
    # DEPRECATED: Use execute_integration_action instead
    
    def self.metadata
      {
        name: "invoke_operation",
        description: "DEPRECATED - Use execute_integration_action instead. This tool has been consolidated.",
        category: "deprecated",
        input_schema: {
          type: "object",
          properties: {
            connection_id: {
              type: "integer",
              description: "ID of the connection to use"
            },
            operation_id: {
              type: "integer",
              description: "ID of the operation to invoke"
            },
            operation: {
              type: "string",
              description: "Operation identifier (alternative to operation_id)"
            },
            parameters: {
              type: "object",
              description: "Parameters to pass to the operation"
            },
            params: {
              type: "object",
              description: "Parameters (alternative spelling)"
            }
          },
          required: [ "connection_id" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      connection_id = get_arg(args, :connection_id)
      operation_id = get_arg(args, :operation_id)
      operation_name = get_arg(args, :operation)
      parameters = get_arg(args, :parameters) || get_arg(args, :params, {})

      # Validate required args
      if error = validate_required_args(args, [ :connection_id ])
        return error
      end

      begin
        # Find connection (scoped to user+entity for data privacy)
        connection = Connection.find_by(id: connection_id, user: user, entity: entity)
        return error_response("Connection not found or access denied") unless connection

        # Find operation
        operation = if operation_id
          connection.integration.integration_operations.find_by(id: operation_id)
        elsif operation_name
          connection.integration.integration_operations.find_by(operation_id: operation_name)
        else
          return error_response("Either operation_id or operation must be provided")
        end

        return error_response("Operation not found") unless operation

        # Execute the operation
        api_service = IntegrationApiService.new(connection)
        result = api_service.execute_operation(operation, params: parameters)

        Rails.logger.info "API Response: #{result.code} - #{result.message}"

        # Handle response
        if result.code.between?(200, 299)
          handle_successful_response(result, operation, connection)
        else
          handle_error_response(result, operation)
        end
      rescue => e
        Rails.logger.error "Operation invocation failed: #{e.message}"
        error_response("Operation failed: #{e.message}")
      end
    end

    private

    def handle_successful_response(response, operation, connection)
      data = response.parsed_response

      # For GET/list operations, create an artifact
      if operation.http_method == "GET" && data.is_a?(Array)
        artifact = create_data_artifact(data, operation, connection)

        # Load dynamic canvas with the data
        load_data_canvas(data, operation, artifact)

        success_response(
          operation: operation.name,
          method: operation.http_method,
          status_code: response.code,
          artifact_id: artifact.id,
          row_count: data.length,
          data: data,
          message: "Successfully retrieved #{data.length} records"
        )
      else
        # Non-list operation result
        success_response(
          operation: operation.name,
          method: operation.http_method,
          status_code: response.code,
          data: data,
          message: "Operation completed successfully"
        )
      end
    end

    def handle_error_response(response, operation)
      error_data = begin
        response.parsed_response
      rescue
        { error: response.message }
      end

      error_response(
        "Operation failed: #{response.message}",
        operation: operation.name,
        status_code: response.code,
        error_details: error_data
      )
    end

    def create_data_artifact(data, operation, connection)
      # Extract schema from data
      schema = extract_schema(data)

      # Get sample rows
      sample_rows = data.first(100)

      # Create artifact
      Artifact.create!(
        user: user,
        entity: entity,
        connection: connection,
        integration_operation: operation,
        artifact_type: "dataset",
        storage_ref: "memory://#{SecureRandom.uuid}",
        schema: schema,
        sample_rows: sample_rows,
        row_count: data.length,
        metadata: {
          operation: operation.operation_id,
          created_at: Time.current,
          parameters: @parameters
        }
      )
    end

    def extract_schema(data)
      return {} if data.empty?

      # Analyze first few rows to determine schema
      sample = data.first(10)
      schema = {}

      # Get all unique keys
      all_keys = sample.flat_map(&:keys).uniq

      all_keys.each do |key|
        # Determine type from non-nil values
        values = sample.map { |row| row[key] }.compact
        next if values.empty?

        types = values.map { |v| v.class.name }.uniq

        schema[key] = {
          type: determine_json_type(types.first),
          nullable: values.length < sample.length,
          examples: values.uniq.first(3)
        }
      end

      schema
    end

    def determine_json_type(ruby_type)
      case ruby_type
      when "String", "Symbol"
        "string"
      when "Integer", "Fixnum", "Bignum"
        "integer"
      when "Float", "BigDecimal"
        "number"
      when "TrueClass", "FalseClass"
        "boolean"
      when "Array"
        "array"
      when "Hash"
        "object"
      else
        "string"
      end
    end

    def load_data_canvas(data, operation, artifact)
      # Select smart columns for display
      columns = select_display_columns(data.first)

      # Generate HTML table
      html = generate_data_table_html(data, columns, operation)

      @context[:canvas_suggestion] = "dynamic_canvas"
      @context[:canvas_data] = {
        title: operation.name,
        content: html,
        artifact_id: artifact.id,
        artifact_type: "api_response"
      }
    end

    def select_display_columns(row)
      return [] unless row

      priority_columns = %w[id email name title description created_at status amount
                           balance currency plan subscription type category]

      # Get intersection of available and priority columns
      available = row.keys.map(&:to_s)
      selected = priority_columns & available

      # Add more columns if we have room
      if selected.length < 8
        other_columns = available - selected - [ "metadata", "raw_data", "object" ]
        selected += other_columns.first(8 - selected.length)
      end

      selected.first(10) # Cap at 10 columns
    end

    def generate_data_table_html(data, columns, operation)
      <<~HTML
        <div class="api-response-data">
          <div class="response-header">
            <h4>#{operation.name}</h4>
            <p class="text-muted">Retrieved #{data.length} records</p>
          </div>
        #{'  '}
          <div class="table-responsive">
            <table class="table table-striped table-hover">
              <thead>
                <tr>
                  #{columns.map { |col| "<th>#{col.humanize}</th>" }.join}
                </tr>
              </thead>
              <tbody>
                #{data.first(50).map { |row|
                  "<tr>#{columns.map { |col|# {' '}
                    "<td>#{format_cell_value(row[col])}</td>"# {' '}
                  }.join}</tr>"
                }.join}
              </tbody>
            </table>
          </div>
        #{'  '}
          #{data.length > 50 ? '<p class="text-muted mt-3">Showing first 50 of ' + data.length.to_s + ' records</p>' : ''}
        </div>
      HTML
    end

    def format_cell_value(value)
      case value
      when nil
        '<span class="text-muted">-</span>'
      when true
        '<span class="badge badge-success">Yes</span>'
      when false
        '<span class="badge badge-secondary">No</span>'
      when Time, DateTime
        value.strftime("%Y-%m-%d %H:%M")
      when Hash, Array
        '<span class="text-muted">[Complex]</span>'
      else
        value.to_s.truncate(50)
      end
    end
  end
end
