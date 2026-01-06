module Tools
  class GetDataTool < BaseTool
    def self.read_only?
      true  # This tool only queries data
    end
    
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
      
      # Validate object type exists (check both static and dynamic)
      available_types = ScoutDataRegistry.available_object_types(entity)
      unless available_types.include?(object_type)
        return error_response(
          "Unknown object type: #{object_type}",
          available_types: available_types,
          suggestion: "Did you mean: #{find_closest_match(object_type, available_types)}?"
        )
      end
      
      # Check if this is a dynamic module type
      config = ScoutDataRegistry.object_config(object_type, entity)
      if config && config[:dynamic]
        return query_dynamic_module(object_type, config, filters, options)
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
        
        # Get total count from the correct key (total_available from query engine)
        total_count = data[:total_available] || data[:total_count] || records.length
        
        success_response(
          object_type: object_type,
          count: records.length,
          records: records,
          total_count: total_count,
          has_more: total_count > records.length,
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
    
    def query_dynamic_module(object_type, config, filters, options)
      # Parse object_type - can be "module_slug" or "module_slug/model_name"
      parts = object_type.to_s.split('/')
      module_slug = parts[0]
      model_name = parts[1] # May be nil
      
      # Find the module
      app_module = entity.app_modules.active.find_by(slug: module_slug)
      app_module ||= entity.app_modules.active.find_by(slug: module_slug.singularize)
      
      unless app_module
        return error_response("Module not found: #{module_slug}")
      end
      
      # Get or load the model
      if model_name.present?
        # Specific model requested
        model_code = app_module.module_codes.models.find_by(name: model_name)
        model_code ||= app_module.module_codes.models.find_by(name: model_name.classify)
      else
        # No specific model - use the first/primary model, or list available models
        model_codes = app_module.module_codes.models.validated_or_deployed
        if model_codes.count > 1
          return success_response(
            message: "Module #{app_module.name} has multiple models. Please specify which one:",
            available_models: model_codes.map { |mc| "#{module_slug}/#{mc.name}" },
            example: "Use object_type: '#{module_slug}/#{model_codes.first.name}'"
          )
        end
        model_code = model_codes.first
      end
      
      unless model_code
        available = app_module.module_codes.models.pluck(:name)
        return error_response(
          "Model not found: #{model_name}",
          available_models: available.map { |m| "#{module_slug}/#{m}" }
        )
      end
      
      # Load the model class
      model_class = Modules::DynamicModelLoader.instance.get_model(app_module, model_code.name)
      unless model_class
        model_class = Modules::DynamicModelLoader.instance.load_model(model_code)
      end
      
      unless model_class
        return error_response("Could not load model: #{model_code.name}")
      end
      
      # Build query
      limit = options['limit'] || 20
      order_by = options['order_by'] || 'created_at desc'
      
      records = model_class.where(entity_id: entity.id)
      
      # Apply filters
      filters = process_date_filters(filters || {})
      filters.each do |field, value|
        if model_class.column_names.include?(field.to_s)
          records = records.where(field => value)
        end
      end
      
      # Apply ordering
      records = records.order(order_by).limit(limit)
      
      success_response(
        object_type: object_type,
        module_name: app_module.name,
        count: records.length,
        records: records.map { |r| r.attributes },
        total_count: model_class.where(entity_id: entity.id).count,
        has_more: model_class.where(entity_id: entity.id).count > limit,
        filters_applied: filters,
        options_applied: options
      )
    rescue => e
      Rails.logger.error "[GetDataTool] Dynamic module query error: #{e.message}"
      error_response("Module query failed: #{e.message}")
    end
    
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
      when "campaign"
        "campaigns"
      when "contact"
        "contacts"
      when "contact_group"
        "contact_groups"
      when "landing_page"
        "landing_pages"
      when "email_template"
        "email_templates"
      when "email_delivery"
        "email_deliveries"
      when "email_sequence"
        "email_sequences"
      when "sequence_step"
        "sequence_steps"
      when "sequence_enrollment"
        "sequence_enrollments"
      when "affiliate"
        "affiliates"
      when "commission"
        "commissions"
      when "payout"
        "payouts"
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
