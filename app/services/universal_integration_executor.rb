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
      result = service.execute_operation(operation_record.operation_id, params)
      
      # 8. Log the execution
      log_execution(
        connection: connection,
        operation: operation_record,
        params: params,
        result: result,
        duration_ms: ((Time.current - start_time) * 1000).round
      )
      
      # 9. Return standardized response
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
      
      error_response("Execution failed: #{e.message}", error_class: e.class.name)
    end
  end
  
  private
  
  def find_integration(slug_or_name)
    Integration.find_by(slug: slug_or_name) ||
    Integration.find_by(slug: slug_or_name.downcase.gsub(/\s+/, '_')) ||
    Integration.find_by(name: slug_or_name)
  end
  
  def find_connection(integration, connection_id)
    if connection_id
      Connection.find_by(id: connection_id, integration: integration, entity: entity)
    else
      # Find first active connection
      entity.connections
            .where(integration: integration)
            .active
            .order(created_at: :desc)
            .first
    end
  end
  
  def find_operation(integration, operation_id)
    # Try exact match first
    op = integration.integration_operations
               .where(is_enabled: true)
               .find_by(operation_id: operation_id)
    
    return op if op
    
    # If not found, try matching with integration slug prefix
    # E.g., "get_company_info" or "quickbooks.get_company_info" matches "quickbooks.get_company_info.v3"
    integration.integration_operations
               .where(is_enabled: true)
               .find do |o|
                 # Extract base operation name without version (e.g., "quickbooks.get_company_info.v3" → "quickbooks.get_company_info")
                 base_op_id = o.operation_id.sub(/\.v\d+$/, '')  # Remove version suffix like .v3
                 
                 # Match if:
                 # 1. Input matches the base (e.g., "quickbooks.get_company_info")
                 # 2. Input matches just the operation name (e.g., "get_company_info")
                 # 3. Input with slug prefix matches (e.g., "quickbooks.get_company_info")
                 base_op_id == operation_id ||
                 base_op_id == "#{integration.slug}.#{operation_id}" ||
                 base_op_id.end_with?(".#{operation_id}")
               end
  end
  
  def load_service(integration, connection)
    # Try to load service class
    service_class_name = "Integrations::#{integration.slug.camelize}::#{integration.slug.camelize}Service"
    
    begin
      service_class = service_class_name.constantize
      service_class.new(connection)
    rescue NameError
      # Try loading the file
      service_path = Rails.root.join('app', 'services', 'integrations', integration.slug, "#{integration.slug}_service.rb")
      
      if File.exist?(service_path)
        load service_path
        service_class = service_class_name.constantize
        service_class.new(connection)
      else
        nil
      end
    end
  end
  
  def log_execution(connection:, operation:, params:, result:, duration_ms:)
    IntegrationLog.create!(
      connection: connection,
      integration_operation: operation,
      http_method: operation.http_method,
      endpoint: operation.path_template,
      request_params: params,
      response_status: result[:success] ? 200 : 500,
      response_body: result[:data] || result[:error],
      duration_ms: duration_ms,
      executed_by: user&.id,
      executed_at: Time.current,
      metadata: {
        executed_via: 'universal_executor',
        operation_id: operation.operation_id
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
  
  def format_response(result, operation, connection)
    # Standardized response format
    response = {
      success: result[:success] || false,
      integration: connection.integration.name,
      operation: operation.name,
      operation_id: operation.operation_id
    }
    
    if result[:success]
      response.merge!(
        data: result[:data],
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
    
    Artifact.create!(
      user: user,
      entity: entity,
      connection: connection,
      integration_operation: operation,
      artifact_type: 'dataset',
      storage_ref: "memory://#{SecureRandom.uuid}",
      schema: extract_schema(data),
      sample_rows: data.first(100),
      row_count: data.length,
      metadata: {
        operation: operation.operation_id,
        integration: connection.integration.slug,
        created_at: Time.current
      }
    )
  rescue => e
    Rails.logger.error "Failed to create artifact: #{e.message}"
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
end

