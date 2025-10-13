module Integrations
  class BaseService
    attr_reader :connection
    
    def initialize(connection)
      @connection = connection
    end
    
    # Standard interface that all integration services must implement
    def execute_operation(operation_id, params = {})
      raise NotImplementedError, "Subclass must implement execute_operation"
    end
    
    # Return list of available operations
    # Override in subclass or use auto-discovery
    def available_operations
      []
    end
    
    # Base URL for the API - override in subclass
    def base_url
      @connection.integration.api_base_url
    end
    
    # Standard HTTP request method
    # All integrations can use this for making API calls
    def request(method, path, params: {}, body: nil, headers: {})
      url = build_url(path)
      
      # Add authentication headers
      auth_headers = authentication_headers
      final_headers = default_headers.merge(auth_headers).merge(headers)
      
      # Build request options
      options = {
        method: method.to_s.upcase,
        url: url,
        headers: final_headers
      }
      
      options[:params] = params if params.any?
      options[:payload] = body.to_json if body
      
      # Execute request with error handling
      begin
        response = RestClient::Request.execute(options)
        parse_response(response)
      rescue RestClient::ExceptionWithResponse => e
        handle_error(e)
      end
    end
    
    # Get active credential
    def credential
      @credential ||= @connection.active_credential
    end
    
    # Authentication headers - override in subclass if needed
    def authentication_headers
      return {} unless credential
      
      case @connection.integration.auth_type.to_sym
      when :bearer_token, :oauth2
        { 'Authorization' => "Bearer #{bearer_token}" }
      when :api_key
        { 'Authorization' => api_key_header }
      when :basic_auth
        { 'Authorization' => basic_auth_header }
      else
        {}
      end
    end
    
    # Default headers
    def default_headers
      {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json',
        'User-Agent' => 'AMOS/1.0'
      }
    end
    
    # Build full URL
    def build_url(path)
      # Handle absolute URLs
      return path if path.start_with?('http')
      
      # Ensure path starts with /
      path = "/#{path}" unless path.start_with?('/')
      
      "#{base_url}#{path}"
    end
    
    # Parse response
    def parse_response(response)
      {
        success: true,
        data: parse_body(response.body),
        status_code: response.code,
        headers: response.headers
      }
    end
    
    # Parse response body
    def parse_body(body)
      return nil if body.nil? || body.empty?
      
      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
    
    # Handle errors uniformly
    def handle_error(error)
      status_code = error.response&.code || 500
      error_body = parse_body(error.response&.body) rescue {}
      
      {
        success: false,
        error: determine_error_message(status_code, error_body),
        status_code: status_code,
        error_details: error_body,
        error_type: determine_error_type(status_code)
      }
    end
    
    def determine_error_message(status_code, error_body)
      case status_code
      when 401 then 'Authentication failed - check your credentials'
      when 403 then 'Access forbidden - insufficient permissions'
      when 404 then 'Resource not found'
      when 429 then 'Rate limit exceeded - please try again later'
      when 400 then error_body['message'] || error_body['error'] || 'Bad request'
      when 500..599 then 'API server error'
      else error_body['message'] || error_body['error'] || 'Request failed'
      end
    end
    
    def determine_error_type(status_code)
      case status_code
      when 401 then 'unauthorized'
      when 403 then 'forbidden'
      when 404 then 'not_found'
      when 429 then 'rate_limit'
      when 400 then 'bad_request'
      when 500..599 then 'server_error'
      else 'unknown'
      end
    end
    
    # Authentication helper methods
    def bearer_token
      return nil unless credential
      credential.credentials['bearer_token'] ||
      credential.credentials['token'] ||
      credential.credentials['access_token']
    end
    
    def api_key
      return nil unless credential
      credential.credentials['api_key']
    end
    
    def api_key_header
      key = api_key
      return '' unless key
      
      # Common patterns - can be overridden
      "Bearer #{key}"
    end
    
    def basic_auth_header
      return '' unless credential
      
      username = credential.credentials['username']
      password = credential.credentials['password']
      return '' unless username && password
      
      credentials = Base64.strict_encode64("#{username}:#{password}")
      "Basic #{credentials}"
    end
    
    # Helper to check if token is expired (for OAuth)
    def token_expired?
      return false unless credential
      credential.expired? || credential.needs_refresh?
    end
    
    # Log API calls for debugging
    def log_request(method, url, params, body)
      Rails.logger.debug "#{method.upcase} #{url}"
      Rails.logger.debug "Params: #{params.inspect}" if params.any?
      Rails.logger.debug "Body: #{body.inspect}" if body
    end
  end
end

