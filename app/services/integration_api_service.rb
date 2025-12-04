class IntegrationApiService
  include HTTParty

  def initialize(connection)
    @connection = connection
    @integration = connection.integration
    @credential = connection.active_credential

    raise "No active credentials for connection" unless @credential
  end

  def test_connection
    # Check if there's a configured test_endpoint in oauth_configuration
    oauth_config = @integration.oauth_configurations.first
    
    if oauth_config&.test_endpoint.present?
      # Use the configured test endpoint
      return test_with_endpoint(oauth_config.test_endpoint)
    end
    
    # Fall back to finding the test connection operation
    # After normalization, operation_ids follow format: slug.operation_name (e.g., stripe.test_connection)
    test_operation = @integration.integration_operations
                                .where("operation_id = ? OR operation_id LIKE ?", 
                                       "#{@integration.slug}.test_connection",
                                       "%.test_connection")
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
    # Refresh OAuth token if needed
    refresh_oauth_token_if_needed
    
    # Build the request
    url = build_url(operation, params)
    headers = build_headers

    # Apply query parameters (user params + auth params)
    query_params = params.except(*extract_path_params(operation.path_template))
    query_params.merge!(build_auth_query_params) # Add auth query params from AuthConfig

    # Log the request
    correlation_id = SecureRandom.uuid
    log_start = Time.current

    begin
      response = case operation.http_method
      when "GET"
        self.class.get(url, headers: headers, query: query_params)
      when "POST"
        self.class.post(url, headers: headers, query: query_params, body: body&.to_json)
      when "PUT"
        self.class.put(url, headers: headers, query: query_params, body: body&.to_json)
      when "PATCH"
        self.class.patch(url, headers: headers, query: query_params, body: body&.to_json)
      when "DELETE"
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

  def refresh_oauth_token_if_needed
    # Only refresh for OAuth credentials
    return unless @credential.auth_method == "bearer"
    return unless @credential.expires_at.present?
    
    # Check if we have a refresh token
    refresh_token = @credential.credentials["refresh_token"] || @credential.credentials[:refresh_token]
    return unless refresh_token
    
    # Use the refresh service
    refresh_service = OauthTokenRefreshService.new(@credential)
    refresh_service.refresh_if_needed!
    
    # Reload credential to get updated tokens
    @credential.reload
  rescue => e
    Rails.logger.error "Failed to refresh OAuth token: #{e.message}"
    # Don't raise - let the API call proceed and fail naturally if token is invalid
  end

  def test_with_endpoint(endpoint_path)
    # Build URL with credential-based parameter replacement using smart matching
    base_url = @integration.api_base_url
    
    begin
      # Substitute placeholders in the base URL first (e.g., {shop_domain} for Shopify)
      base_url = substitute_path_params(base_url, {}, @credential.credentials)
      
      # Use the universal path substitution logic for the endpoint path
      path = substitute_path_params(endpoint_path, {}, @credential.credentials)
    rescue ArgumentError => e
      return {
        success: false,
        error: e.message
      }
    end
    
    url = URI.join(base_url, path).to_s
    headers = build_headers
    query_params = build_auth_query_params
    
    Rails.logger.info "Testing connection with endpoint: #{url}"
    Rails.logger.info "Auth query params: #{query_params.keys}" if query_params.any?
    
    begin
      response = self.class.get(url, headers: headers, query: query_params)
      
      if response.success?
        {
          success: true,
          status_code: response.code,
          message: "Connection successful",
          data: response.parsed_response
        }
      else
        error_message = extract_error_message(response)
        {
          success: false,
          status_code: response.code,
          error: error_message || "API request failed with status #{response.code}",
          data: response.parsed_response
        }
      end
    rescue => e
      status_code = e.respond_to?(:response) ? e.response&.code : nil
      {
        success: false,
        error: e.message,
        status_code: status_code
      }
    end
  end
  
  # Build auth query params from AuthConfig records with placement='query'
  def build_auth_query_params
    query_params = {}
    
    oauth_config = @integration.oauth_configurations.first
    return query_params unless oauth_config
    
    oauth_config.auth_configs.where(auth_placement: 'query').each do |auth_config|
      value = auth_config.auth_value
      
      # Replace placeholders with actual credential values
      placeholders = value.scan(/\{(\w+)\}/).flatten
      placeholders.each do |placeholder|
        credential_value = @credential.credentials[placeholder] || @credential.credentials[placeholder.to_sym] || ''
        value = value.gsub("{#{placeholder}}", credential_value)
      end
      
      query_params[auth_config.auth_key] = value
    end
    
    # Also include legacy query auth if configured
    if @credential.auth_method == "query"
      query_params.merge!(@credential.build_auth_params)
    end
    
    query_params
  end
  
  # Universal path parameter substitution with smart matching
  def substitute_path_params(path_template, params = {}, credentials = {})
    path = path_template.dup
    
    # Combine both credentials and params for substitution
    all_params = credentials.merge(params)
    
    # Find all placeholders in the path
    placeholders = path.scan(/[{:](\w+)[}]?/).flatten.uniq
    
    # Replace each placeholder with smart matching
    placeholders.each do |placeholder|
      value = find_param_value(placeholder, all_params)
      
      if value
        path.gsub!("{#{placeholder}}", value.to_s)
        path.gsub!(":#{placeholder}", value.to_s)
      end
    end
    
    # Ensure no unreplaced parameters remain
    if path.include?("{") || path.include?(":")
      missing = path.scan(/[{:](\w+)[}]?/).flatten
      raise ArgumentError, "Missing required path parameters: #{missing.join(', ')}"
    end
    
    path
  end
  
  # Smart parameter matching - tries multiple naming conventions
  def find_param_value(placeholder, params)
    # Try exact match first (both string and symbol)
    return params[placeholder] if params.key?(placeholder)
    return params[placeholder.to_sym] if params.key?(placeholder.to_sym)
    
    # Convert placeholder to snake_case and try
    snake_case = placeholder.underscore
    return params[snake_case] if params.key?(snake_case)
    return params[snake_case.to_sym] if params.key?(snake_case.to_sym)
    
    # Convert placeholder to camelCase and try
    camel_case = snake_case.camelize(:lower)
    return params[camel_case] if params.key?(camel_case)
    return params[camel_case.to_sym] if params.key?(camel_case.to_sym)
    
    # Try known aliases
    case placeholder.downcase
    when "companyid", "company_id"
      params[:realmId] || params[:realm_id] || params["realmId"] || params["realm_id"]
    when "realmid", "realm_id"
      params[:companyId] || params[:company_id] || params["companyId"] || params["company_id"]
    else
      nil
    end
  end

  def extract_error_message(response)
    return nil unless response&.parsed_response

    data = response.parsed_response

    # Handle different API error formats
    case @integration.slug
    when "stripe"
      data.dig("error", "message")
    when "shopify"
      data["errors"]&.first || data["error"]
    when "hubspot"
      data.dig("message") || data.dig("errors", 0, "message")
    else
      # Generic error extraction
      data["message"] || data["error"] || data.dig("error", "message") || data.dig("errors", 0, "message")
    end
  end

  def build_url(operation, params)
    # Start with the base URL
    base_url = @integration.api_base_url
    
    # Substitute placeholders in the base URL (e.g., {shop_domain} for Shopify)
    base_url = substitute_path_params(base_url, params, @credential.credentials)
    
    # Ensure base URL ends with / for proper path joining
    base_url = base_url.chomp('/') + '/'

    # Build the path with parameter substitution
    # Pass credentials so OAuth callback params (like company_id) can be auto-injected
    path = operation.build_path(params, @credential.credentials)
    
    # Remove leading slash from path if present
    path = path.sub(/^\//, '')

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
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "User-Agent" => "AmosLabs/1.0"
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
      rate_limit_remaining: response&.headers&.[]("x-ratelimit-remaining")&.to_i,
      rate_limit_reset_at: parse_rate_limit_reset(response&.headers)
    )
  end

  def parse_rate_limit_reset(headers)
    return nil unless headers

    reset = headers["x-ratelimit-reset"] || headers["x-rate-limit-reset"]
    return nil unless reset

    # Handle both timestamp and seconds-from-now formats
    if reset.to_i > 1_000_000_000
      Time.at(reset.to_i)
    else
      reset.to_i.seconds.from_now
    end
  end
end
