class ScoutUniversalTools
  def initialize(user, entity)
    @user = user
    @entity = entity
    @query_engine = UniversalQueryEngine.new(user, entity)
  end
  
  # Universal tool definitions for Claude function calling
  TOOLS = {
    'get_data' => {
      description: 'Retrieve and query any data objects in the system with filtering and metrics',
      parameters: {
        objects: { 
          type: 'array', 
          description: 'Object types to query: campaigns, landing_pages, contacts, contact_groups, email_templates, email_deliveries',
          required: true
        },
        filters: { 
          type: 'object', 
          description: 'Filtering criteria like {date_range: "last_30_days", status: "sent"} or {created_at: "this_month"}',
          properties: {
            date_range: { type: 'string', description: 'today, yesterday, last_7_days, last_30_days, this_month, last_month' },
            status: { type: 'string', description: 'Filter by status field' },
            created_at: { type: 'string', description: 'Date filter for creation date' },
            sent_at: { type: 'string', description: 'Date filter for send date' }
          }
        },
        include_metrics: { 
          type: 'boolean', 
          default: true,
          description: 'Include performance metrics like open_rate, click_rate, engagement_score' 
        },
        include_relationships: { 
          type: 'array', 
          description: 'Related objects to include: email_deliveries, contact_groups, campaigns, etc.' 
        },
        include_relationship_counts: {
          type: 'boolean',
          default: false,
          description: 'Include counts of related objects'
        },
        limit: { 
          type: 'integer', 
          default: 10,
          maximum: 100,
          description: 'Maximum number of records to return per object type' 
        },
        order_by: {
          type: 'string',
          description: 'Field to order by with direction, e.g., "created_at desc" or "name asc"'
        }
      }
    },
    
    'analyze_data' => {
      description: 'Perform intelligent analysis on data with context and specific questions',
      parameters: {
        data_context: { 
          type: 'string', 
          description: 'Description of what data to analyze - either from previous get_data results or user context',
          required: true
        },
        analysis_type: { 
          type: 'string',
          description: 'Type of analysis to perform',
          enum: ['trends', 'comparison', 'performance', 'forecasting', 'correlation', 'summary', 'optimization'],
          required: true
        },
        user_question: { 
          type: 'string', 
          description: 'The specific question or goal for the analysis',
          required: true
        },
        benchmark_against: { 
          type: 'string', 
          description: 'What to compare against',
          enum: ['previous_period', 'industry_standards', 'goals', 'best_performing', 'average']
        },
        time_period: {
          type: 'string',
          description: 'Time period for analysis if relevant',
          enum: ['daily', 'weekly', 'monthly', 'quarterly']
        }
      }
    },
    
    'create_object' => {
      description: 'Create new objects like campaigns, landing pages, contacts, or contact groups',
      parameters: {
        object_type: { 
          type: 'string', 
          description: 'Type of object to create',
          enum: ['campaigns', 'landing_pages', 'contacts', 'contact_groups', 'email_templates'],
          required: true
        },
        object_data: { 
          type: 'object', 
          description: 'Data for the new object - must include required fields based on object type',
          required: true
        },
        auto_populate: { 
          type: 'boolean', 
          default: true,
          description: 'Whether to intelligently populate optional fields based on context and best practices' 
        }
      }
    }
  }.freeze
  
  # Execute a tool by name
  def execute_tool(tool_name, parameters)
    case tool_name.to_s
    when 'get_data'
      execute_get_data(parameters)
    when 'analyze_data'
      execute_analyze_data(parameters)
    when 'create_object'
      execute_create_object(parameters)
    else
      { error: "Unknown tool: #{tool_name}" }
    end
  end
  
  # Get tool definitions formatted for Claude
  def self.for_claude_function_calling
    TOOLS
  end
  
  # Get available data objects for Claude context
  def self.available_data_objects
    ScoutDataRegistry.for_claude_function_calling
  end
  
  private
  
  def execute_get_data(params)
    # Validate required parameters
    return { error: 'objects parameter is required' } unless params[:objects].present?
    
    # Execute query using the universal query engine
    result = @query_engine.execute_get_data(params)
    
    if result[:success]
      # Format for AI consumption
      {
        success: true,
        data: result[:data],
        metadata: result[:metadata],
        summary: generate_data_summary(result[:data], params),
        ai_context: format_for_ai_context(result[:data], params)
      }
    else
      result
    end
  end
  
  def execute_analyze_data(params)
    # Validate required parameters
    required_params = [:data_context, :analysis_type, :user_question]
    missing_params = required_params.select { |param| params[param].blank? }
    
    if missing_params.any?
      return { error: "Missing required parameters: #{missing_params.join(', ')}" }
    end
    
    begin
      # Perform analysis based on type
      analysis_result = case params[:analysis_type]
      when 'trends'
        analyze_trends(params)
      when 'comparison'
        analyze_comparison(params)
      when 'performance'
        analyze_performance(params)
      when 'summary'
        analyze_summary(params)
      when 'correlation'
        analyze_correlation(params)
      when 'optimization'
        analyze_optimization(params)
      else
        { error: "Unsupported analysis type: #{params[:analysis_type]}" }
      end
      
      if analysis_result[:error]
        analysis_result
      else
        {
          success: true,
          analysis_type: params[:analysis_type],
          user_question: params[:user_question],
          insights: analysis_result[:insights],
          recommendations: analysis_result[:recommendations],
          data_summary: analysis_result[:data_summary],
          ai_context: analysis_result[:ai_context]
        }
      end
    rescue => e
      Rails.logger.error "Analysis error: #{e.message}"
      { error: "Analysis failed: #{e.message}" }
    end
  end
  
  def execute_create_object(params)
    # Validate required parameters
    return { error: 'object_type is required' } unless params[:object_type].present?
    return { error: 'object_data is required' } unless params[:object_data].present?
    
    object_type = params[:object_type]
    
    # Check if object type is creatable
    unless ScoutDataRegistry.creatable?(object_type)
      return { error: "Cannot create objects of type: #{object_type}" }
    end
    
    begin
      # Get creation schema
      schema = ScoutDataRegistry.creation_schema(object_type)
      model_class = ScoutDataRegistry.model_class(object_type)
      
      # Validate and prepare data
      creation_data = prepare_creation_data(params[:object_data], schema, params[:auto_populate])
      
      # Validate required fields
      missing_fields = schema[:required] - creation_data.keys.map(&:to_s)
      if missing_fields.any?
        return { error: "Missing required fields: #{missing_fields.join(', ')}" }
      end
      
      # Add entity scoping
      creation_data[:entity_id] = @entity.id
      creation_data[:user_id] = @user.id if model_class.column_names.include?('user_id')
      
      # Create the object
      new_object = model_class.create!(creation_data)
      
      {
        success: true,
        object_type: object_type,
        object_id: new_object.id,
        object_data: format_created_object(new_object, object_type),
        message: "Successfully created #{object_type.singularize}: #{new_object.name || new_object.title || new_object.email || new_object.id}"
      }
    rescue ActiveRecord::RecordInvalid => e
      { error: "Validation failed: #{e.record.errors.full_messages.join(', ')}" }
    rescue => e
      Rails.logger.error "Object creation error: #{e.message}"
      { error: "Creation failed: #{e.message}" }
    end
  end
  
  # Analysis methods
  def analyze_trends(params)
    # Get recent data to analyze trends
    trend_data = @query_engine.execute_get_data({
      objects: extract_objects_from_context(params[:data_context]),
      filters: { created_at: 'last_90_days' },
      include_metrics: true,
      order_by: 'created_at asc'
    })
    
    if trend_data[:success]
      insights = generate_trend_insights(trend_data[:data], params[:user_question])
      {
        insights: insights,
        recommendations: generate_trend_recommendations(insights),
        data_summary: summarize_trend_data(trend_data[:data]),
        ai_context: "Trend analysis shows #{insights[:summary]}"
      }
    else
      { error: "Could not retrieve data for trend analysis" }
    end
  end
  
  def analyze_performance(params)
    # Get performance data
    performance_data = @query_engine.execute_get_data({
      objects: extract_objects_from_context(params[:data_context]),
      filters: { created_at: 'last_30_days' },
      include_metrics: true,
      include_relationship_counts: true
    })
    
    if performance_data[:success]
      insights = generate_performance_insights(performance_data[:data], params[:user_question])
      {
        insights: insights,
        recommendations: generate_performance_recommendations(insights),
        data_summary: summarize_performance_data(performance_data[:data]),
        ai_context: "Performance analysis reveals #{insights[:summary]}"
      }
    else
      { error: "Could not retrieve data for performance analysis" }
    end
  end
  
  def analyze_summary(params)
    # Get comprehensive data for summary
    summary_data = @query_engine.execute_get_data({
      objects: extract_objects_from_context(params[:data_context]),
      include_metrics: true,
      include_relationship_counts: true,
      limit: 20
    })
    
    if summary_data[:success]
      insights = generate_summary_insights(summary_data[:data], params[:user_question])
      {
        insights: insights,
        recommendations: [],
        data_summary: insights,
        ai_context: "Data summary: #{insights[:overview]}"
      }
    else
      { error: "Could not retrieve data for summary" }
    end
  end
  
  # Helper methods for analysis
  def extract_objects_from_context(context)
    # Simple keyword matching - could be made more sophisticated
    objects = []
    objects << 'campaigns' if context.match?(/campaign|email/i)
    objects << 'landing_pages' if context.match?(/landing.page|page|conversion/i)
    objects << 'contacts' if context.match?(/contact|audience|subscriber/i)
    objects << 'contact_groups' if context.match?(/group|segment/i)
    
    objects.any? ? objects : ['campaigns']  # Default to campaigns
  end
  
  def generate_data_summary(data, params)
    summary = {}
    
    data.each do |object_type, object_data|
      records = object_data[:records] || []
      
      summary[object_type] = {
        count: records.length,
        date_range: extract_date_range(records),
        key_metrics: extract_key_metrics(records)
      }
    end
    
    summary
  end
  
  def format_for_ai_context(data, params)
    context_parts = []
    
    data.each do |object_type, object_data|
      records = object_data[:records] || []
      next if records.empty?
      
      metrics_summary = summarize_metrics_for_ai(records)
      context_parts << "#{object_type}: #{records.length} records#{metrics_summary}"
    end
    
    context_parts.join('; ')
  end
  
  def summarize_metrics_for_ai(records)
    return '' if records.empty?
    
    metrics = records.map { |r| r[:metrics] }.compact
    return '' if metrics.empty?
    
    # Calculate averages for key metrics
    avg_metrics = {}
    metrics.first.keys.each do |metric|
      values = metrics.map { |m| m[metric] }.compact.select { |v| v.is_a?(Numeric) }
      avg_metrics[metric] = (values.sum.to_f / values.length).round(2) if values.any?
    end
    
    key_metrics = avg_metrics.select { |k, v| k.match?(/rate|score/) && v > 0 }
    return '' if key_metrics.empty?
    
    " (avg: #{key_metrics.map { |k, v| "#{k}: #{v}%" }.join(', ')})"
  end
  
  # More helper methods would go here for specific analysis types...
  def generate_trend_insights(data, question)
    { summary: "trend analysis completed", details: [] }
  end
  
  def generate_performance_insights(data, question)
    { summary: "performance analysis completed", details: [] }
  end
  
  def generate_summary_insights(data, question)
    { overview: "data summary generated", details: data }
  end
  
  def generate_trend_recommendations(insights)
    []
  end
  
  def generate_performance_recommendations(insights)
    []
  end
  
  def summarize_trend_data(data)
    {}
  end
  
  def summarize_performance_data(data)
    {}
  end
  
  def extract_date_range(records)
    return nil if records.empty?
    
    dates = records.map { |r| r['created_at'] }.compact.map { |d| Date.parse(d) rescue nil }.compact
    return nil if dates.empty?
    
    "#{dates.min} to #{dates.max}"
  end
  
  def extract_key_metrics(records)
    return {} if records.empty?
    
    metrics = records.map { |r| r[:metrics] }.compact
    return {} if metrics.empty?
    
    # Return first record's metrics as sample
    metrics.first.select { |k, v| v.is_a?(Numeric) }
  end
  
  def prepare_creation_data(object_data, schema, auto_populate)
    data = object_data.with_indifferent_access
    
    if auto_populate
      # Apply intelligent defaults
      schema[:defaults]&.each do |field, default_value|
        next if data[field].present?
        
        if default_value.respond_to?(:call)
          # Skip callable defaults for now - would need entity context
          next
        else
          data[field] = default_value
        end
      end
    end
    
    data
  end
  
  def format_created_object(object, object_type)
    config = ScoutDataRegistry.object_config(object_type)
    result = {}
    
    config[:queryable_fields].each do |field|
      result[field] = object.send(field) if object.respond_to?(field)
    end
    
    result
  end
end 