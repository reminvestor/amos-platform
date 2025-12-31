module Tools
  class CreateIntegrationFoundationTool < BaseTool
    def self.metadata
      {
        name: "create_integration_foundation",
        description: <<~DESC.strip,
          **STAGE 1 of 4: Create Integration Foundation**
          
          This is the FIRST step in creating an integration. It creates the basic integration
          record with name, base URL, and documentation. Auth and operations come later.
          
          **Before calling this tool:**
          1. Use web_search to find the official API documentation
          2. Verify the exact base URL from the documentation
          3. Identify the documentation URL
          
          **After this succeeds, you MUST call:**
          → configure_integration_auth (Stage 2)
          
          The integration will be in "pending_auth" status until auth is configured.
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Display name for the integration (e.g., 'Trello', 'Slack', 'Notion')"
            },
            base_url: {
              type: "string",
              description: "Base URL for API requests (e.g., 'https://api.trello.com'). Get this from official docs!"
            },
            documentation_url: {
              type: "string",
              description: "Link to official API documentation - REQUIRED"
            },
            description: {
              type: "string",
              description: "Brief description of what the integration does"
            },
            category: {
              type: "string",
              enum: %w[payment ecommerce crm communication productivity marketing analytics custom],
              description: "Category for organization"
            },
            api_version: {
              type: "string",
              description: "API version if applicable (e.g., '2024-01', 'v3')"
            }
          },
          required: %w[name base_url documentation_url]
        }
      }
    end

    def execute(args)
      log_execution(args)

      # Check if entity already has this integration (prefer entity-owned)
      existing_entity_integration = Integration.owned_by_entity(@entity).find_by(
        "slug = ? OR LOWER(name) = LOWER(?)", 
        args["name"]&.downcase&.gsub(/[^a-z0-9]+/, '_'), 
        args["name"]
      )
      
      if existing_entity_integration
        return error_response(
          "Integration '#{args['name']}' already exists for this entity",
          existing_integration: {
            id: existing_entity_integration.id,
            slug: existing_entity_integration.slug,
            status: existing_entity_integration.is_active ? 'active' : 'inactive'
          },
          suggestion: "Use the existing integration or update it if needed"
        )
      end

      # Check if there's a global template to copy from
      global_template = Integration.global.find_by(
        "slug = ? OR LOWER(name) = LOWER(?)",
        args["name"]&.downcase&.gsub(/[^a-z0-9]+/, '_'),
        args["name"]
      )

      if global_template
        Rails.logger.info "📋 Found global template '#{global_template.name}' - creating entity-specific instance"
        
        # Instantiate from template
        begin
          entity_integration = global_template.instantiate_for_entity(
            @entity, 
            @user,
            api_base_url: args["base_url"],  # Allow override
            description: args["description"]
          )
          
          return success_response(
            message: "✅ Integration created from template! Now configure authentication.",
            integration_id: entity_integration.id,
            integration_slug: entity_integration.slug,
            integration_name: entity_integration.name,
            base_url: entity_integration.api_base_url,
            created_from_template: true,
            template_id: global_template.id,
            status: "pending_auth",
            next_step: "STAGE 2: Call configure_integration_auth to set up authentication"
          )
        rescue => e
          Rails.logger.error "Failed to instantiate from template: #{e.message}"
          # Fall through to create fresh
        end
      end

      factory = Factories::IntegrationFactory.new(user: @user, entity: @entity)

      result = factory.create_foundation(
        name: args["name"],
        base_url: args["base_url"],
        documentation_url: args["documentation_url"],
        description: args["description"],
        category: args["category"],
        api_version: args["api_version"]
      )

      if result[:success]
        success_response(
          message: "✅ Integration foundation created! Now research and configure authentication.",
          integration_id: result[:integration].id,
          integration_slug: result[:integration].slug,
          integration_name: result[:integration].name,
          base_url: result[:integration].api_base_url,
          status: "pending_auth",
          next_step: "STAGE 2: Research the authentication method for #{args['name']} API, then call configure_integration_auth",
          research_prompts: [
            "#{args['name']} API authentication method",
            "#{args['name']} API key vs OAuth",
            "How to authenticate with #{args['name']} API"
          ]
        )
      else
        error_response(
          "Foundation creation failed: #{result[:errors].join(', ')}",
          warnings: result[:warnings]
        )
      end
    rescue => e
      Rails.logger.error "CreateIntegrationFoundationTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to create integration foundation: #{e.message}")
    end
  end
end

