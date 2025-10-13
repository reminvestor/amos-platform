class OperationDiscoveryService
  def self.discover_all
    new.discover_all
  end
  
  def self.discover_integration(integration_slug)
    new.discover_integration(integration_slug)
  end
  
  def initialize
    @discovered_operations = []
    @errors = []
  end
  
  # Discover all operations for all integrations
  def discover_all
    Rails.logger.info "🔍 Starting operation discovery for all integrations..."
    
    Integration.where(is_active: true).each do |integration|
      discover_integration(integration.slug)
    end
    
    Rails.logger.info "✅ Discovery complete: #{@discovered_operations.length} operations discovered"
    Rails.logger.error "⚠️ Errors: #{@errors.length}" if @errors.any?
    
    {
      success: true,
      discovered: @discovered_operations.length,
      errors: @errors
    }
  end
  
  # Discover operations for a specific integration
  def discover_integration(slug)
    integration = Integration.find_by(slug: slug)
    
    unless integration
      @errors << "Integration not found: #{slug}"
      return
    end
    
    Rails.logger.info "🔍 Discovering operations for #{integration.name}..."
    
    # Load service class
    service_class = load_service_class(integration)
    
    unless service_class
      Rails.logger.warn "⚠️ No service class found for #{integration.name}"
      return
    end
    
    # Get methods from service
    operations = extract_operations_from_service(service_class, integration)
    
    # Sync to database
    operations.each do |op|
      sync_operation(integration, op)
    end
    
    # Mark stale operations as inactive
    mark_stale_operations(integration, operations.map { |op| op[:operation_id] })
    
    Rails.logger.info "✅ Discovered #{operations.length} operations for #{integration.name}"
    
    operations
  end
  
  private
  
  def load_service_class(integration)
    service_class_name = "Integrations::#{integration.slug.camelize}::#{integration.slug.camelize}Service"
    
    begin
      service_class_name.constantize
    rescue NameError
      # Try loading the file
      service_path = Rails.root.join('app', 'services', 'integrations', integration.slug, "#{integration.slug}_service.rb")
      
      if File.exist?(service_path)
        begin
          load service_path
          service_class_name.constantize
        rescue => e
          Rails.logger.error "Failed to load service: #{e.message}"
          nil
        end
      else
        nil
      end
    end
  end
  
  def extract_operations_from_service(service_class, integration)
    operations = []
    
    # Get public instance methods (excluding base class methods)
    base_methods = Integrations::BaseService.instance_methods
    service_methods = service_class.instance_methods(false)
    
    # Also check methods defined in included modules (like Operations)
    service_class.included_modules.each do |mod|
      next if mod.name.nil? || !mod.name.start_with?('Integrations::')
      service_methods += mod.instance_methods(false)
    end
    
    service_methods.uniq!
    
    # Filter out private/internal methods
    service_methods.reject! { |m| m.to_s.start_with?('_') || base_methods.include?(m) }
    
    service_methods.each do |method_name|
      next if method_name == :execute_operation # Skip the interface method
      
      # Try to get metadata from method
      operation = extract_operation_metadata(service_class, method_name, integration)
      operations << operation if operation
    end
    
    operations
  end
  
  def extract_operation_metadata(service_class, method_name, integration)
    # Try to parse method to determine HTTP method and path
    begin
      # Read the source file
      source_file = find_source_file(integration)
      return nil unless source_file
      
      source = File.read(source_file)
      
      # Find the method definition
      method_match = source.match(/def\s+#{Regexp.escape(method_name.to_s)}\s*\(([^)]*)\)/)
      return nil unless method_match
      
      # Extract parameters
      params_str = method_match[1]
      parameters = parse_parameters(params_str)
      
      # Look for request call in method body
      method_start = method_match.begin(0)
      method_end = find_method_end(source, method_start)
      method_body = source[method_start..method_end]
      
      # Extract HTTP method and path from request() call
      request_match = method_body.match(/request\s*\(\s*:(\w+)\s*,\s*['"](.*?)['"]/m)
      
      if request_match
        http_method = request_match[1].upcase
        path_template = request_match[2]
      else
        # Default to GET and guess path
        http_method = 'GET'
        path_template = "/#{method_name}"
      end
      
      {
        operation_id: method_name.to_s,
        name: method_name.to_s.titleize,
        description: "#{method_name.to_s.titleize} operation",
        http_method: http_method,
        path_template: path_template,
        request_schema: generate_request_schema(parameters),
        method_name: method_name.to_s
      }
    rescue => e
      Rails.logger.warn "Could not extract metadata for #{method_name}: #{e.message}"
      
      # Return basic operation
      {
        operation_id: method_name.to_s,
        name: method_name.to_s.titleize,
        description: "#{method_name.to_s.titleize} operation",
        http_method: 'GET',
        path_template: "/#{method_name}",
        request_schema: {},
        method_name: method_name.to_s
      }
    end
  end
  
  def find_source_file(integration)
    operations_file = Rails.root.join('app', 'services', 'integrations', integration.slug, 'operations.rb')
    service_file = Rails.root.join('app', 'services', 'integrations', integration.slug, "#{integration.slug}_service.rb")
    
    if File.exist?(operations_file)
      operations_file
    elsif File.exist?(service_file)
      service_file
    else
      nil
    end
  end
  
  def find_method_end(source, start_pos)
    # Simple heuristic: find the next "end" at the same indentation level
    lines = source[start_pos..-1].lines
    indent_level = 0
    
    lines.each_with_index do |line, index|
      indent_level += 1 if line =~ /\b(def|class|module|if|unless|while|until|case|begin)\b/
      indent_level -= 1 if line =~ /\bend\b/
      
      if indent_level == 0 && line =~ /\bend\b/
        return start_pos + lines[0..index].join.length
      end
    end
    
    start_pos + 500 # Fallback
  end
  
  def parse_parameters(params_str)
    return {} if params_str.blank?
    
    params = {}
    params_str.split(',').each do |param|
      param = param.strip
      
      # Handle keyword arguments
      if param.include?(':')
        key = param.split(':').first.strip
        params[key] = 'string' # Default type
      else
        params[param] = 'string'
      end
    end
    
    params
  end
  
  def generate_request_schema(parameters)
    return {} if parameters.empty?
    
    {
      type: 'object',
      properties: parameters.transform_values { |type| { type: type } },
      required: parameters.keys
    }
  end
  
  def sync_operation(integration, op_data)
    operation = integration.integration_operations.find_or_initialize_by(
      operation_id: op_data[:operation_id]
    )
    
    # Only update if this is a discovered operation or new
    if operation.new_record? || operation.metadata&.dig('generated_by') == 'integration_builder'
      operation.assign_attributes(
        name: op_data[:name],
        description: op_data[:description],
        http_method: op_data[:http_method],
        path_template: op_data[:path_template],
        request_schema: op_data[:request_schema],
        response_schema: op_data[:response_schema] || {},
        is_enabled: true,
        is_idempotent: op_data[:http_method] == 'GET',
        requires_confirmation: ['DELETE', 'POST', 'PUT', 'PATCH'].include?(op_data[:http_method]),
        metadata: (operation.metadata || {}).merge(
          discovered_at: Time.current,
          discovered_by: 'operation_discovery_service',
          method_name: op_data[:method_name]
        )
      )
      
      if operation.save
        @discovered_operations << op_data[:operation_id]
      else
        @errors << "Failed to sync #{op_data[:operation_id]}: #{operation.errors.full_messages.join(', ')}"
      end
    end
  end
  
  def mark_stale_operations(integration, current_operation_ids)
    # Find operations that were discovered but no longer exist in code
    stale_operations = integration.integration_operations
                                  .where(metadata: { discovered_by: 'operation_discovery_service' })
                                  .where.not(operation_id: current_operation_ids)
    
    stale_operations.update_all(
      is_enabled: false,
      metadata: stale_operations.first&.metadata&.merge(stale_since: Time.current) || { stale_since: Time.current }
    )
    
    Rails.logger.info "⚠️ Marked #{stale_operations.count} operations as stale" if stale_operations.count > 0
  end
end

