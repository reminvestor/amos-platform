module Tools
  class AggregateArtifactDataTool < BaseTool
    def self.metadata
      {
        name: 'aggregate_artifact_data',
        description: 'Perform aggregation operations on artifact data (group_by, count, sum, avg)',
        category: 'analytics',
        input_schema: {
          type: 'object',
          properties: {
            artifact_id: {
              type: 'integer',
              description: 'The ID of the artifact containing the data to aggregate'
            },
            operation: {
              type: 'string',
              enum: ['group_by_field', 'group_by_time', 'top_k', 'simple_stats'],
              description: 'The type of aggregation to perform'
            },
            field: {
              type: 'string',
              description: 'Field to group by (for group_by_field) or analyze (for top_k)'
            },
            time_field: {
              type: 'string',
              description: 'Time field for group_by_time operations'
            },
            time_bucket: {
              type: 'string',
              enum: ['hour', 'day', 'week', 'month', 'quarter', 'year'],
              description: 'Time bucket size for group_by_time'
            },
            aggregations: {
              type: 'array',
              description: 'List of aggregation functions to apply',
              items: {
                type: 'object',
                properties: {
                  function: {
                    type: 'string',
                    enum: ['count', 'sum', 'avg', 'min', 'max', 'distinct']
                  },
                  field: { type: 'string' },
                  alias: { type: 'string' }
                }
              }
            },
            k: {
              type: 'integer',
              description: 'Number of top results to return (for top_k)'
            }
          },
          required: ['artifact_id', 'operation']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      args = args.with_indifferent_access
      artifact_id = args[:artifact_id]
      operation = args[:operation]
      
      # Validate required args
      if error = validate_required_args(args, [:artifact_id, :operation])
        return error
      end
      
      # Find artifact
      artifact = find_artifact(artifact_id)
      return error_response("Artifact not found or access denied") unless artifact
      
      # Perform aggregation based on operation
      begin
        result = case operation
        when 'group_by_field'
          perform_group_by_field(artifact, args)
        when 'group_by_time'
          perform_group_by_time(artifact, args)
        when 'top_k'
          perform_top_k(artifact, args)
        when 'simple_stats'
          perform_simple_stats(artifact, args)
        else
          return error_response("Unknown operation: #{operation}")
        end
        
        # Load results into canvas if successful
        if result[:success]
          load_aggregation_canvas(result[:data], operation)
        end
        
        result
      rescue => e
        Rails.logger.error "Aggregation failed: #{e.message}"
        error_response("Aggregation failed: #{e.message}")
      end
    end
    
    private
    
    def find_artifact(artifact_id)
      # SECURITY: Always scope by entity to prevent cross-entity data access
      return nil unless entity
      Artifact.find_by(id: artifact_id, entity: entity)
    end
    
    def perform_group_by_field(artifact, args)
      field = args[:field]
      aggregations = args[:aggregations] || [{ function: 'count' }]
      
      return error_response("Field required for group_by_field") if field.blank?
      
      # Process sample data (in production, would query actual data)
      data = artifact.sample_rows || []
      grouped = data.group_by { |row| row[field] }
      
      results = grouped.map do |value, rows|
        result = { field => value }
        
        aggregations.each do |agg|
          agg_field = agg['field'] || agg[:field]
          agg_function = agg['function'] || agg[:function]
          agg_alias = agg['alias'] || agg[:alias] || "#{agg_function}_#{agg_field || 'count'}"
          
          result[agg_alias] = calculate_aggregate(rows, agg_function, agg_field)
        end
        
        result
      end
      
      success_response(
        data: results,
        operation: 'group_by_field',
        field: field,
        row_count: results.length
      )
    end
    
    def perform_top_k(artifact, args)
      field = args[:field]
      k = args[:k] || 10
      order_by = args[:order_by] || 'count'
      order_direction = args[:order_direction] || 'desc'
      
      return error_response("Field required for top_k") if field.blank?
      
      data = artifact.sample_rows || []
      grouped = data.group_by { |row| row[field] }
      
      # Calculate counts
      counts = grouped.map { |value, rows| { field => value, 'count' => rows.length } }
      
      # Sort and take top k
      sorted = counts.sort_by { |item| item[order_by] || 0 }
      sorted.reverse! if order_direction == 'desc'
      
      success_response(
        data: sorted.first(k),
        operation: 'top_k',
        field: field,
        k: k,
        total_unique: counts.length
      )
    end
    
    def perform_simple_stats(artifact, args)
      data = artifact.sample_rows || []
      
      # Ensure we have hashes with proper access
      return success_response(data: { total_rows: 0, fields: {} }, operation: 'simple_stats') if data.empty?
      return error_response("Sample data format error: expected array of hashes") unless data.first.is_a?(Hash)
      
      # Get numeric fields - ensure hash access works with string keys
      first_row = data.first.with_indifferent_access
      numeric_fields = first_row.select { |k, v| v.is_a?(Numeric) }.keys
      
      stats = {
        total_rows: data.length,
        fields: {}
      }
      
      numeric_fields.each do |field|
        values = data.map { |row| row[field] }.compact
        next if values.empty?
        
        stats[:fields][field] = {
          count: values.length,
          sum: values.sum,
          avg: values.sum.to_f / values.length,
          min: values.min,
          max: values.max
        }
      end
      
      success_response(
        data: stats,
        operation: 'simple_stats'
      )
    end
    
    def perform_group_by_time(artifact, args)
      time_field = args[:time_field]
      time_bucket = args[:time_bucket] || 'day'
      aggregations = args[:aggregations] || [{ function: 'count' }]
      
      return error_response("Time field required for group_by_time") if time_field.blank?
      
      data = artifact.sample_rows || []
      
      # Group by time bucket
      grouped = data.group_by do |row|
        time_value = row[time_field]
        next nil unless time_value
        
        time = Time.parse(time_value.to_s) rescue nil
        next nil unless time
        
        case time_bucket
        when 'hour'
          time.beginning_of_hour
        when 'day'
          time.beginning_of_day
        when 'week'
          time.beginning_of_week
        when 'month'
          time.beginning_of_month
        when 'quarter'
          time.beginning_of_quarter
        when 'year'
          time.beginning_of_year
        end
      end
      
      grouped.delete(nil) # Remove invalid time entries
      
      results = grouped.map do |time, rows|
        result = { 'time_bucket' => time.iso8601 }
        
        aggregations.each do |agg|
          agg_field = agg['field'] || agg[:field]
          agg_function = agg['function'] || agg[:function]
          agg_alias = agg['alias'] || agg[:alias] || "#{agg_function}_#{agg_field || 'count'}"
          
          result[agg_alias] = calculate_aggregate(rows, agg_function, agg_field)
        end
        
        result
      end.sort_by { |r| r['time_bucket'] }
      
      success_response(
        data: results,
        operation: 'group_by_time',
        time_field: time_field,
        time_bucket: time_bucket,
        row_count: results.length
      )
    end
    
    def calculate_aggregate(rows, function, field = nil)
      case function
      when 'count'
        rows.length
      when 'sum'
        rows.map { |r| r[field].to_f if r[field].is_a?(Numeric) }.compact.sum
      when 'avg'
        values = rows.map { |r| r[field].to_f if r[field].is_a?(Numeric) }.compact
        values.empty? ? 0 : values.sum / values.length
      when 'min'
        rows.map { |r| r[field] }.compact.min
      when 'max'
        rows.map { |r| r[field] }.compact.max
      when 'distinct'
        rows.map { |r| r[field] }.compact.uniq.length
      else
        0
      end
    end
    
    def load_aggregation_canvas(data, operation)
      # Generate HTML table for the aggregation results
      html = generate_aggregation_html(data, operation)
      
      @context[:canvas_suggestion] = 'dynamic_canvas'
      @context[:canvas_data] = {
        title: "Aggregation Results - #{operation.humanize}",
        content: html,
        artifact_type: 'aggregation'
      }
    end
    
    def generate_aggregation_html(data, operation)
      return "<p>No data to display</p>" if data.nil? || (data.respond_to?(:empty?) && data.empty?)
      
      # Handle different data structures
      return generate_stats_html(data) if operation == 'simple_stats' && data.is_a?(Hash)
      return "<p>No tabular data</p>" unless data.is_a?(Array) && data.first.is_a?(Hash)
      
      # Get column names
      columns = data.first.keys
      
      html = <<~HTML
        <div class="aggregation-results">
          <table class="table table-striped table-hover">
            <thead>
              <tr>
                #{columns.map { |col| "<th>#{col.to_s.humanize}</th>" }.join}
              </tr>
            </thead>
            <tbody>
              #{data.map { |row| 
                "<tr>#{columns.map { |col| "<td>#{format_value(row[col])}</td>" }.join}</tr>"
              }.join}
            </tbody>
          </table>
        </div>
      HTML
      
      html
    end
    
    def generate_stats_html(stats)
      html = <<~HTML
        <div class="stats-results">
          <p><strong>Total Rows:</strong> #{stats[:total_rows]}</p>
          <table class="table table-striped table-hover">
            <thead>
              <tr>
                <th>Field</th>
                <th>Count</th>
                <th>Sum</th>
                <th>Average</th>
                <th>Min</th>
                <th>Max</th>
              </tr>
            </thead>
            <tbody>
              #{(stats[:fields] || {}).map { |field, s|
                "<tr>
                  <td>#{field}</td>
                  <td>#{s[:count]}</td>
                  <td>#{format_value(s[:sum])}</td>
                  <td>#{format_value(s[:avg])}</td>
                  <td>#{format_value(s[:min])}</td>
                  <td>#{format_value(s[:max])}</td>
                </tr>"
              }.join}
            </tbody>
          </table>
        </div>
      HTML
      html
    end

    def format_value(value)
      case value
      when Float
        "%.2f" % value
      when Time, DateTime
        value.strftime("%Y-%m-%d %H:%M")
      when nil
        "-"
      else
        value.to_s
      end
    end
  end
end
