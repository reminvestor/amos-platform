module Tools
  class CreateAgentPluginTool < BaseTool
    # DEPRECATED: Agent plugins have been removed from the platform.
    
    def self.metadata
      {
        name: "create_agent_plugin",
        description: <<~DESC.strip,
          DEPRECATED - DO NOT USE. Agent plugins have been removed from the platform.
          Amos now handles all tasks directly using available tools.
        DESC
        category: "deprecated",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Display name (e.g. 'SEO Auditor')" },
            slug: { type: "string", description: "Unique identifier (e.g. 'seo_auditor')" },
            role: { type: "string", description: "Role type (executor, analyst, verifier, architect)" },
            description: { type: "string", description: "Short description of what the agent does" },
            system_prompt: { type: "string", description: "The master prompt that defines the agent's behavior and personality" },
            capabilities: { 
              type: "array", 
              items: { type: "object" },
              description: "List of capabilities (name, schema)"
            },
            tools: {
              type: "array",
              items: { type: "string" },
              description: "List of tool names to enable for this agent"
            }
          },
          required: ["name", "slug", "role", "system_prompt"]
        }
      }
    end

    def execute(args)
      # Delegate to the new AgentFactory-based tool
      Rails.logger.info "🏭 CreateAgentPluginTool delegating to AgentFactory"

      # Check user limits
      unless @user.admin?
        current_count = AgentPlugin.where(entity_id: @entity.id, user_id: @user.id).count
        limit = @user.agents_limit || 10
        
        if current_count >= limit
          return error_response("You have reached the limit of #{limit} custom agents. Please contact support to increase your limit.")
        end
      end

      # Use the AgentFactory for proper validation
      factory = Factories::AgentFactory.new(user: @user, entity: @entity)
      
      result = factory.create(
        name: args["name"],
        slug: args["slug"],
        role: args["role"],
        description: args["description"] || "Custom agent created by Agent Architect",
        system_prompt: args["system_prompt"],
        capabilities: args["capabilities"],
        tools: args["tools"],
        status: "active", # Legacy behavior: auto-activate
        skip_test: true   # Legacy behavior: skip test
      )

      if result[:success]
        agent = result[:agent]
        
        {
          success: true,
          message: "Successfully created agent: #{agent.name} (#{agent.slug})",
          agent: {
            id: agent.id,
            name: agent.name,
            slug: agent.slug,
            tools_count: agent.agent_tools.count,
            capabilities_count: agent.agent_capabilities.count
          }
        }
      else
        error_response(result[:error])
      end
    rescue => e
      Rails.logger.error "Failed to create agent: #{e.message}"
      error_response("Failed to create agent: #{e.message}")
    end
  end
end

