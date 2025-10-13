class IntegrationEndpointTester
  attr_reader :integration, :connection
  
  def initialize(integration, connection)
    @integration = integration
    @connection = connection
  end
  
  def test_endpoint(endpoint_name, test_params = {})
    Rails.logger.info "🧪 Testing endpoint: #{endpoint_name} for #{integration.name}"
    
    begin
      # Load the service class
      service_class = load_service_class
      
      if !service_class
        return {
          success: false,
          error: "Service class not found for #{integration.slug}",
          troubleshooting: [
            "Ensure the scaffold has been generated",
            "Check that the service file exists at app/services/integrations/#{integration.slug}/",
            "Verify the class name matches the expected pattern"
          ]
        }
      end
      
      # Initialize the service
      service = service_class.new(connection)
      
      # Check if method exists
      method_name = endpoint_name.underscore
      if !service.respond_to?(method_name)
        return {
          success: false,
          error: "Method '#{method_name}' not found in service",
          available_methods: service.public_methods(false).map(&:to_s),
          troubleshooting: [
            "Ensure the endpoint has been generated",
            "Check the operations.rb file for the method definition",
            "Method name should be: #{method_name}"
          ]
        }
      end
      
      # Execute the method
      start_time = Time.current
      result = service.public_send(method_name, **test_params.symbolize_keys)
      end_time = Time.current
      
      response_time = ((end_time - start_time) * 1000).round(2)
      
      if result[:success]
        {
          success: true,
          response: result[:data],
          status_code: result[:status],
          response_time_ms: response_time,
          headers: result[:headers]
        }
      else
        {
          success: false,
          error: result[:error],
          status_code: result[:status],
          response: result,
          response_time_ms: response_time,
          troubleshooting: generate_troubleshooting(result)
        }
      end
      
    rescue ArgumentError => e
      {
        success: false,
        error: "Invalid parameters: #{e.message}",
        troubleshooting: [
          "Check that all required parameters are provided",
          "Verify parameter types match the endpoint requirements",
          "Review the endpoint documentation for required fields"
        ]
      }
    rescue => e
      Rails.logger.error "Test failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      {
        success: false,
        error: e.message,
        error_class: e.class.name,
        troubleshooting: [
          "Check the error message for specific details",
          "Verify your API credentials are correct",
          "Ensure the API endpoint is accessible",
          "Review the integration logs for more information"
        ]
      }
    end
  end
  
  private
  
  def load_service_class
    # Try to load the service class
    class_name = "Integrations::#{integration.slug.camelize}::#{integration.slug.camelize}Service"
    
    begin
      class_name.constantize
    rescue NameError
      # Try requiring the file first
      require_path = Rails.root.join('app', 'services', 'integrations', integration.slug, "#{integration.slug}_service.rb")
      
      if File.exist?(require_path)
        load require_path
        class_name.constantize rescue nil
      else
        nil
      end
    end
  end
  
  def generate_troubleshooting(result)
    tips = []
    
    case result[:error_type]
    when 'unauthorized'
      tips << "Verify your API credentials are correct"
      tips << "Check if your API token has expired"
      tips << "Ensure you have the necessary permissions"
    when 'forbidden'
      tips << "Check if your API key has the required scopes/permissions"
      tips << "Verify you're accessing a resource you own"
    when 'not_found'
      tips << "Verify the resource ID exists"
      tips << "Check the endpoint URL is correct"
      tips << "Ensure you're using the right API version"
    when 'rate_limit'
      tips << "Wait before making more requests"
      tips << "Implement rate limiting in your code"
      tips << "Consider upgrading your API plan"
    when 'bad_request'
      tips << "Check your request parameters"
      tips << "Verify data types and formats"
      tips << "Review the API documentation for this endpoint"
    else
      tips << "Review the error message for specific details"
      tips << "Check the API status page for outages"
      tips << "Verify your network connection"
    end
    
    tips
  end
end

