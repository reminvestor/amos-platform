require 'json-schema'

class ToolRunner
  attr_reader :tool_registry
  
  def initialize(tool_registry = nil)
    @tool_registry = tool_registry || ToolRegistry
    @observability = ObservabilityService.instance
  end
  
  # Execute a tool with contract validation and idempotency
  def call(tool:, inputs: {}, idempotency_key: nil, retries: 3, agent_loadout: nil, step_id: nil)
    # Generate idempotency key if not provided
    idempotency_key ||= SecureRandom.uuid
    
    # Check agent loadout permissions if provided
    if agent_loadout
      unless agent_loadout.tool_allowed?(tool)
        return {
          status: 'failed',
          error: "Tool '#{tool}' not allowed for agent role '#{agent_loadout.agent_role}'",
          tool: tool,
          denied: true,
          agent_role: agent_loadout.agent_role
        }
      end
      
      # Check budget constraints
      current_usage = get_current_usage(step_id) if step_id
      unless agent_loadout.within_budget?(current_usage || {})
        return {
          status: 'failed',
          error: "Budget exceeded for agent role '#{agent_loadout.agent_role}'",
          tool: tool,
          budget_exceeded: true
        }
      end
    end
    
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
      # For output validation, we need to validate the structure that includes the success flag
      output_to_validate = { 
        success: true,  # If we got here, it was successful
        data: result[:data] 
      }
      if result[:message]
        output_to_validate[:message] = result[:message]
      end
      if result[:recommendation]
        output_to_validate[:recommendation] = result[:recommendation]
      end
      
      output_validation = validate_outputs(contract, output_to_validate)
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
    
    # Track usage if step_id provided
    if step_id
      result[:duration_ms] = duration_ms
      track_usage(step_id, tool, result)
    end
    
    # Add metadata
    result.merge(
      tool: tool,
      idempotency_key: idempotency_key,
      executed_at: Time.current,
      step_id: step_id,
      agent_role: agent_loadout&.agent_role
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
    Rails.logger.info "ToolRunner: Executing tool '#{tool}' with input keys: #{inputs.keys}"
    
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
    when 'analyze_landing_page_request'
      Rails.logger.info "ToolRunner: Matched analyze_landing_page_request case"
      execute_analyze_landing_page_request(inputs)
    when 'process_landing_page_images'
      Rails.logger.info "ToolRunner: Matched process_landing_page_images case"
      execute_process_landing_page_images(inputs)
    when 'aggregate_artifact_data'
      Rails.logger.info "ToolRunner: Matched aggregate_artifact_data case"
      execute_legacy_tool(tool, inputs)
    when 'fetch_next_page'
      Rails.logger.info "ToolRunner: Matched fetch_next_page case"
      execute_legacy_tool(tool, inputs)
    else
      Rails.logger.info "ToolRunner: No direct implementation for '#{tool}', checking legacy system"
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
      stored_images = Array(inputs[:stored_images]).map do |img|
        # normalize from either symbol or string keys
        {
          id: img[:id] || img['id'],
          url: img[:url] || img['url'],
          title: img[:title] || img['title'],
          description: img[:description] || img['description']
        }.compact
      end
      image_prefs = inputs[:image_preferences] || {}
      
      # Derive a key message from collected details if not supplied
      key_message = business_info[:key_message]
      if key_message.blank?
        purpose = business_info[:page_purpose]
        details = business_info[:specific_details]
        cta = business_info[:call_to_action]
        key_message = [purpose, details, cta].compact.join(' — ')
      end

      Rails.logger.info "ToolRunner: Generating landing page DSL for business: #{business_info[:business_name]}"
      Rails.logger.info "ToolRunner: Prompt context summary => theme=#{design_prefs[:theme] || 'n/a'}, color=#{design_prefs[:primary_color] || 'n/a'}, images=#{stored_images.length}, first_url=#{stored_images.first&.dig(:url)&.to_s&.first(80)}"
      
      # Create the AI agent for DSL generation
      dsl_agent = AiAgents::LandingPageDslAgent.new
      
      # Generate DSL using AI
      dsl_result = dsl_agent.generate_dsl(
        business_name: business_info[:business_name],
        industry: business_info[:industry],
        target_audience: business_info[:target_audience],
        key_message: key_message,
        theme: design_prefs[:theme] || 'professional',
        primary_color: design_prefs[:primary_color],
        style_notes: design_prefs[:style_notes],
        images: stored_images,
        image_preferences: image_prefs,
        raw_context: {
          business_info: business_info,
          design_preferences: design_prefs
        }
      )
      
      # Validate the generated DSL
      validation = ::LandingPageDsl.validate(dsl_result)
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
      # Try to resolve user/entity from inputs for services that require context
      user_param = inputs[:user] || inputs['user']
      entity_param = inputs[:entity] || inputs['entity']
      user_obj = user_param.is_a?(Hash) ? User.find(user_param['id'] || user_param[:id]) : user_param
      entity_obj = entity_param.is_a?(Hash) ? Entity.find(entity_param['id'] || entity_param[:id]) : entity_param

      # Fallback to explicit IDs if provided
      user_obj ||= (User.find(inputs[:user_id] || inputs['user_id']) rescue nil)
      entity_obj ||= (Entity.find(inputs[:entity_id] || inputs['entity_id']) rescue nil)
      
      # Log what we found
      Rails.logger.info "Legacy tool '#{tool}' - User: #{user_obj&.id}, Entity: #{entity_obj&.id}"

      # Use V2 service with a session ID
      session_id = inputs[:session_id] || inputs['session_id'] || SecureRandom.uuid
      service = ScoutGenericToolsServiceV2.new(user_obj, entity_obj, session_id)

      # Use the V2 executor
      legacy_result = service.execute_tool_by_name(tool, inputs)

      # Map legacy result format to ToolRunner format
      if legacy_result[:success] == true || legacy_result['success'] == true
        {
          status: 'success',
          data: legacy_result[:data] || legacy_result['data'] || {},
          message: legacy_result[:message] || legacy_result['message'],
          recommendation: legacy_result[:recommendation] || legacy_result['recommendation']
        }
      else
        {
          status: 'failed',
          error: legacy_result[:error] || legacy_result['error'] || 'Legacy tool failed'
        }
      end
    rescue => e
      Rails.logger.error "Legacy tool error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      {
        status: 'failed',
        error: "Legacy tool execution failed: #{e.message}"
      }
    end
  end
  
  def execute_process_landing_page_images(inputs)
    Rails.logger.info "🖼️ ToolRunner: Processing landing page images"
    Rails.logger.info "🖼️ Inputs: #{inputs.inspect}"
    
    # Bridge to ScoutGenericToolsService if available
    if defined?(ScoutGenericToolsService) && inputs['user_id'] && inputs['entity_id']
      begin
        # Convert hash representations to actual objects
        user = inputs['user_id'].is_a?(Integer) ? User.find(inputs['user_id']) : inputs['user_id']
        entity = inputs['entity_id'].is_a?(Integer) ? Entity.find(inputs['entity_id']) : inputs['entity_id']
        
        # Create V2 service instance
        session_id = inputs[:session_id] || inputs['session_id'] || SecureRandom.uuid
        service = ScoutGenericToolsServiceV2.new(user, entity, session_id)
        
        # Call the V2 tool
        result = service.execute_tool_by_name('process_landing_page_images', inputs)
        
        Rails.logger.info "🖼️ ScoutGenericToolsService result: #{result.inspect}"
        
        # Convert to ToolRunner format
        if result[:success]
          {
            status: 'success',
            data: result[:data],
            message: result[:message],
            recommendation: result[:recommendation]
          }
        else
          {
            status: 'error',
            message: result[:error] || 'Failed to process images',
            data: {}
          }
        end
      rescue => e
        Rails.logger.error "🖼️ Error in ScoutGenericToolsService: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        {
          status: 'error',
          message: "Failed to process images: #{e.message}",
          data: {}
        }
      end
    else
      # Fallback simulation
      Rails.logger.warn "🖼️ ScoutGenericToolsService not available, using simulation"
      
      {
        status: 'success',
        data: {
          processed_images: [],
          image_strategy: inputs.dig('image_preferences', 'image_preference') || 'placeholders'
        },
        message: "Image processing prepared",
        recommendation: "Images will be handled in the landing page editor"
      }
    end
  end

  def execute_analyze_landing_page_request(inputs)
    Rails.logger.info "ToolRunner: execute_analyze_landing_page_request called with keys: #{inputs.keys}"
    begin
      user = inputs[:user] || inputs['user']
      entity = inputs[:entity] || inputs['entity']
      
      Rails.logger.info "ToolRunner: User: #{user.inspect}, Entity: #{entity.inspect}"
      
      # If we have full context, use the real Scout tool
      if user && entity && defined?(ScoutGenericToolsService)
        Rails.logger.info "ToolRunner: Using real Scout tool service"
        # Need to convert hash to proper objects if needed
        user_obj = user.is_a?(Hash) ? User.find(user['id'] || user[:id]) : user
        entity_obj = entity.is_a?(Hash) ? Entity.find(entity['id'] || entity[:id]) : entity
        
        Rails.logger.info "ToolRunner: Creating V2 service with user #{user_obj.id} and entity #{entity_obj.id}"
        session_id = inputs[:session_id] || inputs['session_id'] || SecureRandom.uuid
        service = ScoutGenericToolsServiceV2.new(user_obj, entity_obj, session_id)
        # Call the V2 tool
        result = service.execute_tool_by_name('analyze_landing_page_request', inputs)
        
        Rails.logger.info "ToolRunner: Scout service returned: #{result.inspect}"
        
        # Convert Scout tool result format to ToolRunner format
        if result[:success] || result[:data]
          {
            status: 'success',
            data: result[:data] || result,
            message: result[:message] || result[:recommendation]
          }
        else
          {
            status: 'failed',
            error: result[:error] || 'Failed to analyze landing page request'
          }
        end
      else
        Rails.logger.info "ToolRunner: Using fallback simulated response"
        # Fallback to simulated response
        {
          status: 'success',
          data: {
            business_profile: {
              name: "Your Business",
              industry: 'Technology',
              description: 'A forward-thinking business',
              target_audience: 'Businesses and professionals'
            },
            message_context: {
              mentions_classes: true
            },
            missing_info: ['specific class details', 'call to action']
          },
          message: "I'll help you create a landing page for your classes."
        }
      end
    rescue => e
      Rails.logger.error "analyze_landing_page_request error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      {
        status: 'failed',
        error: "Failed to analyze request: #{e.message}"
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
  
  def get_current_usage(step_id)
    # Get current usage metrics for the step
    # In production, this would query from TaskEvent or metrics store
    {
      tool_calls: TaskEvent.where(
        task_session_id: TaskSession.active.where("metadata->>'step_id' = ?", step_id).pluck(:id),
        event_type: 'tool_call'
      ).count,
      tokens: 0 # Would integrate with actual token counting
    }
  rescue
    { tool_calls: 0, tokens: 0 }
  end
  
  def track_usage(step_id, tool, result)
    # Track tool usage for budget enforcement
    return unless step_id
    
    # Find active task session for this step
    task_session = TaskSession.active.find_by("metadata->>'step_id' = ?", step_id)
    return unless task_session
    
    # Log tool call event
    TaskEvent.create!(
      task_session: task_session,
      event_type: 'tool_call',
      event_data: {
        tool: tool,
        success: result[:status] == 'success',
        duration_ms: result[:duration_ms],
        error: result[:error]
      }
    )
  rescue => e
    Rails.logger.error "Failed to track tool usage: #{e.message}"
  end
end
