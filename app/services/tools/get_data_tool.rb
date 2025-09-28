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
      
      object_type = normalize_object_type(get_arg(args, :object_type))
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
      
      # Fix field names to match database schema
      fixed_filters = fix_field_names(filters, object_type)
      fixed_order_by = fix_field_names_in_order_by(options['order_by'], object_type)
      
      # Use UniversalQueryEngine to query the data
      query_engine = UniversalQueryEngine.new(user, entity)
      
      # Convert to format expected by query engine
      query_params = {
        objects: [object_type],
        filters: fixed_filters,
        limit: options['limit'] || 20,
        order_by: fixed_order_by,
        include_metrics: options['include_metrics'] != false,
        include_relationships: options['include_relationships']
      }
      
      result = query_engine.execute_get_data(query_params)
      
      if result[:success]
        # Extract data for the requested object type
        data = result[:data][object_type] || {}
        records = data[:records] || []
        
        success_response(
          object_type: object_type,
          count: records.length,
          records: records,
          total_count: data[:total_count] || records.length,
          has_more: data[:has_more] || false,
          filters_applied: filters,
          options_applied: options,
          metadata: result[:metadata]
        )
      else
        error_response(result[:error] || "Query failed")
      end
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
    
    def normalize_object_type(object_type)
      # Convert singular to plural forms expected by the query engine
      case object_type.to_s.downcase
      when 'campaign'
        'campaigns'
      when 'contact'
        'contacts'
      when 'contact_group'
        'contact_groups'
      when 'landing_page'
        'landing_pages'
      when 'email_template'
        'email_templates'
      when 'email_delivery'
        'email_deliveries'
      else
        object_type.to_s
      end
    end
    
    def fix_field_names(filters, object_type)
      return filters unless filters.is_a?(Hash)
      
      fixed_filters = {}
      
      filters.each do |key, value|
        fixed_key = map_field_name(key.to_s, object_type)
        fixed_filters[fixed_key] = value
      end
      
      fixed_filters
    end
    
    def fix_field_names_in_order_by(order_by, object_type)
      return order_by unless order_by.is_a?(String)
      
      # Split field and direction
      parts = order_by.split(' ')
      field = parts[0]
      direction = parts[1] || 'desc'
      
      fixed_field = map_field_name(field, object_type)
      "#{fixed_field} #{direction}"
    end
    
    def map_field_name(field, object_type)
      # Common field mappings
      case object_type.to_s.downcase
      when 'campaign', 'campaigns'
        case field.downcase
        when 'date', 'created', 'date_created'
          'created_at'
        when 'sent', 'date_sent', 'sent_date'
          'sent_at'
        else
          field
        end
      when 'contact', 'contacts'
        case field.downcase
        when 'date', 'created', 'date_created', 'signup_date'
          'created_at'
        when 'name'
          'first_name' # Most likely they want first_name when they say name
        else
          field
        end
      else
        field
      end
    end
  end
end
