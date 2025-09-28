module Tools
  class GetDataTool < BaseTool
    def self.metadata
      {
        name: 'get_data',
        description: 'Query any data model with filters and options',
        category: 'data',
        input_schema: {
          type: 'object',
          properties: {
            object_type: {
              type: 'string',
              description: "The type of object to query (e.g., 'campaign', 'contact', 'landing_page')"
            },
            filters: {
              type: 'object',
              description: "Filters to apply (e.g., {status: 'sent', date_range: 'last_30_days'})"
            },
            options: {
              type: 'object',
              description: "Query options (e.g., {limit: 20, order_by: 'created_at desc', include_metrics: true})"
            }
          },
          required: ['object_type']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      object_type = get_arg(args, :object_type)
      filters = get_arg(args, :filters, {})
      options = get_arg(args, :options, {})
      
      # Validate required args
      if error = validate_required_args(args, [:object_type])
        return error
      end
      
      # Validate object type exists
      available_types = ScoutDataRegistry.available_object_types
      unless available_types.include?(object_type)
        return error_response(
          "Unknown object type: #{object_type}",
          available_types: available_types,
          suggestion: "Did you mean: #{find_closest_match(object_type, available_types)}?"
        )
      end
      
      # Process date range filters
      filters = process_date_filters(filters)
      
      # Query the data
      result = ScoutDataRegistry.query_data(
        object_type: object_type,
        filters: filters,
        options: options,
        entity: entity
      )
      
      success_response(
        object_type: object_type,
        count: result[:count],
        records: result[:records],
        total_count: result[:total_count],
        has_more: result[:has_more],
        filters_applied: filters,
        options_applied: options
      )
    rescue => e
      Rails.logger.error "GetDataTool error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      error_response("Query failed: #{e.message}")
    end
    
    private
    
    def process_date_filters(filters)
      return filters unless filters.is_a?(Hash)
      
      filters.transform_values do |value|
        case value
        when 'today'
          Date.current
        when 'yesterday'
          Date.yesterday
        when 'last_7_days'
          7.days.ago..Date.current
        when 'last_30_days'
          30.days.ago..Date.current
        when 'last_90_days'
          90.days.ago..Date.current
        when 'this_month'
          Date.current.beginning_of_month..Date.current
        when 'last_month'
          1.month.ago.beginning_of_month..1.month.ago.end_of_month
        when 'this_year'
          Date.current.beginning_of_year..Date.current
        else
          value
        end
      end
    end
    
    def find_closest_match(input, options)
      return nil if options.empty?
      
      input_downcase = input.downcase
      options.min_by { |opt| levenshtein_distance(input_downcase, opt.downcase) }
    end
    
    def levenshtein_distance(s1, s2)
      m = s1.length
      n = s2.length
      return n if m == 0
      return m if n == 0
      
      d = Array.new(m + 1) { Array.new(n + 1) }
      
      (0..m).each { |i| d[i][0] = i }
      (0..n).each { |j| d[0][j] = j }
      
      (1..n).each do |j|
        (1..m).each do |i|
          cost = s1[i - 1] == s2[j - 1] ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,      # deletion
            d[i][j - 1] + 1,      # insertion
            d[i - 1][j - 1] + cost # substitution
          ].min
        end
      end
      
      d[m][n]
    end
  end
end
