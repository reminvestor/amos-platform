class UniversalIntegrationExecutor
  attr_reader :user, :entity
  
  def initialize(user:, entity:)
    @user = user
    @entity = entity
  end
  
  # Execute an integration operation
  # Works with both generated and manual integrations
  def self.execute(integration:, operation:, params: {}, user:, entity:, connection_id: nil)
    new(user: user, entity: entity).execute(
      integration: integration,
      operation: operation,
      params: params,
      connection_id: connection_id
    )
  end
  
  def execute(integration:, operation:, params: {}, connection_id: nil)
    Rails.logger.info "🚀 Universal Executor: #{integration}.#{operation}"
    
    start_time = Time.current
    
    begin
      # 1. Find or create integration record
      integration_record = find_integration(integration)
      return error_response("Integration '#{integration}' not found") unless integration_record
      
      # 2. Find connection
      connection = find_connection(integration_record, connection_id)
      return error_response("No active connection for #{integration_record.name}") unless connection
      
      # 3. Find operation
      operation_record = find_operation(integration_record, operation)
      return error_response("Operation '#{operation}' not found for #{integration_record.name}") unless operation_record
      
      # 4. Check if operation is allowed
      unless connection.can_execute?(operation_record.operation_id, 'scout')
        return error_response("Operation not allowed by policy")
      end
      
      # 5. Check rate limits
      unless connection.within_rate_limit?
        return error_response("Rate limit exceeded", retry_after: 1.hour.from_now)
      end
      
      # 6. Load service class
      service = load_service(integration_record, connection)
      return error_response("Service class not found for #{integration_record.name}") unless service
      
      # 7. Execute operation
      # For POST/PUT/PATCH: params go to body (for request payload)
      # For GET/DELETE: params go to query string
      # Path parameters (like {id}) are extracted from params in both cases by build_url
      if %w[POST PUT PATCH].include?(operation_record.http_method.upcase)
        # Pass params to both: params for path substitution, body for request payload
        response = service.execute_operation(operation_record, params: params, body: params)
      else
        response = service.execute_operation(operation_record, params: params)
      end
      
      # 8. Convert HTTParty response to standardized format
      result = standardize_response(response)
      
      # 9. Log the execution
      log_execution(
        connection: connection,
        operation: operation_record,
        params: params,
        result: result,
        duration_ms: ((Time.current - start_time) * 1000).round
      )
      
      # 10. SCHEMA LEARNING: Learn from successful/failed calls to auto-correct schemas
      learn_from_result(operation_record, params, result)
      
      # 11. Return standardized response
      format_response(result, operation_record, connection)
      
    rescue => e
      Rails.logger.error "Universal Executor Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      log_error(
        integration: integration,
        operation: operation,
        params: params,
        error: e,
        duration_ms: ((Time.current - start_time) * 1000).round
      )
      
      # Learn from exception as failure
      if defined?(operation_record) && operation_record
        IntegrationSchemaLearnerService.learn_from_failure(
          operation: operation_record,
          params: params,
          error: e.message
        )
      end
      
      error_response("Execution failed: #{e.message}", error_class: e.class.name)
    end
  end
  
  private
  
  def find_integration(slug_or_name)
    # If already an Integration object, return it directly
    return slug_or_name if slug_or_name.is_a?(Integration)
    
    Integration.find_by(slug: slug_or_name) ||
    Integration.find_by(slug: slug_or_name.to_s.downcase.gsub(/\s+/, '_')) ||
    Integration.find_by(name: slug_or_name)
  end
  
  def find_connection(integration, connection_id)
    if connection_id
      # User-scoped for data privacy
      Connection.find_by(id: connection_id, integration: integration, user: user, entity: entity)
    else
      # Find first active connection for this user (user-scoped)
      Connection.where(integration: integration, user: user, entity: entity)
                .active
                .order(created_at: :desc)
                .first
    end
  end
  
  def find_operation(integration, operation_id)
    # After normalization, all operation_ids follow the format: slug.operation_name
    # Support both full format (stripe.list_customers) and short format (list_customers)
    
    # Try exact match first
    op = integration.integration_operations
               .where(is_enabled: true)
               .find_by(operation_id: operation_id)
    
    return op if op
    
    # If not found and input doesn't include slug prefix, try adding it
    unless operation_id.include?('.')
      full_operation_id = "#{integration.slug}.#{operation_id}"
      op = integration.integration_operations
                 .where(is_enabled: true)
                 .find_by(operation_id: full_operation_id)
    end
    
    op
  end
  
  def load_service(integration, connection)
    # Try to load integration-specific service class first
    service_class_name = "Integrations::#{integration.slug.camelize}::#{integration.slug.camelize}Service"
    
    begin
      service_class = service_class_name.constantize
      return service_class.new(connection)
    rescue NameError
      # Try loading the file
      service_path = Rails.root.join('app', 'services', 'integrations', integration.slug, "#{integration.slug}_service.rb")
      
      if File.exist?(service_path)
        load service_path
        service_class = service_class_name.constantize
        return service_class.new(connection)
      end
    end
    
    # Fall back to generic IntegrationApiService for all integrations
    # This is the standard service for REST API integrations
    IntegrationApiService.new(connection)
  end
  
  def standardize_response(response)
    # Convert HTTParty response to standardized format
    if response.success?
      {
        success: true,
        data: response.parsed_response,
        status_code: response.code,
        message: "Operation completed successfully"
      }
    else
      {
        success: false,
        error: response.message || "Request failed",
        error_details: response.parsed_response,
        status_code: response.code
      }
    end
  rescue => e
    # Handle non-HTTParty responses (already standardized)
    if response.is_a?(Hash) && response.key?(:success)
      response
    else
      {
        success: false,
        error: "Failed to parse response: #{e.message}",
        status_code: 500
      }
    end
  end
  
  def log_execution(connection:, operation:, params:, result:, duration_ms:)
    IntegrationLog.create!(
      connection: connection,
      integration_operation: operation,
      user: @user,
      http_method: operation.http_method,
      endpoint: operation.path_template,
      response_status: result[:success] ? 200 : 500,
      response_body_encrypted: (result[:data] || result[:error]).to_json,
      duration_ms: duration_ms,
      metadata: {
        executed_via: 'universal_executor',
        operation_id: operation.operation_id,
        params: params
      }
    )
  rescue => e
    Rails.logger.error "Failed to log execution: #{e.message}"
  end
  
  def log_error(integration:, operation:, params:, error:, duration_ms:)
    Rails.logger.error "Integration Error Log: #{integration}.#{operation}"
    Rails.logger.error "Error: #{error.message}"
    Rails.logger.error "Params: #{params.inspect}"
  end
  
  # Schema Learning: Auto-update operation schemas based on success/failure
  # This prevents AMOS from making the same mistakes repeatedly
  def learn_from_result(operation, params, result)
    return unless operation.present?
    
    if result[:success]
      # Learn from success - update schema with working params
      IntegrationSchemaLearnerService.learn_from_success(
        operation: operation,
        params: params,
        response: result[:data],
        context: { user_id: user&.id, entity_id: entity&.id }
      )
    else
      # Learn from failure - record bad params
      IntegrationSchemaLearnerService.learn_from_failure(
        operation: operation,
        params: params,
        error: result[:error] || result[:error_details],
        context: { user_id: user&.id, entity_id: entity&.id }
      )
    end
  rescue => e
    # Don't let learning failures break execution
    Rails.logger.warn "[SchemaLearner] Learning failed: #{e.message}"
  end
  
  def format_response(result, operation, connection)
    # Standardized response format
    response = {
      success: result[:success] || false,
      integration: connection.integration.name,
      operation: operation.name,
      operation_id: operation.operation_id
    }
    
    if result[:success]
      # Apply currency formatting if specified in schema
      formatted_data = apply_response_formatting(result[:data], operation, connection.integration)
      
      response.merge!(
        data: formatted_data,
        status_code: result[:status_code] || result[:status] || 200,
        message: result[:message] || "Operation completed successfully"
      )
      
      # Handle list operations - create artifacts
      if operation.http_method == 'GET' && result[:data].is_a?(Array)
        artifact = create_data_artifact(result[:data], operation, connection)
        response[:artifact_id] = artifact.id if artifact
        response[:row_count] = result[:data].length
      end
    else
      response.merge!(
        error: result[:error] || "Operation failed",
        error_details: result[:error_details],
        status_code: result[:status_code] || result[:status] || 500
      )
    end
    
    response
  end
  
  def create_data_artifact(data, operation, connection)
    return nil if data.empty?
    
    artifact = Artifact.create!(
      user: user,
      entity: entity,
      name: "#{connection.integration.name} - #{operation.name}",
      source: 'integration',
      connection_id: connection.id,
      operation_id: operation.operation_id,
      schema: extract_schema(data),
      sample: data.first(100),  # Store up to 100 records in 'sample' column
      row_count: data.length,
      storage_ref: "memory://#{SecureRandom.uuid}",
      metadata: {
        operation: operation.operation_id,
        integration: connection.integration.slug,
        created_at: Time.current
      }
    )
    
    Rails.logger.info "[UniversalExecutor] Created artifact #{artifact.id} with #{data.length} records"
    artifact
  rescue => e
    Rails.logger.error "[UniversalExecutor] Failed to create artifact: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    nil
  end
  
  def extract_schema(data)
    return {} if data.empty?
    
    sample = data.first(10)
    schema = {}
    
    all_keys = sample.flat_map(&:keys).uniq
    
    all_keys.each do |key|
      values = sample.map { |row| row[key] }.compact
      next if values.empty?
      
      schema[key] = {
        type: determine_type(values.first),
        nullable: values.length < sample.length
      }
    end
    
    schema
  end
  
  def determine_type(value)
    case value
    when String then 'string'
    when Integer then 'integer'
    when Float, BigDecimal then 'number'
    when TrueClass, FalseClass then 'boolean'
    when Array then 'array'
    when Hash then 'object'
    else 'string'
    end
  end
  
  def error_response(message, **extra)
    {
      success: false,
      error: message
    }.merge(extra)
  end
  
  # Apply response formatting based on operation schema or integration metadata
  # Handles currency conversion (cents to dollars) and timestamp formatting
  def apply_response_formatting(data, operation, integration)
    return data unless data.present?
    
    # Get formatting hints from operation schema or integration metadata
    formatting = operation.request_schema&.dig('response_formatting') ||
                 integration.metadata&.dig('currency_handling')
    
    return data unless formatting.present?
    
    currency_fields = formatting['currency_fields'] || formatting['common_currency_fields'] || []
    divisor = formatting['currency_divisor'] || formatting['divisor'] || 100
    
    return data if currency_fields.empty?
    
    # Apply formatting to data
    if data.is_a?(Array)
      data.map { |record| format_record_currencies(record, currency_fields, divisor) }
    elsif data.is_a?(Hash)
      # Handle Stripe's {data: [...]} wrapper
      if data['data'].is_a?(Array)
        data.merge('data' => data['data'].map { |r| format_record_currencies(r, currency_fields, divisor) })
      else
        format_record_currencies(data, currency_fields, divisor)
      end
    else
      data
    end
  rescue => e
    Rails.logger.warn "[UniversalExecutor] Response formatting failed: #{e.message}"
    data  # Return original data on error
  end
  
  def format_record_currencies(record, currency_fields, divisor)
    return record unless record.is_a?(Hash)
    
    formatted = record.dup
    
    currency_fields.each do |field|
      # Handle nested fields like 'items.data[].price.unit_amount'
      if field.include?('.')
        # Skip complex nested paths for now - these need special handling
        next
      end
      
      # Convert string keys to handle both symbol and string keys
      value = formatted[field] || formatted[field.to_sym]
      
      if value.is_a?(Integer) || value.is_a?(Float)
        formatted_value = (value.to_f / divisor).round(2)
        # Store both original and formatted values
        formatted["#{field}_cents"] = value
        formatted[field] = formatted_value
        formatted[field.to_sym] = formatted_value if formatted.key?(field.to_sym)
      end
    end
    
    formatted
  end
end

