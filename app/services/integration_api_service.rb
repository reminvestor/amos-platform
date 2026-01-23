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

  def execute_operation(operation, params: {}, body: nil, retry_on_401: true)
    # Refresh OAuth token if needed
    refresh_oauth_token_if_needed
    
    # Pre-process request body for integration-specific transformations
    body = preprocess_request_body(operation, body)
    
    # Build the request
    url = build_url(operation, params)
    headers = build_headers

    # Apply query parameters (user params + auth params)
    query_params = params.except(*extract_path_params(operation.path_template))
    
    # Integration-specific query param transformations
    query_params = preprocess_query_params(operation, query_params)
    
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

      # Handle 401 Unauthorized - attempt to refresh token and retry once
      if response.code == 401 && retry_on_401 && can_refresh_token?
        Rails.logger.info "🔄 Received 401 for #{operation.operation_id} - attempting token refresh and retry"
        
        begin
          force_token_refresh!
          # Retry with fresh token (set retry_on_401: false to prevent infinite loop)
          return execute_operation(operation, params: params, body: body, retry_on_401: false)
        rescue => refresh_error
          Rails.logger.warn "⚠️ Token refresh failed, returning original 401 response: #{refresh_error.message}"
        end
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

  # Check if we have the ability to refresh the token
  def can_refresh_token?
    return false unless @credential.auth_method == "bearer"
    refresh_token = @credential.credentials["refresh_token"] || @credential.credentials[:refresh_token]
    refresh_token.present?
  end

  # Force a token refresh regardless of expiration time
  def force_token_refresh!
    Rails.logger.info "🔄 Forcing OAuth token refresh for #{@integration.name}"
    refresh_service = OauthTokenRefreshService.new(@credential)
    refresh_service.refresh_token!
    @credential.reload
    
    # Rebuild headers with new token
    @headers = nil # Clear cached headers if any
    Rails.logger.info "✅ Forced token refresh successful for #{@integration.name}"
  end

  def test_with_endpoint(endpoint_path)
    # Build URL with credential-based parameter replacement using smart matching
    base_url = @integration.api_base_url
    
    Rails.logger.info "🔍 Test connection - base_url from integration: #{base_url}"
    Rails.logger.info "🔍 Test connection - endpoint_path template: #{endpoint_path}"
    
    begin
      # Substitute placeholders in the base URL first (e.g., {shop_domain} for Shopify)
      base_url = substitute_path_params(base_url, {}, @credential.credentials)
      
      # Use the universal path substitution logic for the endpoint path
      path = substitute_path_params(endpoint_path, {}, @credential.credentials)
      
      Rails.logger.info "🔍 Test connection - substituted path: #{path}"
    rescue ArgumentError => e
      Rails.logger.error "🔍 Test connection - path substitution failed: #{e.message}"
      return {
        success: false,
        error: e.message
      }
    end
    
    # Ensure proper URL joining - base_url must end with / and path must not start with /
    # to avoid URI.join replacing the entire path
    normalized_base = base_url.end_with?('/') ? base_url : "#{base_url}/"
    normalized_path = path.start_with?('/') ? path[1..] : path
    url = URI.join(normalized_base, normalized_path).to_s
    
    headers = build_headers
    query_params = build_auth_query_params
    
    Rails.logger.info "Testing connection with endpoint: #{url}"
    Rails.logger.info "Auth query params: #{query_params.keys}" if query_params.any?
    
    begin
      response = self.class.get(url, headers: headers, query: query_params)
      
      if response.success?
        Rails.logger.info "🔍 Test connection SUCCESS - status: #{response.code}"
        {
          success: true,
          status_code: response.code,
          message: "Connection successful",
          data: response.parsed_response
        }
      else
        error_message = extract_error_message(response)
        Rails.logger.warn "🔍 Test connection FAILED - status: #{response.code}, error: #{error_message}"
        Rails.logger.warn "🔍 Test connection response body: #{response.body&.truncate(500)}"
        {
          success: false,
          status_code: response.code,
          error: error_message || "API request failed with status #{response.code}",
          data: response.parsed_response
        }
      end
    rescue => e
      status_code = e.respond_to?(:response) ? e.response&.code : nil
      Rails.logger.error "🔍 Test connection EXCEPTION: #{e.class} - #{e.message}"
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
  # Uses curly brace placeholders like {shop_domain}, {customer_id}, etc.
  def substitute_path_params(path_template, params = {}, credentials = {})
    path = path_template.dup
    
    # Combine both credentials and params for substitution
    all_params = credentials.merge(params)
    
    # Find all curly brace placeholders in the path like {param}
    placeholders = path.scan(/\{(\w+)\}/).flatten.uniq
    
    # Replace each placeholder with smart matching
    placeholders.each do |placeholder|
      value = find_param_value(placeholder, all_params)
      
      if value
        path.gsub!("{#{placeholder}}", value.to_s)
      end
    end
    
    # Ensure no unreplaced parameters remain
    remaining = path.scan(/\{(\w+)\}/).flatten
    if remaining.any?
      raise ArgumentError, "Missing required path parameters: #{remaining.join(', ')}"
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

  # Pre-process request body for integration-specific transformations
  # Handles special cases like Gmail's RFC 2822 email format requirement
  def preprocess_request_body(operation, body)
    return body if body.nil?

    case @integration.slug
    when "gmail"
      preprocess_gmail_body(operation, body)
    when "quickbooks"
      preprocess_quickbooks_body(operation, body)
    else
      body
    end
  end

  # Gmail-specific body preprocessing
  # Converts simple email parameters to RFC 2822 base64url format
  def preprocess_gmail_body(operation, body)
    # Only transform send_email operations
    return body unless operation.operation_id&.include?("send_email")
    
    # Check if body needs transformation (has simple params, not raw)
    if Integrations::GmailEmailFormatter.needs_transformation?(body)
      Rails.logger.info "[Gmail] Transforming email body to RFC 2822 format"
      
      transformed = Integrations::GmailEmailFormatter.format(body)
      Rails.logger.info "[Gmail] Email formatted successfully"
      
      transformed
    else
      body
    end
  end

  # QuickBooks-specific body preprocessing
  # QuickBooks Query API uses SQL-like syntax in a 'query' parameter
  # This converts simple params like {status: "Open"} into proper QB Query Language
  def preprocess_quickbooks_body(operation, body)
    # Only transform query-based operations (list_invoices, list_customers, etc.)
    return body unless operation.path_template&.include?("/query")
    
    # Body is not used for GET query operations - preprocessing happens in params
    body
  end
  
  # Pre-process query parameters for integration-specific transformations
  def preprocess_query_params(operation, query_params)
    case @integration.slug
    when "quickbooks"
      preprocess_quickbooks_query_params(operation, query_params)
    else
      query_params
    end
  end
  
  # QuickBooks Query API transformation
  # Converts simple params like {status: "Open", limit: 50} into QuickBooks Query Language
  def preprocess_quickbooks_query_params(operation, params)
    # Only transform query-based operations
    return params unless operation.path_template&.include?("/query")
    
    # If a 'query' param is already provided, sanitize and use it
    if params[:query].present? || params['query'].present?
      query = params[:query] || params['query']
      sanitized_query = sanitize_quickbooks_query(query)
      Rails.logger.info "[QuickBooks] Sanitized query: #{sanitized_query}"
      params[:query] = sanitized_query
      params.delete('query') if params['query']
      return params
    end
    
    # Determine the entity type from the operation_id
    entity = extract_quickbooks_entity(operation.operation_id)
    return params unless entity
    
    # Build the query
    query_parts = ["SELECT * FROM #{entity}"]
    where_clauses = []
    
    # Handle status for invoices
    if params[:status].present? || params['status'].present?
      status = params.delete(:status) || params.delete('status')
      case status.to_s.downcase
      when 'open', 'unpaid'
        where_clauses << "Balance > '0'"
      when 'paid', 'closed'
        where_clauses << "Balance = '0'"
      when 'overdue'
        where_clauses << "Balance > '0'"
        where_clauses << "DueDate < '#{Date.current.strftime('%Y-%m-%d')}'"
      end
    end
    
    # Handle date filters
    if params[:start_date].present? || params['start_date'].present?
      start_date = params.delete(:start_date) || params.delete('start_date')
      where_clauses << "TxnDate >= '#{start_date}'"
    end
    
    if params[:end_date].present? || params['end_date'].present?
      end_date = params.delete(:end_date) || params.delete('end_date')
      where_clauses << "TxnDate <= '#{end_date}'"
    end
    
    # Handle customer filter
    if params[:customer_id].present? || params['customer_id'].present?
      customer_id = params.delete(:customer_id) || params.delete('customer_id')
      where_clauses << "CustomerRef = '#{customer_id}'"
    end
    
    # Build WHERE clause
    if where_clauses.any?
      query_parts << "WHERE #{where_clauses.join(' AND ')}"
    end
    
    # Handle limit/maxResults
    limit = params.delete(:limit) || params.delete('limit') || 
            params.delete(:maxResults) || params.delete('maxResults') || 50
    query_parts << "MAXRESULTS #{limit}"
    
    # Handle offset/startPosition
    if (offset = params.delete(:startPosition) || params.delete('startPosition') || 
        params.delete(:offset) || params.delete('offset'))
      query_parts << "STARTPOSITION #{offset}"
    end
    
    final_query = query_parts.join(' ')
    Rails.logger.info "[QuickBooks] Built query: #{final_query}"
    
    # Replace params with the query
    params[:query] = final_query
    params
  end
  
  # Sanitize QuickBooks query to remove invalid fields
  # QuickBooks Invoice does NOT have a Status field - open/closed is determined by Balance
  def sanitize_quickbooks_query(query)
    return query if query.blank?
    
    # Remove Status = 'Open' or Status = 'Closed' (invalid for invoices)
    # QuickBooks uses Balance > 0 for open, Balance = 0 for paid
    sanitized = query.dup
    
    # Remove Status conditions (case insensitive)
    sanitized.gsub!(/\s+AND\s+Status\s*=\s*'[^']*'/i, '')
    sanitized.gsub!(/Status\s*=\s*'[^']*'\s+AND\s+/i, '')
    sanitized.gsub!(/\s+AND\s+Status\s*=\s*"[^"]*"/i, '')
    sanitized.gsub!(/Status\s*=\s*"[^"]*"\s+AND\s+/i, '')
    
    # If the WHERE clause is now empty, remove it
    sanitized.gsub!(/WHERE\s+AND\s+/i, 'WHERE ')
    sanitized.gsub!(/WHERE\s+$/i, '')
    sanitized.gsub!(/WHERE\s+MAXRESULTS/i, 'MAXRESULTS')
    
    # Clean up extra whitespace
    sanitized.gsub!(/\s+/, ' ')
    sanitized.strip!
    
    Rails.logger.info "[QuickBooks] Query sanitization: '#{query.truncate(100)}' -> '#{sanitized.truncate(100)}'"
    sanitized
  end

  # Sanitize QuickBooks query to remove invalid fields
  # LLMs often add invalid fields like "Status" which don't exist
  def sanitize_quickbooks_query(query)
    return query if query.blank?
    
    sanitized = query.dup
    
    # Remove invalid Status field references (QuickBooks uses Balance for invoice status)
    # Status = 'Open' should be Balance > '0'
    sanitized.gsub!(/\s+AND\s+Status\s*=\s*'[^']*'/i, '')
    sanitized.gsub!(/Status\s*=\s*'[^']*'\s+AND\s+/i, '')
    sanitized.gsub!(/\s+AND\s+Status\s*=\s*"[^"]*"/i, '')
    sanitized.gsub!(/Status\s*=\s*"[^"]*"\s+AND\s+/i, '')
    
    # Remove orphaned WHERE if all conditions were removed
    sanitized.gsub!(/WHERE\s+AND\s+/i, 'WHERE ')
    sanitized.gsub!(/WHERE\s+MAXRESULTS/i, 'MAXRESULTS')
    sanitized.gsub!(/WHERE\s+STARTPOSITION/i, 'STARTPOSITION')
    sanitized.gsub!(/WHERE\s*$/i, '')
    
    # Clean up any double spaces
    sanitized.gsub!(/\s+/, ' ')
    sanitized.strip!
    
    Rails.logger.info "[QuickBooks] Query sanitization: '#{query.truncate(80)}' -> '#{sanitized.truncate(80)}'" if query != sanitized
    
    sanitized
  end

  # Extract QuickBooks entity name from operation_id
  def extract_quickbooks_entity(operation_id)
    return nil unless operation_id
    
    case operation_id.to_s.downcase
    when /list_invoices/, /invoice/
      'Invoice'
    when /list_customers/, /customer/
      'Customer'
    when /list_items/, /item/
      'Item'
    when /list_accounts/, /account/
      'Account'
    when /list_payments/, /payment/
      'Payment'
    when /list_vendors/, /vendor/
      'Vendor'
    when /list_bills/, /bill/
      'Bill'
    when /list_estimates/, /estimate/
      'Estimate'
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
