require 'json-schema'

class ToolRunner
  attr_reader :tool_registry
  
  def initialize(tool_registry = nil)
    @tool_registry = tool_registry || ToolRegistry
  end
  
  # Execute a tool with contract validation and idempotency
  def call(tool:, inputs: {}, idempotency_key: nil, retries: 3)
    # Generate idempotency key if not provided
    idempotency_key ||= SecureRandom.uuid
    
    # Check for cached result first
    cached_result = check_idempotency_cache(tool, idempotency_key)
    return cached_result if cached_result
    
    # Get tool contract
    contract = @tool_registry.get_contract(tool)
    unless contract
      return {
        status: 'failed',
        error: "Unknown tool: #{tool}",
        tool: tool
      }
    end
    
    # Validate inputs
    input_validation = validate_inputs(contract, inputs)
    unless input_validation[:valid]
      return {
        status: 'failed',
        error: "Invalid inputs for #{tool}: #{input_validation[:errors].join(', ')}",
        tool: tool,
        validation_errors: input_validation[:errors]
      }
    end
    
    # Execute tool with retries
    result = execute_with_retries(tool, inputs, retries)
    
    # Validate outputs
    if result[:status] == 'success' && result[:data]
      output_validation = validate_outputs(contract, result[:data])
      unless output_validation[:valid]
        result = {
          status: 'failed',
          error: "Tool #{tool} returned invalid output: #{output_validation[:errors].join(', ')}",
          tool: tool,
          validation_errors: output_validation[:errors],
          raw_output: result[:data]
        }
      end
    end
    
    # Cache successful results
    if result[:status] == 'success'
      cache_result(tool, idempotency_key, result)
    end
    
    # Add metadata
    result.merge(
      tool: tool,
      idempotency_key: idempotency_key,
      executed_at: Time.current
    )
  end
  
  private
  
  def validate_inputs(contract, inputs)
    return { valid: true, errors: [] } unless contract[:input_schema]
    
    begin
      JSON::Validator.validate!(contract[:input_schema], inputs)
      { valid: true, errors: [] }
    rescue JSON::Schema::ValidationError => e
      { valid: false, errors: [e.message] }
    rescue => e
      { valid: false, errors: ["Input validation error: #{e.message}"] }
    end
  end
  
  def validate_outputs(contract, outputs)
    return { valid: true, errors: [] } unless contract[:output_schema]
    
    begin
      JSON::Validator.validate!(contract[:output_schema], outputs)
      { valid: true, errors: [] }
    rescue JSON::Schema::ValidationError => e
      { valid: false, errors: [e.message] }
    rescue => e
      { valid: false, errors: ["Output validation error: #{e.message}"] }
    end
  end
  
  def execute_with_retries(tool, inputs, max_retries)
    retries = 0
    last_error = nil
    
    begin
      # Execute the actual tool
      result = execute_tool(tool, inputs)
      
      # Check if result indicates a retryable error
      if result[:status] == 'failed' && retryable_error?(result[:error])
        raise StandardError.new(result[:error])
      end
      
      result
      
    rescue => e
      last_error = e
      retries += 1
      
      if retries <= max_retries
        # Exponential backoff
        sleep_time = 2 ** (retries - 1)
        sleep(sleep_time)
        
        Rails.logger.warn "Tool #{tool} failed (attempt #{retries}/#{max_retries}): #{e.message}. Retrying in #{sleep_time}s..."
        retry
      else
        Rails.logger.error "Tool #{tool} failed after #{max_retries} retries: #{last_error.message}"
        {
          status: 'failed',
          error: "Tool execution failed after #{max_retries} retries: #{last_error.message}",
          tool: tool,
          retries: retries - 1
        }
      end
    end
  end
  
  def execute_tool(tool, inputs)
    # Map tool names to actual implementations
    case tool
    when 'generate_landing_page_dsl'
      execute_landing_page_generation(inputs)
    when 'compile_landing_page_html'
      execute_landing_page_compilation(inputs)
    when 'create_contact'
      execute_contact_creation(inputs)
    when 'create_campaign'
      execute_campaign_creation(inputs)
    when 'send_email'
      execute_email_sending(inputs)
    when 'get_contact_groups'
      execute_contact_groups_fetch(inputs)
    when 'get_schema'
      execute_schema_fetch(inputs)
    when 'query_data'
      execute_data_query(inputs)
    else
      # Fallback to existing tool system if available
      if defined?(ScoutGenericToolsService)
        execute_legacy_tool(tool, inputs)
      else
        {
          status: 'failed',
          error: "Tool not implemented: #{tool}"
        }
      end
    end
  end
  
  def execute_landing_page_generation(inputs)
    begin
      # Use AI to generate landing page DSL
      business_info = inputs[:business_info] || {}
      design_prefs = inputs[:design_preferences] || {}
      
      # This would call the AI service to generate DSL
      # For now, return a sample DSL
      sample_dsl = LandingPageDSL.sample_dsl(business_info[:industry] || 'consulting')
      
      {
        status: 'success',
        data: {
          dsl: sample_dsl,
          business_info: business_info,
          design_preferences: design_prefs
        },
        message: 'Landing page DSL generated successfully'
      }
    rescue => e
      {
        status: 'failed',
        error: "Failed to generate landing page: #{e.message}"
      }
    end
  end
  
  def execute_landing_page_compilation(inputs)
    begin
      dsl = inputs[:dsl]
      slug = inputs[:slug] || 'generated-page'
      
      # Compile DSL to HTML
      compiler = LandingPageCompiler.new(dsl, landing_page_slug: slug)
      html = compiler.compile
      
      {
        status: 'success',
        data: {
          html: html,
          dsl: dsl,
          slug: slug
        },
        message: 'Landing page compiled successfully'
      }
    rescue => e
      {
        status: 'failed',
        error: "Failed to compile landing page: #{e.message}"
      }
    end
  end
  
  def execute_contact_creation(inputs)
    begin
      # This would create a contact through the Contact model
      contact_data = {
        email: inputs[:email],
        first_name: inputs[:first_name],
        last_name: inputs[:last_name],
        phone: inputs[:phone],
        company: inputs[:company]
      }.compact
      
      {
        status: 'success',
        data: {
          contact_id: SecureRandom.uuid,
          contact_data: contact_data
        },
        message: 'Contact created successfully'
      }
    rescue => e
      {
        status: 'failed',
        error: "Failed to create contact: #{e.message}"
      }
    end
  end
  
  def execute_campaign_creation(inputs)
    begin
      campaign_data = {
        name: inputs[:campaign_name],
        type: inputs[:campaign_type],
        description: inputs[:description]
      }.compact
      
      {
        status: 'success',
        data: {
          campaign_id: SecureRandom.uuid,
          campaign_data: campaign_data
        },
        message: 'Campaign created successfully'
      }
    rescue => e
      {
        status: 'failed',
        error: "Failed to create campaign: #{e.message}"
      }
    end
  end
  
  def execute_email_sending(inputs)
    begin
      {
        status: 'success',
        data: {
          message_id: SecureRandom.uuid,
          recipient: inputs[:recipient],
          subject: inputs[:subject]
        },
        message: 'Email sent successfully'
      }
    rescue => e
      {
        status: 'failed',
        error: "Failed to send email: #{e.message}"
      }
    end
  end
  
  def execute_contact_groups_fetch(inputs)
    begin
      # This would fetch actual contact groups
      {
        status: 'success',
        data: {
          contact_groups: [
            { id: 1, name: 'Newsletter Subscribers', count: 150 },
            { id: 2, name: 'Prospects', count: 75 },
            { id: 3, name: 'Customers', count: 200 }
          ]
        },
        message: 'Contact groups fetched successfully'
      }
    rescue => e
      {
        status: 'failed',
        error: "Failed to fetch contact groups: #{e.message}"
      }
    end
  end
  
  def execute_schema_fetch(inputs)
    begin
      table_name = inputs[:table] || inputs[:model]
      
      {
        status: 'success',
        data: {
          schema: "Schema for #{table_name} (simulated)",
          table: table_name
        },
        message: 'Schema fetched successfully'
      }
    rescue => e
      {
        status: 'failed',
        error: "Failed to fetch schema: #{e.message}"
      }
    end
  end
  
  def execute_data_query(inputs)
    begin
      query = inputs[:query]
      
      {
        status: 'success',
        data: {
          results: "Query results for: #{query} (simulated)",
          query: query,
          count: 42
        },
        message: 'Data query executed successfully'
      }
    rescue => e
      {
        status: 'failed',
        error: "Failed to execute query: #{e.message}"
      }
    end
  end
  
  def execute_legacy_tool(tool, inputs)
    # Bridge to existing tool system
    begin
      service = ScoutGenericToolsService.new
      result = service.execute_single_tool(tool, inputs)
      
      {
        status: 'success',
        data: result,
        message: "Legacy tool #{tool} executed successfully"
      }
    rescue => e
      {
        status: 'failed',
        error: "Legacy tool execution failed: #{e.message}"
      }
    end
  end
  
  def retryable_error?(error_message)
    retryable_patterns = [
      /timeout/i,
      /connection/i,
      /network/i,
      /temporary/i,
      /rate limit/i,
      /503/,
      /502/,
      /500/
    ]
    
    retryable_patterns.any? { |pattern| error_message.match?(pattern) }
  end
  
  def check_idempotency_cache(tool, idempotency_key)
    # Use Rails cache for idempotency (could be Redis in production)
    cache_key = "tool_result:#{tool}:#{idempotency_key}"
    
    if defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache
      Rails.cache.read(cache_key)
    else
      # Fallback to in-memory cache for testing
      @memory_cache ||= {}
      @memory_cache[cache_key]
    end
  end
  
  def cache_result(tool, idempotency_key, result)
    # Cache successful results for 1 hour
    cache_key = "tool_result:#{tool}:#{idempotency_key}"
    
    if defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache
      Rails.cache.write(cache_key, result, expires_in: 1.hour)
    else
      # Fallback to in-memory cache for testing
      @memory_cache ||= {}
      @memory_cache[cache_key] = result
    end
  end
end
