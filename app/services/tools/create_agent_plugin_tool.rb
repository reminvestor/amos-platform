module Tools
  class CreateAgentPluginTool < BaseTool
    def self.metadata
      {
        name: "create_agent_plugin",
        description: "Creates a new AI Agent Plugin in the system. Use this to build new agents.",
        category: "system",
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
      name = args["name"]
      slug = args["slug"]
      role = args["role"]
      system_prompt = args["system_prompt"]
      capabilities = args["capabilities"] || []
      tools = args["tools"] || []

      # Basic validation
      if AgentPlugin.exists?(slug: slug)
        return error_response("Agent with slug '#{slug}' already exists. Please choose a different one.")
      end

      ActiveRecord::Base.transaction do
        # Create the agent
        agent = AgentPlugin.create!(
          name: name,
          slug: slug,
          role: role,
          description: args["description"] || "Custom agent created by Agent Architect",
          version: "1.0.0",
          status: "active", # Auto-activate for now
          priority: 50,
          system_prompt: { prompt: system_prompt },
          configuration: {} # Default empty config
        )

        # Add capabilities
        capabilities.each do |cap|
          agent.agent_capabilities.create!(
            capability_name: cap["name"] || cap["capability_name"],
            contract_schema: cap["contract_schema"] || cap["schema"] || {}
          )
        end

        # Add tools
        # Always add 'ask_user' and 'get_data' by default if not specified, as they are essential
        tools << "ask_user" unless tools.include?("ask_user")
        tools << "get_data" unless tools.include?("get_data")
        
        tools.each do |tool_name|
          # Verify tool exists in catalog
          if Tools::ToolCatalog.instance.get_tool_definition(tool_name)
            agent.agent_tools.create!(tool_name: tool_name)
          end
        end

        {
          success: true,
          message: "Successfully created agent: #{name} (#{slug})",
          agent: {
            id: agent.id,
            name: agent.name,
            slug: agent.slug,
            tools_count: agent.agent_tools.count,
            capabilities_count: agent.agent_capabilities.count
          }
        }
      end
    rescue => e
      Rails.logger.error "Failed to create agent: #{e.message}"
      error_response("Failed to create agent: #{e.message}")
    end
  end
end

