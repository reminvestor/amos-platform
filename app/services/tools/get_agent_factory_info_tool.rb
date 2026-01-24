module Tools
  class GetAgentFactoryInfoTool < BaseTool
    # DEPRECATED: Agent factory info is no longer used. The agent system has been removed.
    
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: "get_agent_factory_info",
        description: <<~DESC.strip,
          DEPRECATED - DO NOT USE. The agent system has been removed.
          Use discover_tools to find available capabilities.
          - Available integrations for the entity
          - Best practices for agent creation
          - Valid roles and configuration options
          
          Use this before creating an agent to understand what tools and capabilities are available.
        DESC
        category: "system",
        input_schema: {
          type: "object",
          properties: {
            include_tools: {
              type: "boolean",
              description: "Include list of available tools. Default: true"
            },
            include_integrations: {
              type: "boolean",
              description: "Include list of available integrations. Default: true"
            },
            include_best_practices: {
              type: "boolean",
              description: "Include agent creation best practices. Default: true"
            },
            tool_category: {
              type: "string",
              description: "Filter tools by category (e.g., 'data', 'analytics', 'system')"
            }
          }
        }
      }
    end

    def execute(args)
      include_tools = args["include_tools"] != false
      include_integrations = args["include_integrations"] != false
      include_best_practices = args["include_best_practices"] != false
      tool_category = args["tool_category"]

      result = {
        success: true,
        valid_roles: Factories::AgentFactory::VALID_ROLES,
        valid_execution_strategies: Factories::AgentFactory::VALID_STRATEGIES
      }

      if include_tools
        result[:available_tools] = get_available_tools(tool_category)
      end

      if include_integrations
        result[:available_integrations] = get_available_integrations
      end

      if include_best_practices
        result[:best_practices] = get_best_practices
      end

      result
    rescue => e
      Rails.logger.error "GetAgentFactoryInfoTool error: #{e.message}"
      error_response("Failed to get factory info: #{e.message}")
    end

    private

    def get_available_tools(category = nil)
      catalog = Tools::ToolCatalog.instance
      
      # Refresh to pick up any newly created ToolDefinitions
      catalog.refresh_dynamic_tools!
      
      tools = catalog.all_tools

      if category.present?
        tools = tools.select { |_, info| info[:metadata][:category] == category }
      end

      # Get tools from catalog
      catalog_tools = tools.map do |name, info|
        {
          name: name,
          description: info[:metadata][:description],
          category: info[:metadata][:category],
          read_only: info[:read_only],
          parameters: summarize_parameters(info[:metadata][:input_schema] || info[:metadata][:parameters]),
          source: info[:type] == :definition ? 'custom' : 'system'
        }
      end

      # Also include any ToolDefinitions that might not be in catalog yet
      # (in case refresh didn't work or there's a race condition)
      # Only query DB if we have few custom tools in catalog (optimization)
      custom_tool_count = catalog_tools.count { |t| t[:source] == 'custom' }
      
      if defined?(ToolDefinition) && ToolDefinition.table_exists?
        db_tool_count = ToolDefinition.count
        
        # Only do fallback query if counts don't match
        if db_tool_count > custom_tool_count
          catalog_tool_names = catalog_tools.map { |t| t[:name] }
          
          ToolDefinition.where.not(name: catalog_tool_names).find_each do |td|
            catalog_tools << {
              name: td.name,
              description: td.description,
              category: td.category || 'custom',
              read_only: false,
              parameters: summarize_parameters(td.parameters),
              source: 'custom',
              security_rating: td.security_rating
            }
          end
        end
      end

      catalog_tools.sort_by { |t| [t[:category] || 'zzz', t[:name]] }
    end

    def summarize_parameters(schema)
      return nil if schema.blank?
      return nil unless schema.is_a?(Hash)

      props = schema['properties'] || schema[:properties]
      return nil if props.blank?

      required = schema['required'] || schema[:required] || []

      props.map do |name, definition|
        {
          name: name,
          type: definition['type'] || definition[:type],
          required: required.include?(name) || required.include?(name.to_s)
        }
      end
    end

    def get_available_integrations
      return [] unless @entity

      factory = Factories::AgentFactory.new(user: @user, entity: @entity)
      factory.available_integrations
    end

    def get_best_practices
      {
        system_prompt: {
          structure: [
            "Start with a clear role definition: 'You are a [role] specialized in [domain].'",
            "Define specific objectives: 'Your goal is to [objective].'",
            "Set constraints: 'You should NOT [constraint].'",
            "Specify output format: 'Always respond with [format].'",
            "Include examples if the task is complex."
          ],
          tips: [
            "Be specific about the agent's expertise area",
            "Include error handling instructions",
            "Define how the agent should handle ambiguous requests",
            "Specify when to ask for clarification vs. make assumptions"
          ]
        },
        capabilities: {
          purpose: "Capabilities are used for agent discovery - they help Scout find the right agent for a task.",
          examples: [
            { name: "web_research", use_case: "Finding information online" },
            { name: "content_creation", use_case: "Writing articles, emails, etc." },
            { name: "data_analysis", use_case: "Analyzing datasets and metrics" },
            { name: "code_generation", use_case: "Writing or reviewing code" }
          ]
        },
        tools: {
          essential: ["ask_user", "get_data"],
          recommended_by_role: {
            executor: ["invoke_operation", "create_object", "update_object"],
            analyst: ["query_metric", "get_data", "create_dynamic_visualization"],
            planner: ["delegate_to_agent", "manage_task_list"],
            verifier: ["get_data", "query_document_content"]
          }
        },
        roles: {
          executor: "General-purpose agent that performs tasks",
          planner: "Creates plans and coordinates other agents",
          analyst: "Analyzes data and provides insights",
          verifier: "Validates and checks work quality",
          fixer: "Identifies and resolves issues",
          architect: "Designs systems and workflows",
          engineer: "Implements technical solutions",
          custom: "User-defined role"
        }
      }
    end
  end
end

