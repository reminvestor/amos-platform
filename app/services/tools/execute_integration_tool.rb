module Tools
  class ExecuteIntegrationTool < BaseTool
    # DEPRECATED: Use execute_integration_action instead. This tool is consolidated.
    
    def self.metadata
      {
        name: "execute_integration",
        description: <<~DESC.strip,
          DEPRECATED - Use execute_integration_action instead.
          
          Execute an API operation on any connected integration (Stripe, Twilio, HubSpot, etc.)

          🔍 DON'T KNOW THE OPERATIONS? Call list_operations(integration_slug: "stripe") first!
          
          📋 COMMON PATTERNS:
          • List records: operation="list_customers", params={limit: 10}
          • Get by ID: operation="get_customer", params={id: "cus_xxx"}
          • Create: operation="create_customer", params={email: "...", name: "..."}
          • Recent items: params={created: {gte: 1704067200}, limit: 10}
          
          ⏰ DATE FILTERING (Unix timestamps):
          • created[gte]: Records created after this timestamp
          • created[lte]: Records created before this timestamp
          • Use: params={created: {gte: UNIX_TIMESTAMP}}
          
          📊 PAGINATION:
          • limit: Number of records (default varies, often 10-100)
          • starting_after: Cursor for next page (use last record's ID)
          
          ⚠️ IF YOU DON'T KNOW: Use list_operations first, then try with discovered params!
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            integration: {
              type: "string",
              description: 'Integration slug (e.g., "stripe", "twilio", "hubspot"). Use lowercase.'
            },
            operation: {
              type: "string",
              description: 'Operation name (e.g., "list_customers", "get_charge", "create_contact"). Call list_operations to discover available operations.'
            },
            params: {
              type: "object",
              description: <<~PARAMS.strip
                Parameters for the operation. Common params:
                - limit: Number of records to return (e.g., 10, 100)
                - id: Record ID for get/update operations
                - created: Date filter object {gte: UNIX_TIMESTAMP, lte: UNIX_TIMESTAMP}
                - email, name, etc.: Resource-specific fields
              PARAMS
            },
            parameters: {
              type: "object",
              description: "Alternative key for params (use either params or parameters)"
            },
            connection_id: {
              type: "integer",
              description: "Optional: Specific connection ID (auto-selects if not provided)"
            }
          },
          required: [ "integration", "operation" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      integration = get_arg(args, :integration)
      operation = get_arg(args, :operation)
      params = get_arg(args, :params) || get_arg(args, :parameters, {})
      connection_id = get_arg(args, :connection_id)

      # Validate required args
      if error = validate_required_args(args, [ :integration, :operation ])
        return error
      end

      begin
        # Use universal executor
        result = UniversalIntegrationExecutor.execute(
          integration: integration,
          operation: operation,
          params: params,
          connection_id: connection_id,
          user: @user,
          entity: @entity
        )

        if result[:success]
          # Handle different response types
          if result[:artifact_id]
            # This is a list operation - load canvas
            load_data_canvas(result)
            Rails.logger.info "[ExecuteIntegration] Created artifact #{result[:artifact_id]} with #{result[:row_count]} records"
          else
            Rails.logger.info "[ExecuteIntegration] No artifact created for this response"
          end

          # IMPORTANT: For datasets with artifact, return ONLY summary + artifact_id
          # This prevents "input too long" errors - agent should use artifact_id with analyze_dataset
          response_data = if result[:artifact_id] && result[:data].is_a?(Array)
            # NEVER return full data when artifact exists - only summary
            {
              _note: "Data stored in artifact #{result[:artifact_id]}. Call analyze_dataset(artifact_id: #{result[:artifact_id]}, operations: [...]) to analyze.",
              sample: slim_records(result[:data].first(3)), # Only 3 samples!
              fields: result[:data].first&.keys&.first(15),
              total_records: result[:data].length
            }
          elsif result[:data].is_a?(Array) && result[:data].length > 5
            # No artifact but large array - still slim it down
            {
              _note: "Showing slim sample of #{result[:data].length} records",
              sample: slim_records(result[:data].first(5)),
              total_records: result[:data].length
            }
          else
            # Return full data for small responses or non-array data
            result[:data]
          end

          success_response(
            message: result[:message] || "Operation completed successfully",
            integration: result[:integration],
            operation: result[:operation],
            data: response_data,
            status_code: result[:status_code],
            artifact_id: result[:artifact_id],
            row_count: result[:row_count]
          )
        else
          error_response(
            result[:error],
            integration: result[:integration],
            operation: result[:operation],
            error_type: result[:error_type],
            error_details: result[:error_details],
            status_code: result[:status_code]
          )
        end
      rescue => e
        Rails.logger.error "Execute integration failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Execution failed: #{e.message}")
      end
    end

    private

    def load_data_canvas(result)
      return unless result[:data].is_a?(Array)

      @context[:canvas_suggestion] = "dynamic_canvas"
      @context[:canvas_data] = {
        title: "#{result[:integration]} - #{result[:operation]}",
        content: generate_table_html(result[:data], result),
        artifact_id: result[:artifact_id],
        artifact_type: "api_response"
      }
    end

    def generate_table_html(data, result)
      return "<p>No data returned</p>" if data.empty?

      # Select smart columns
      columns = select_display_columns(data.first)

      <<~HTML
        <div class="api-response-data">
          <div class="response-header mb-3">
            <h4>#{result[:operation_id] || result[:operation]}</h4>
            <p class="text-muted">Retrieved #{data.length} records from #{result[:integration]}</p>
          </div>
        #{'  '}
          <div class="table-responsive">
            <table class="table table-striped table-hover">
              <thead>
                <tr>
                  #{columns.map { |col| "<th>#{col.to_s.humanize}</th>" }.join}
                </tr>
              </thead>
              <tbody>
                #{data.first(50).map { |row|
                  "<tr>#{columns.map { |col|# {' '}
                    "<td>#{format_cell_value(row[col.to_s] || row[col.to_sym])}</td>"# {' '}
                  }.join}</tr>"
                }.join}
              </tbody>
            </table>
          </div>
        #{'  '}
          #{data.length > 50 ? "<p class='text-muted mt-3'>Showing first 50 of #{data.length} records</p>" : ''}
        </div>
      HTML
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

    def format_cell_value(value)
      case value
      when nil
        '<span class="text-muted">-</span>'
      when true
        '<span class="badge bg-success">Yes</span>'
      when false
        '<span class="badge bg-secondary">No</span>'
      when Time, DateTime, Date
        value.strftime("%Y-%m-%d %H:%M")
      when Hash, Array
        '<span class="text-muted">[Complex]</span>'
      else
        ERB::Util.html_escape(value.to_s.truncate(50))
      end
    end

    # Return slimmed down records with only key fields to reduce token usage
    def slim_records(records)
      return records unless records.is_a?(Array)

      priority_fields = %w[id amount status created currency paid email name type object customer]
      
      records.map do |record|
        next record unless record.is_a?(Hash)
        
        # Keep only priority fields + first few other simple fields
        slim = {}
        priority_fields.each do |field|
          slim[field] = record[field] if record.key?(field) || record.key?(field.to_sym)
        end
        
        # Add a few more non-nested fields if we have room
        record.each do |key, value|
          break if slim.keys.count >= 12
          next if slim.key?(key.to_s)
          next if value.is_a?(Hash) || value.is_a?(Array)
          slim[key.to_s] = value
        end
        
        slim
      end
    end

    # Extract field names from a record for schema info
    def extract_field_names(record)
      return [] unless record.is_a?(Hash)
      
      record.keys.map do |key|
        value = record[key]
        type = case value
               when Integer then "integer"
               when Float then "number"
               when TrueClass, FalseClass then "boolean"
               when Array then "array"
               when Hash then "object"
               when nil then "null"
               else "string"
               end
        { name: key.to_s, type: type }
      end
    end
  end
end
