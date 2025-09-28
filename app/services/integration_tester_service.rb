class IntegrationTesterService
  include HTTParty
  
  def initialize(user, entity)
    @user = user
    @entity = entity
  end
  
  def test_endpoint(integration_id, credentials, test_params = {})
    integration = Integration.find(integration_id)
    
    Rails.logger.info "🧪 Testing integration: #{integration.name}"
    
    # Find test endpoint or first GET endpoint
    test_operation = find_test_operation(integration)
    
    unless test_operation
      return { success: false, error: "No test endpoint found for integration" }
    end
    
    # Create connection with credentials
    connection = create_test_connection(integration, credentials)
    
    # Execute test request
    result = execute_test_request(connection, test_operation, test_params)
    
    # Analyze results
    analyze_test_results(result, test_operation)
  rescue => e
    Rails.logger.error "Integration test failed: #{e.message}"
    { success: false, error: e.message, details: e.backtrace.first(5) }
  end
  
  def test_all_endpoints(integration_id, credentials)
    integration = Integration.find(integration_id)
    connection = create_test_connection(integration, credentials)
    
    results = {
      integration_id: integration.id,
      integration_name: integration.name,
      total_endpoints: integration.integration_operations.count,
      tested: 0,
      successful: 0,
      failed: 0,
      endpoint_results: []
    }
    
    integration.integration_operations.each do |operation|
      begin
        test_result = execute_test_request(connection, operation, {})
        analysis = analyze_test_results(test_result, operation)
        
        results[:tested] += 1
        if analysis[:success]
          results[:successful] += 1
        else
          results[:failed] += 1
        end
        
        results[:endpoint_results] << {
          operation_id: operation.id,
          name: operation.name,
          method: operation.http_method,
          path: operation.endpoint_path,
          result: analysis
        }
      rescue => e
        results[:tested] += 1
        results[:failed] += 1
        results[:endpoint_results] << {
          operation_id: operation.id,
          name: operation.name,
          error: e.message
        }
      end
    end
    
    results[:success] = results[:failed] == 0
    results[:message] = "Tested #{results[:tested]} endpoints: #{results[:successful]} successful, #{results[:failed]} failed"
    
    results
  end
  
  private
  
  def find_test_operation(integration)
    # First look for designated test endpoint
    integration.integration_operations.find { |op| op.metadata['is_test_endpoint'] } ||
    # Then look for a simple GET endpoint
    integration.integration_operations.find { |op| op.http_method == 'GET' && !op.endpoint_path.include?(':') } ||
    # Finally just use the first endpoint
    integration.integration_operations.first
  end
  
  def create_test_connection(integration, credentials)
    # Create a connection but don't save it
    Connection.new(
      name: "Test connection for #{integration.name}",
      integration: integration,
      user: @user,
      entity: @entity,
      credentials: encrypt_credentials(credentials, integration),
      status: 'testing'
    )
  end
  
  def encrypt_credentials(credentials, integration)
    # In production, use Rails encrypted credentials
    # For now, just structure the credentials properly
    case integration.auth_type
    when 'api_key'
      {
        api_key: credentials['api_key'] || credentials[:api_key]
      }
    when 'oauth2'
      {
        client_id: credentials['client_id'] || credentials[:client_id],
        client_secret: credentials['client_secret'] || credentials[:client_secret],
        access_token: credentials['access_token'] || credentials[:access_token],
        refresh_token: credentials['refresh_token'] || credentials[:refresh_token]
      }
    when 'basic'
      {
        username: credentials['username'] || credentials[:username],
        password: credentials['password'] || credentials[:password]
      }
    else
      credentials
    end
  end
  
  def execute_test_request(connection, operation, params)
    # Build full URL
    base_url = connection.integration.settings['base_url']
    full_url = build_url(base_url, operation.endpoint_path, params)
    
    # Build headers
    headers = build_headers(connection)
    
    # Build request options
    options = {
      headers: headers,
      timeout: 30
    }
    
    # Add query parameters for GET requests
    if operation.http_method == 'GET' && params.any?
      options[:query] = params
    end
    
    # Add body for POST/PUT requests
    if %w[POST PUT PATCH].include?(operation.http_method) && params.any?
      options[:body] = params.to_json
      headers['Content-Type'] = 'application/json'
    end
    
    # Log the request
    Rails.logger.info "🌐 #{operation.http_method} #{full_url}"
    Rails.logger.debug "Headers: #{headers.except('Authorization').inspect}"
    
    # Make the request
    start_time = Time.current
    response = HTTParty.send(
      operation.http_method.downcase.to_sym,
      full_url,
      options
    )
    end_time = Time.current
    
    {
      success: response.success?,
      status_code: response.code,
      response_time_ms: ((end_time - start_time) * 1000).round,
      headers: response.headers.to_h,
      body: parse_response_body(response),
      raw_body: response.body
    }
  rescue => e
    {
      success: false,
      error: e.message,
      error_class: e.class.name
    }
  end
  
  def build_url(base_url, path, params)
    url = base_url.chomp('/') + '/' + path.sub(/^\//, '')
    
    # Replace path parameters
    params.each do |key, value|
      if url.include?(":#{key}")
        url = url.gsub(":#{key}", value.to_s)
        params.delete(key)
      end
    end
    
    url
  end
  
  def build_headers(connection)
    headers = connection.integration.settings['headers']&.dup || {}
    
    # Add authentication headers
    case connection.integration.auth_type
    when 'api_key'
      auth_config = connection.integration.auth_config
      header_name = auth_config['header_name'] || 'X-API-Key'
      headers[header_name] = connection.credentials['api_key']
    when 'bearer'
      headers['Authorization'] = "Bearer #{connection.credentials['access_token'] || connection.credentials['api_key']}"
    when 'basic'
      credentials = Base64.strict_encode64("#{connection.credentials['username']}:#{connection.credentials['password']}")
      headers['Authorization'] = "Basic #{credentials}"
    end
    
    # Add default headers
    headers['User-Agent'] ||= 'AMOS Labs Integration Tester/1.0'
    headers['Accept'] ||= 'application/json'
    
    headers
  end
  
  def parse_response_body(response)
    return nil if response.body.blank?
    
    case response.content_type
    when /json/i
      JSON.parse(response.body)
    when /xml/i
      Hash.from_xml(response.body)
    else
      response.body
    end
  rescue => e
    Rails.logger.warn "Failed to parse response body: #{e.message}"
    response.body
  end
  
  def analyze_test_results(result, operation)
    if result[:success] == false && result[:error]
      # Request failed
      return {
        success: false,
        error: result[:error],
        message: "Request failed: #{result[:error]}",
        details: result
      }
    end
    
    status_code = result[:status_code]
    
    case status_code
    when 200..299
      # Success
      {
        success: true,
        message: "Successfully connected to #{operation.name}",
        status_code: status_code,
        response_time_ms: result[:response_time_ms],
        sample_data: extract_sample_data(result[:body]),
        auth_working: true
      }
    when 401
      {
        success: false,
        error: "Authentication failed",
        message: "Invalid credentials or authentication configuration",
        status_code: status_code,
        auth_working: false
      }
    when 403
      {
        success: false,
        error: "Permission denied",
        message: "Valid credentials but insufficient permissions",
        status_code: status_code,
        auth_working: true
      }
    when 404
      {
        success: false,
        error: "Endpoint not found",
        message: "The endpoint path may be incorrect: #{operation.endpoint_path}",
        status_code: status_code
      }
    when 429
      {
        success: false,
        error: "Rate limited",
        message: "Too many requests. Check rate limit configuration",
        status_code: status_code,
        retry_after: result[:headers]['retry-after']
      }
    when 500..599
      {
        success: false,
        error: "Server error",
        message: "The API server encountered an error",
        status_code: status_code
      }
    else
      {
        success: false,
        error: "Unexpected response",
        message: "Received status code #{status_code}",
        status_code: status_code,
        body: result[:body]
      }
    end
  end
  
  def extract_sample_data(body)
    return nil unless body
    
    case body
    when Array
      {
        type: 'array',
        count: body.length,
        sample: body.first(3)
      }
    when Hash
      {
        type: 'object',
        keys: body.keys,
        sample: body.slice(*body.keys.first(10))
      }
    else
      {
        type: body.class.name.downcase,
        sample: body.to_s.first(200)
      }
    end
  end
end
