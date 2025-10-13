class IntegrationCodeGeneratorService
  def generate_code(integration:, code_type:, endpoint_name: nil, http_method: 'GET', 
                   endpoint_path: nil, parameters: {}, response_format: {}, documentation: nil)
    Rails.logger.info "💻 Generating #{code_type} code for #{integration.name}"
    
    case code_type
    when 'endpoint'
      generate_endpoint_code(integration, endpoint_name, http_method, endpoint_path, parameters, response_format, documentation)
    when 'auth'
      generate_auth_code(integration, documentation)
    when 'operation'
      generate_operation_code(integration, endpoint_name, http_method, endpoint_path, parameters, response_format, documentation)
    when 'error_handler'
      generate_error_handler_code(integration, documentation)
    else
      { success: false, error: "Unknown code type: #{code_type}" }
    end
  end
  
  private
  
  def generate_endpoint_code(integration, endpoint_name, http_method, endpoint_path, parameters, response_format, documentation)
    method_name = endpoint_name.underscore
    
    # Build parameter list
    param_list = parameters.keys.map { |p| "#{p}:" }.join(', ')
    
    # Build request body/params based on method
    request_code = if ['POST', 'PUT', 'PATCH'].include?(http_method)
      "body: { #{parameters.keys.map { |p| "#{p}: #{p}" }.join(', ')} }"
    else
      "params: { #{parameters.keys.map { |p| "#{p}: #{p}" }.join(', ')} }"
    end
    
    code = <<~RUBY
      # #{endpoint_name.titleize}
      # #{documentation}
      def #{method_name}(#{param_list})
        request(
          :#{http_method.downcase},
          '#{endpoint_path}',
          #{request_code}
        )
      end
    RUBY
    
    # Determine file path
    file_path = Rails.root.join('app', 'services', 'integrations', integration.slug, 'operations.rb')
    
    # Append to operations file if it exists
    if File.exist?(file_path)
      content = File.read(file_path)
      
      # Find where to insert (before the final 'end')
      lines = content.lines
      insert_index = lines.rindex { |line| line.strip == 'end' } - 1
      
      if insert_index && insert_index > 0
        lines.insert(insert_index, "\n#{code}\n")
        File.write(file_path, lines.join)
      else
        # Just append if we can't find the right spot
        File.write(file_path, content + "\n" + code)
      end
    end
    
    usage_example = generate_usage_example(integration, method_name, parameters)
    
    {
      success: true,
      code: code,
      file_path: file_path.to_s,
      method_name: method_name,
      usage_example: usage_example
    }
  end
  
  def generate_operation_code(integration, operation_name, http_method, endpoint_path, parameters, response_format, documentation)
    # Same as endpoint code - they're synonymous
    generate_endpoint_code(integration, operation_name, http_method, endpoint_path, parameters, response_format, documentation)
  end
  
  def generate_auth_code(integration, documentation)
    # Auth code is already generated in scaffold, so we just return info
    file_path = Rails.root.join('app', 'services', 'integrations', integration.slug, "#{integration.slug}_auth.rb")
    
    if File.exist?(file_path)
      code = File.read(file_path)
      {
        success: true,
        code: code,
        file_path: file_path.to_s,
        message: "Auth code already exists. Review and modify as needed."
      }
    else
      { success: false, error: "Auth file not found. Generate scaffold first." }
    end
  end
  
  def generate_error_handler_code(integration, documentation)
    # Error handler is already in scaffold
    file_path = Rails.root.join('app', 'services', 'integrations', integration.slug, 'error_handler.rb')
    
    if File.exist?(file_path)
      code = File.read(file_path)
      {
        success: true,
        code: code,
        file_path: file_path.to_s,
        message: "Error handler already exists. Review and modify as needed."
      }
    else
      { success: false, error: "Error handler file not found. Generate scaffold first." }
    end
  end
  
  def generate_usage_example(integration, method_name, parameters)
    # Create example parameter values
    example_params = parameters.map do |key, type|
      value = case type
              when 'string' then "'example_value'"
              when 'integer' then '123'
              when 'boolean' then 'true'
              when 'array' then '[]'
              when 'object' then '{}'
              else "'value'"
              end
      "#{key}: #{value}"
    end.join(', ')
    
    <<~RUBY
      # Usage example:
      connection = Connection.find_by(integration_slug: '#{integration.slug}')
      service = Integrations::#{integration.slug.camelize}::#{integration.slug.camelize}Service.new(connection)
      result = service.#{method_name}(#{example_params})
      
      if result[:success]
        puts result[:data]
      else
        puts "Error: \#{result[:error]}"
      end
    RUBY
  end
end

