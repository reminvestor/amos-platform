module Tools
  class GenerateIntegrationScaffoldTool < BaseTool
    def self.metadata
      {
        name: "generate_integration_scaffold",
        description: "Generate the base structure for a new integration including models, migrations, and base service",
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            app_name: {
              type: "string",
              description: 'Name of the application being integrated (e.g., "Stripe", "Mailchimp")'
            },
            slug: {
              type: "string",
              description: 'URL-safe slug for the integration (e.g., "stripe", "mailchimp")'
            },
            auth_type: {
              type: "string",
              enum: [ "oauth2", "api_key", "basic_auth", "bearer_token" ],
              description: "Type of authentication used by the API"
            },
            base_url: {
              type: "string",
              description: 'Base URL for the API (e.g., "https://api.stripe.com")'
            },
            description: {
              type: "string",
              description: "Brief description of what the integration does"
            }
          },
          required: [ "app_name", "auth_type" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      app_name = get_arg(args, :app_name)
      slug = get_arg(args, :slug) || app_name.downcase.gsub(/\s+/, "_")
      auth_type = get_arg(args, :auth_type)
      base_url = get_arg(args, :base_url)
      description = get_arg(args, :description, "Integration with #{app_name}")

      # Validate required args
      if error = validate_required_args(args, [ :app_name, :auth_type ])
        return error
      end

      begin
        # Create integration record in database (secure - no code generation!)
        integration = Integration.create!(
          name: app_name,
          slug: slug,
          description: description,
          category: "custom",
          auth_type: auth_type,
          api_base_url: base_url || "https://api.#{slug}.com",
          is_active: true,
          is_custom: true,
          metadata: {
            created_by: "ai_integration_builder",
            created_at: Time.current
          }
        )

        # Create connection for the user
        connection = Connection.create!(
          integration: integration,
          entity: @entity,
          name: "#{app_name} Connection",
          status: :disconnected,
          metadata: {
            created_by: "ai_integration_builder",
            setup_required: true
          }
        )

        # Create pending credential
        connection.integration_credentials.create!(
          name: "#{app_name} Credentials",
          credentials: {}.to_json,
          auth_method: determine_auth_method(auth_type),
          status: :expired,
          metadata: { pending_setup: true }
        )

        result = {
          success: true,
          integration_id: integration.id,
          connection_id: connection.id
        }

        if result[:success]
          success_response(
            message: "Successfully created #{app_name} integration (secure DB-only approach)",
            integration_id: result[:integration_id],
            connection_id: result[:connection_id],
            integration_slug: slug,
            next_steps: [
              "Add your API credentials using the integrations UI",
              "Use add_integration_endpoint to add API operations",
              "Operations are stored securely in the database (no code generation)"
            ]
          )
        else
          error_response("Integration creation failed: #{result[:error]}")
        end
      rescue => e
        Rails.logger.error "Integration creation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Integration creation failed: #{e.message}")
      end
    end

    private

    def determine_auth_method(auth_type)
      case auth_type.to_s
      when "api_key", "bearer_token"
        "header"
      when "basic_auth"
        "basic"
      when "oauth2"
        "bearer"
      else
        "header"
      end
    end
  end
end
