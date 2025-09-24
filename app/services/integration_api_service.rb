class IntegrationApiService
  include HTTParty
  
  def initialize(connection)
    @connection = connection
    @integration = connection.integration
    @credential = connection.active_credential
    
    raise "No active credentials for connection" unless @credential
  end
  
  def test_connection
    # Find the test connection operation
    test_operation = @integration.integration_operations
                                 .where("operation_id LIKE ?", "%.test_connection.%")
                                 .first
    
    return { success: false, error: "No test operation defined for this integration" } unless test_operation
    
    begin
      response = execute_operation(test_operation)
      
      if response.success?
        {
          success: true,
          status_code: response.code,
          message: "Connection successful",
          data: response.parsed_response
        }
      else
        # Extract error message from response
        error_message = extract_error_message(response)
        {
          success: false,
          status_code: response.code,
          error: error_message || "API request failed with status #{response.code}",
          data: response.parsed_response
        }
      end
    rescue => e
      status_code = nil
      if e.respond_to?(:response) && e.response
        status_code = e.response.code
      elsif e.is_a?(HTTParty::ResponseError)
        status_code = e.response.code
      end
      
      {
        success: false,
        error: e.message,
        status_code: status_code
      }
    end
  end
  
  def execute_operation(operation, params: {}, body: nil)
    # Build the request
    url = build_url(operation, params)
    headers = build_headers
    
    # Apply query parameters
    query_params = params.except(*extract_path_params(operation.path_template))
    query_params.merge!(@credential.build_auth_params) if @credential.auth_method == 'query'
    
    # Log the request
    correlation_id = SecureRandom.uuid
    log_start = Time.current
    
    begin
      response = case operation.http_method
      when 'GET'
        self.class.get(url, headers: headers, query: query_params)
      when 'POST'
        self.class.post(url, headers: headers, query: query_params, body: body&.to_json)
      when 'PUT'
        self.class.put(url, headers: headers, query: query_params, body: body&.to_json)
      when 'PATCH'
        self.class.patch(url, headers: headers, query: query_params, body: body&.to_json)
      when 'DELETE'
        self.class.delete(url, headers: headers, query: query_params)
      else
        raise "Unsupported HTTP method: #{operation.http_method}"
      end
      
      # Log the response
      log_api_call(
        operation: operation,
        url: url,
        method: operation.http_method,
        request_headers: headers,
        request_body: body,
        response: response,
        duration_ms: ((Time.current - log_start) * 1000).round,
        correlation_id: correlation_id
      )
      
      response
    rescue => e
      # Log the error
      log_api_call(
        operation: operation,
        url: url,
        method: operation.http_method,
        request_headers: headers,
        request_body: body,
        error: e,
        duration_ms: ((Time.current - log_start) * 1000).round,
        correlation_id: correlation_id
      )
      
      raise e
    end
  end
  
  def build_request_preview(operation, params: {}, body: nil)
    url = build_url(operation, params)
    headers = build_headers
    query_params = params.except(*extract_path_params(operation.path_template))
    
    {
      method: operation.http_method,
      url: url,
      headers: headers,
      query: query_params,
      body: body
    }
  end
  
  private
  
  def extract_error_message(response)
    return nil unless response&.parsed_response
    
    data = response.parsed_response
    
    # Handle different API error formats
    case @integration.slug
    when 'stripe'
      data.dig('error', 'message')
    when 'shopify'
      data['errors']&.first || data['error']
    when 'hubspot'
      data.dig('message') || data.dig('errors', 0, 'message')
    else
      # Generic error extraction
      data['message'] || data['error'] || data.dig('error', 'message') || data.dig('errors', 0, 'message')
    end
  end
  
  def build_url(operation, params)
    # Start with the base URL
    base_url = @integration.api_base_url
    
    # Build the path with parameter substitution
    path = operation.build_path(params)
    
    # Combine URL and path
    url = URI.join(base_url, path).to_s
    
    # Verify host is allowed
    uri = URI.parse(url)
    unless @integration.host_allowed?(uri.host)
      raise SecurityError, "Host not allowed: #{uri.host}"
    end
    
    url
  end
  
  def build_headers
    headers = {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json',
      'User-Agent' => "AmosLabs/1.0"
    }
    
    # Add authentication headers
    headers.merge!(@credential.build_auth_header)
    
    headers
  end
  
  def extract_path_params(path_template)
    # Extract parameter names from path template
    # e.g., "/customers/{id}/orders/{order_id}" => ["id", "order_id"]
    path_template.scan(/[{:](\w+)[}]?/).flatten
  end
  
  def log_api_call(operation:, url:, method:, request_headers:, request_body:, 
                   response: nil, error: nil, duration_ms:, correlation_id:)
    IntegrationLog.create!(
      connection: @connection,
      user: @connection.entity.users.first, # TODO: Track actual user
      scout_message: nil, # Optional for connection testing
      integration_operation: operation,
      correlation_id: correlation_id,
      operation_id: operation.operation_id,
      endpoint: url,
      http_method: method,
      request_headers: request_headers,
      request_body: request_body,
      response_status: response&.code,
      response_headers: response&.headers&.to_h,
      response_body_encrypted: response&.parsed_response&.to_json,
      error_message: error&.message,
      duration_ms: duration_ms,
      rate_limit_remaining: response&.headers&.[]('x-ratelimit-remaining')&.to_i,
      rate_limit_reset_at: parse_rate_limit_reset(response&.headers)
    )
  end
  
  def parse_rate_limit_reset(headers)
    return nil unless headers
    
    reset = headers['x-ratelimit-reset'] || headers['x-rate-limit-reset']
    return nil unless reset
    
    # Handle both timestamp and seconds-from-now formats
    if reset.to_i > 1_000_000_000
      Time.at(reset.to_i)
    else
      reset.to_i.seconds.from_now
    end
  end
end
