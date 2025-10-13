module Tools
  class GenerateIntegrationScaffoldTool < BaseTool
    def self.metadata
      {
        name: 'generate_integration_scaffold',
        description: 'Generate the base structure for a new integration including models, migrations, and base service',
        category: 'integration',
        input_schema: {
          type: 'object',
          properties: {
            app_name: {
              type: 'string',
              description: 'Name of the application being integrated (e.g., "Stripe", "Mailchimp")'
            },
            slug: {
              type: 'string',
              description: 'URL-safe slug for the integration (e.g., "stripe", "mailchimp")'
            },
            auth_type: {
              type: 'string',
              enum: ['oauth2', 'api_key', 'basic_auth', 'bearer_token'],
              description: 'Type of authentication used by the API'
            },
            base_url: {
              type: 'string',
              description: 'Base URL for the API (e.g., "https://api.stripe.com")'
            },
            description: {
              type: 'string',
              description: 'Brief description of what the integration does'
            }
          },
          required: ['app_name', 'auth_type']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      app_name = get_arg(args, :app_name)
      slug = get_arg(args, :slug) || app_name.downcase.gsub(/\s+/, '_')
      auth_type = get_arg(args, :auth_type)
      base_url = get_arg(args, :base_url)
      description = get_arg(args, :description, "Integration with #{app_name}")
      
      # Validate required args
      if error = validate_required_args(args, [:app_name, :auth_type])
        return error
      end
      
      begin
        # Generate scaffold using service
        scaffold_service = IntegrationScaffoldService.new
        result = scaffold_service.generate_scaffold(
          app_name: app_name,
          slug: slug,
          auth_type: auth_type,
          base_url: base_url,
          description: description,
          entity: @entity,
          user: @user
        )
        
        if result[:success]
          success_response(
            message: "Successfully generated integration scaffold for #{app_name}",
            integration_id: result[:integration_id],
            files_created: result[:files_created],
            next_steps: [
              "Review the generated files in app/services/integrations/#{slug}/",
              "Add your API credentials to the connection",
              "Implement specific endpoints in the service class"
            ]
          )
        else
          error_response("Scaffold generation failed: #{result[:error]}")
        end
      rescue => e
        Rails.logger.error "Integration scaffold generation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Scaffold generation failed: #{e.message}")
      end
    end
  end
end

