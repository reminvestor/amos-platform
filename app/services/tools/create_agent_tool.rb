module Tools
  class CreateAgentTool < BaseTool
    # DEPRECATED: Agent creation is no longer used. The agent system has been removed.
    
    def self.metadata
      {
        name: "create_agent",
        description: <<~DESC.strip,
          DEPRECATED - DO NOT USE. The agent system has been removed.
          Amos now handles all tasks directly using available tools.
          
          Before creating an agent, you should:
          1. Use 'list_tools' to see available tools that can be assigned
          2. Consider what capabilities the agent needs
          3. Write a comprehensive system prompt that defines the agent's role, objectives, and constraints
          
          The agent will be created in 'draft' status by default. Set status to 'active' to make it immediately usable.
        DESC
        category: "system",
        input_schema: {
          type: "object",
          properties: {
            name: { 
              type: "string", 
              description: "Display name for the agent (e.g., 'SEO Content Auditor', 'Customer Research Agent')" 
            },
            slug: { 
              type: "string", 
              description: <<~SLUG.strip
                Unique identifier in snake_case (e.g., 'seo_content_auditor'). Auto-generated from name if not provided.
                
                IMPORTANT: The slug determines how the agent's output is categorized:
                - Contains 'weather' → info_retrieved (🌤️)
                - Contains 'research' or 'analyst' → research_completed (🔍)
                - Contains 'report' → report_generated (📊)
                - Contains 'email' or 'campaign' → email_drafted/email_sent (✉️)
                - Contains 'landing_page' → landing_page_created (📄)
                - Default → task_completed (✅)
              SLUG
            },
            role: { 
              type: "string", 
              enum: %w[executor planner analyst verifier fixer architect engineer custom],
              description: "The agent's role type. 'executor' is most common for task-oriented agents."
            },
            description: { 
              type: "string", 
              description: "Brief description of what the agent does (1-2 sentences)" 
            },
            system_prompt: { 
              type: "string", 
              description: <<~PROMPT.strip
                The master prompt that defines the agent's behavior. Should include:
                - Role definition (who the agent is)
                - Objectives (what it should accomplish)
                - Constraints (what it should NOT do)
                - Output format expectations
                
                IMPORTANT - User Interaction:
                If the agent needs user input (location, preferences, etc.), instruct it to use the 
                'ask_user' tool. Text responses complete the task - ask_user pauses and waits for reply.
                
                Valid work_types the agent can produce (determines how output is displayed):
                - task_completed: General task completion
                - report_generated: Reports/documents
                - research_completed: Research results
                - analysis_completed: Data analysis
                - visualization_created: Charts/graphs
                - info_retrieved: Information lookups (weather, etc.)
                - email_sent / email_drafted: Email work
                - landing_page_created / campaign_created: Marketing assets
                - agent_created / tool_created: System objects
                - asset_created: General assets
                - integration_synced: Integration work
                - action_required: Needs user action
              PROMPT
            },
            capabilities: { 
              type: "array", 
              items: { 
                type: "object",
                properties: {
                  name: { type: "string", description: "Capability name (e.g., 'content_analysis')" },
                  schema: { 
                    type: "object", 
                    description: "Optional JSON schema defining inputs/outputs for this capability"
                  }
                },
                required: ["name"]
              },
              description: "List of capabilities this agent has. Used for agent discovery."
            },
            tools: {
              type: "array",
              items: { type: "string" },
              description: "List of tool names to enable for this agent. Use 'list_tools' to see available tools."
            },
            ai_model: {
              type: "string",
              description: "AI model to use (default: 'claude-sonnet-4'). Options: 'claude-sonnet-4', 'claude-opus-4', 'gpt-4o'"
            },
            status: {
              type: "string",
              enum: %w[draft active],
              description: "Initial status. 'draft' for testing, 'active' to make immediately usable."
            },
            skip_test: {
              type: "boolean",
              description: "Skip the validation test (not recommended). Default: false"
            }
          },
          required: ["name", "role", "system_prompt"]
        }
      }
    end

    def execute(args)
      Rails.logger.info "🏭 Creating agent via AgentFactory: #{args['name']}"

      # Check user limits
      unless @user.admin?
        current_count = AgentPlugin.where(entity_id: @entity.id, user_id: @user.id).count
        limit = @user.agents_limit || 10
        
        if current_count >= limit
          return error_response("You have reached the limit of #{limit} custom agents. Please upgrade your plan or delete unused agents.")
        end
      end

      # Use the AgentFactory
      factory = Factories::AgentFactory.new(user: @user, entity: @entity)
      
      result = factory.create(
        name: args["name"],
        slug: args["slug"],
        role: args["role"],
        description: args["description"],
        system_prompt: args["system_prompt"],
        capabilities: args["capabilities"],
        tools: args["tools"],
        ai_model: args["ai_model"],
        status: args["status"] || "draft",
        skip_test: args["skip_test"] || false
      )

      if result[:success]
        agent = result[:agent]
        
        response = {
          success: true,
          message: "Successfully created agent '#{agent.name}' (#{agent.slug})",
          agent: {
            id: agent.id,
            name: agent.name,
            slug: agent.slug,
            role: agent.role,
            status: agent.status,
            tools_count: agent.agent_tools.count,
            capabilities: agent.capability_names
          }
        }

        # Include warnings if any
        if result[:warnings].present?
          response[:warnings] = result[:warnings]
          response[:message] += ". Note: #{result[:warnings].join('; ')}"
        end

        response
      else
        error_response(result[:error], errors: result[:errors], warnings: result[:warnings])
      end
    rescue => e
      Rails.logger.error "CreateAgentTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to create agent: #{e.message}")
    end
  end
end

