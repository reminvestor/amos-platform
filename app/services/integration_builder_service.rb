class IntegrationBuilderService
  def initialize(user, entity)
    @user = user
    @entity = entity
    @ai_service = BedrockService.new
  end
  
  def generate_integration_config(app_name, use_case, rag_store_id)
    Rails.logger.info "🔧 Building integration config for #{app_name}"
    
    # Query RAG store for relevant documentation
    rag_service = RagStoreService.new
    
    # Search for authentication patterns
    auth_results = rag_service.query_rag_store(
      rag_store_id,
      "authentication methods API key OAuth bearer token headers",
      top_k: 10
    )
    
    # Search for endpoint patterns
    endpoint_results = rag_service.query_rag_store(
      rag_store_id,
      "#{use_case} endpoints REST API paths",
      top_k: 15
    )
    
    # Search for base URL and versioning
    base_url_results = rag_service.query_rag_store(
      rag_store_id,
      "base URL API endpoint server host version",
      top_k: 5
    )
    
    # Combine context
    context = build_integration_context(auth_results, endpoint_results, base_url_results)
    
    # Use AI to generate integration configuration
    prompt = build_generation_prompt(app_name, use_case, context)
    
    ai_response = @ai_service.send_message(
      "You are an expert at creating API integrations. Generate a complete integration configuration based on the provided documentation.",
      prompt,
      temperature: 0.3,
      json_mode: true
    )
    
    # Parse and validate configuration
    config = JSON.parse(ai_response)
    validated_config = validate_and_enhance_config(config, app_name)
    
    # Create Integration record
    integration = create_integration_record(validated_config, rag_store_id)
    
    {
      success: true,
      integration_id: integration.id,
      config: validated_config,
      endpoints_created: integration.integration_operations.count,
      message: "Successfully generated integration configuration for #{app_name}"
    }
  rescue => e
    Rails.logger.error "Integration config generation failed: #{e.message}"
    { success: false, error: e.message }
  end
  
  def build_full_integration(integration_id, rag_store_id)
    integration = Integration.find(integration_id)
    
    Rails.logger.info "🏗️ Building full integration for #{integration.name}"
    
    # Query RAG store for all available endpoints
    rag_service = RagStoreService.new
    endpoint_results = rag_service.query_rag_store(
      rag_store_id,
      "all endpoints paths operations GET POST PUT DELETE PATCH list create update delete search filter",
      top_k: 50
    )
    
    # Group endpoints by resource
    grouped_endpoints = group_endpoints_by_resource(endpoint_results[:results])
    
    # Generate operations for each endpoint group
    operations_created = []
    
    grouped_endpoints.each do |resource, endpoints|
      endpoints.each do |endpoint_info|
        operation = create_operation_from_endpoint(integration, resource, endpoint_info)
        operations_created << operation if operation
      end
    end
    
    # Update integration status
    integration.update!(
      status: 'active',
      metadata: integration.metadata.merge(
        endpoints_count: operations_created.count,
        resources: grouped_endpoints.keys,
        build_completed_at: Time.current
      )
    )
    
    {
      success: true,
      integration_id: integration.id,
      operations_created: operations_created.count,
      resources: grouped_endpoints.keys,
      message: "Successfully built #{operations_created.count} endpoints for #{integration.name}"
    }
  rescue => e
    Rails.logger.error "Full integration build failed: #{e.message}"
    { success: false, error: e.message }
  end
  
  private
  
  def build_integration_context(auth_results, endpoint_results, base_url_results)
    {
      authentication: auth_results[:results].map { |r| r[:content] }.join("\n\n"),
      endpoints: endpoint_results[:results].map { |r| r[:content] }.join("\n\n"),
      base_info: base_url_results[:results].map { |r| r[:content] }.join("\n\n")
    }
  end
  
  def build_generation_prompt(app_name, use_case, context)
    <<~PROMPT
      Generate a complete integration configuration for #{app_name}.
      
      Use case: #{use_case}
      
      Documentation context:
      
      AUTHENTICATION INFO:
      #{context[:authentication]}
      
      RELEVANT ENDPOINTS:
      #{context[:endpoints]}
      
      BASE URL AND API INFO:
      #{context[:base_info]}
      
      Generate a JSON configuration with the following structure:
      {
        "name": "Integration display name",
        "auth_type": "oauth2|api_key|basic|bearer",
        "auth_config": {
          // Authentication configuration based on the auth type
        },
        "base_url": "https://api.example.com/v1",
        "headers": {
          // Common headers if needed
        },
        "rate_limit": {
          "requests_per_minute": 60,
          "requests_per_hour": 1000
        },
        "test_endpoint": {
          "name": "Test connection endpoint",
          "method": "GET",
          "path": "/endpoint/path",
          "description": "Description of what this does"
        },
        "initial_endpoints": [
          // 3-5 most important endpoints for the use case
          {
            "name": "endpoint_name",
            "method": "GET|POST|PUT|DELETE",
            "path": "/resource/path",
            "description": "What this endpoint does",
            "parameters": [
              // Query or path parameters
            ],
            "request_body_schema": {
              // For POST/PUT requests
            }
          }
        ]
      }
      
      Focus on creating a working configuration for: #{use_case}
    PROMPT
  end
  
  def validate_and_enhance_config(config, app_name)
    # Ensure required fields
    config['name'] ||= "#{app_name} Integration"
    config['auth_type'] ||= 'api_key'
    config['base_url'] ||= "https://api.#{app_name.downcase.gsub(/\s+/, '')}.com"
    
    # Validate auth config based on type
    config['auth_config'] ||= {}
    case config['auth_type']
    when 'api_key'
      config['auth_config']['header_name'] ||= 'X-API-Key'
      config['auth_config']['header_prefix'] ||= ''
    when 'bearer'
      config['auth_config']['header_name'] ||= 'Authorization'
      config['auth_config']['header_prefix'] ||= 'Bearer'
    when 'oauth2'
      config['auth_config']['grant_type'] ||= 'client_credentials'
      config['auth_config']['token_endpoint'] ||= "#{config['base_url']}/oauth/token"
    end
    
    # Ensure rate limits
    config['rate_limit'] ||= {}
    config['rate_limit']['requests_per_minute'] ||= 60
    
    config
  end
  
  def create_integration_record(config, rag_store_id)
    integration = Integration.create!(
      name: config['name'],
      provider: config['name'].split.first, # First word as provider
      auth_type: config['auth_type'],
      auth_config: config['auth_config'],
      settings: {
        base_url: config['base_url'],
        headers: config['headers'] || {},
        rate_limit: config['rate_limit']
      },
      status: 'draft',
      user: @user,
      entity: @entity,
      is_system: false,
      metadata: {
        rag_store_id: rag_store_id,
        generated_at: Time.current
      }
    )
    
    # Create test endpoint
    if config['test_endpoint']
      create_operation(integration, config['test_endpoint'], is_test: true)
    end
    
    # Create initial endpoints
    if config['initial_endpoints']
      config['initial_endpoints'].each do |endpoint_config|
        create_operation(integration, endpoint_config)
      end
    end
    
    integration
  end
  
  def create_operation(integration, endpoint_config, is_test: false)
    IntegrationOperation.create!(
      integration: integration,
      name: endpoint_config['name'],
      operation_id: endpoint_config['name'].underscore,
      http_method: endpoint_config['method'],
      endpoint_path: endpoint_config['path'],
      description: endpoint_config['description'],
      parameters_schema: build_parameters_schema(endpoint_config),
      request_schema: endpoint_config['request_body_schema'],
      response_schema: endpoint_config['response_schema'] || {},
      category: is_test ? 'test' : categorize_endpoint(endpoint_config),
      requires_auth: true,
      is_paginated: endpoint_config['path'].include?('list') || endpoint_config['method'] == 'GET',
      metadata: {
        is_test_endpoint: is_test,
        auto_generated: true
      }
    )
  rescue => e
    Rails.logger.error "Failed to create operation: #{e.message}"
    nil
  end
  
  def build_parameters_schema(endpoint_config)
    schema = {
      type: 'object',
      properties: {},
      required: []
    }
    
    # Extract path parameters
    if endpoint_config['path'].include?(':')
      endpoint_config['path'].scan(/:(\w+)/).each do |param|
        schema['properties'][param[0]] = {
          type: 'string',
          description: "ID of the #{param[0].gsub('_id', '').humanize.downcase}"
        }
        schema['required'] << param[0]
      end
    end
    
    # Add query parameters if specified
    if endpoint_config['parameters']
      endpoint_config['parameters'].each do |param|
        schema['properties'][param['name']] = {
          type: param['type'] || 'string',
          description: param['description']
        }
        schema['required'] << param['name'] if param['required']
      end
    end
    
    schema
  end
  
  def categorize_endpoint(endpoint_config)
    path = endpoint_config['path'].downcase
    method = endpoint_config['method'].upcase
    
    case
    when path.include?('auth') || path.include?('token')
      'authentication'
    when method == 'GET' && path !~ /:\w+$/
      'list'
    when method == 'GET'
      'read'
    when method == 'POST'
      'create'
    when method == 'PUT' || method == 'PATCH'
      'update'
    when method == 'DELETE'
      'delete'
    else
      'other'
    end
  end
  
  def group_endpoints_by_resource(endpoint_results)
    grouped = {}
    
    endpoint_results.each do |result|
      # Extract resource name from content
      if result[:content] =~ /(GET|POST|PUT|DELETE|PATCH)\s+\/(\w+)/
        resource = $2
        grouped[resource] ||= []
        grouped[resource] << result
      end
    end
    
    grouped
  end
  
  def create_operation_from_endpoint(integration, resource, endpoint_info)
    # Parse endpoint information from RAG result
    if endpoint_info[:content] =~ /(GET|POST|PUT|DELETE|PATCH)\s+(\/[\w\/\{\}:]+)/
      method = $1
      path = $2.gsub(/{(\w+)}/, ':\1') # Convert {id} to :id format
      
      operation_name = generate_operation_name(method, path, resource)
      
      create_operation(integration, {
        'name' => operation_name,
        'method' => method,
        'path' => path,
        'description' => extract_description(endpoint_info[:content])
      })
    end
  end
  
  def generate_operation_name(method, path, resource)
    parts = path.split('/').reject(&:empty?)
    
    case method
    when 'GET'
      path.include?(':') ? "Get #{resource.singularize}" : "List #{resource}"
    when 'POST'
      "Create #{resource.singularize}"
    when 'PUT', 'PATCH'
      "Update #{resource.singularize}"
    when 'DELETE'
      "Delete #{resource.singularize}"
    else
      "#{method.capitalize} #{resource}"
    end
  end
  
  def extract_description(content)
    # Try to extract description from content
    if content =~ /Description:\s*(.+?)(\n|$)/i
      $1.strip
    elsif content =~ /Summary:\s*(.+?)(\n|$)/i
      $1.strip
    else
      "Auto-generated endpoint"
    end
  end
end
