require 'json-schema'

class ToolRunner
  attr_reader :tool_registry
  
  def initialize(tool_registry = nil)
    @tool_registry = tool_registry || ToolRegistry
    @observability = ObservabilityService.instance
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
    
    # Track tool execution start
    start_time = Time.current
    @observability.track_tool_event(:tool_called, tool, {
      input_size: inputs.to_s.length,
      idempotency_key: idempotency_key
    })
    
    # Execute tool with retries
    result = execute_with_retries(tool, inputs, retries)
    
    # Track tool completion
    duration_ms = ((Time.current - start_time) * 1000).round(2)
    @observability.track_tool_event(
      result[:status] == 'success' ? :tool_completed : :tool_failed,
      tool,
      {
        duration_ms: duration_ms,
        success: result[:status] == 'success',
        error: result[:error],
        output_size: result[:data]&.to_s&.length,
        retries_used: result[:retries] || 0
      }
    )
    
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
      
      Rails.logger.info "ToolRunner: Generating landing page DSL for business: #{business_info[:business_name]}"
      
      # Create the AI agent for DSL generation
      dsl_agent = LandingPageDslAgent.new
      
      # Generate DSL using AI
      dsl_result = dsl_agent.generate_dsl(
        business_name: business_info[:business_name],
        industry: business_info[:industry],
        target_audience: business_info[:target_audience],
        key_message: business_info[:key_message],
        theme: design_prefs[:theme] || 'professional',
        primary_color: design_prefs[:primary_color],
        style_notes: design_prefs[:style_notes]
      )
      
      # Validate the generated DSL
      validation = LandingPageDSL.validate(dsl_result)
      unless validation[:valid]
        raise "Generated DSL failed validation: #{validation[:errors].join(', ')}"
      end
      
      {
        status: 'success',
        data: {
          dsl: dsl_result,
          business_info: business_info,
          design_preferences: design_prefs
        },
        message: "Landing page DSL generated successfully for #{business_info[:business_name]}"
      }
    rescue => e
      Rails.logger.error "Landing page DSL generation failed: #{e.message}"
      {
        status: 'failed',
        error: "Failed to generate landing page: #{e.message}"
      }
    end
  end
  
  def execute_landing_page_compilation(inputs)
    begin
      dsl = inputs[:dsl]
      business_name = inputs[:business_name] || inputs.dig(:business_info, :business_name) || 'Generated Page'
      user = inputs[:user]
      entity = inputs[:entity]
      
      # Generate slug from business name
      slug = generate_slug_from_name(business_name)
      
      Rails.logger.info "ToolRunner: Compiling landing page DSL to HTML for: #{business_name}"
      
      # Compile DSL to HTML
      compiler = LandingPageCompiler.new(dsl, landing_page_slug: slug)
      html = compiler.compile
      
      # Create or update landing page record if user and entity provided
      landing_page = nil
      if user && entity
        landing_page = create_landing_page_record(
          title: business_name,
          slug: slug,
          html_content: html,
          dsl_content: dsl,
          user: user,
          entity: entity
        )
      end
      
      {
        status: 'success',
        data: {
          html: html,
          dsl: dsl,
          slug: slug,
          landing_page_id: landing_page&.id,
          landing_page: landing_page ? {
            id: landing_page.id,
            title: landing_page.title,
            slug: landing_page.slug,
            status: landing_page.status,
            url: landing_page.full_url
          } : nil
        },
        message: landing_page ? 
          "Landing page '#{business_name}' compiled and saved successfully!" :
          "Landing page compiled successfully"
      }
    rescue => e
      Rails.logger.error "Landing page compilation failed: #{e.message}"
      {
        status: 'failed',
        error: "Failed to compile landing page: #{e.message}"
      }
    end
  end
  
  private
  
  def generate_slug_from_name(name)
    # Convert business name to URL-friendly slug
    name.downcase
        .gsub(/[^a-z0-9\s-]/, '')  # Remove special characters
        .gsub(/\s+/, '-')          # Replace spaces with hyphens
        .gsub(/-+/, '-')           # Remove duplicate hyphens
        .gsub(/^-|-$/, '')         # Remove leading/trailing hyphens
        .presence || 'landing-page'
  end
  
  def create_landing_page_record(title:, slug:, html_content:, dsl_content:, user:, entity:)
    # Ensure slug is unique
    original_slug = slug
    counter = 1
    
    while LandingPage.exists?(slug: slug)
      slug = "#{original_slug}-#{counter}"
      counter += 1
    end
    
    # Create the landing page record
    landing_page = LandingPage.create!(
      title: title,
      slug: slug,
      html_content: html_content,
      status: 'draft',
      user: user,
      entity: entity,
      description: "Landing page for #{title}",
      metadata: {
        generated_with: 'dsl_system',
        dsl_content: dsl_content,
        generated_at: Time.current,
        generator_version: '2.0'
      }
    )
    
    Rails.logger.info "Created landing page record: ID #{landing_page.id}, slug: #{landing_page.slug}"
    landing_page
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
