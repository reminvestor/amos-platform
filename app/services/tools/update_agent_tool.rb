module Tools
  class UpdateAgentTool < BaseTool
    # DEPRECATED: Agent updates are no longer used. The agent system has been removed.
    
    def self.metadata
      {
        name: "update_agent",
        description: <<~DESC.strip,
          DEPRECATED - DO NOT USE. The agent system has been removed.
          Amos now handles all tasks directly using available tools.
          
          Use this tool when a user asks to:
          - Fix or improve an agent that isn't working correctly
          - Add new tools or capabilities to an agent
          - Change the agent's behavior by updating the system prompt
          - Activate or deactivate an agent
          - Adjust an agent's configuration
        DESC
        category: "system",
        input_schema: {
          type: "object",
          properties: {
            agent_identifier: { 
              type: "string", 
              description: "The agent's slug, name, or ID to update" 
            },
            name: { 
              type: "string", 
              description: "New display name for the agent" 
            },
            description: { 
              type: "string", 
              description: "New description" 
            },
            system_prompt: { 
              type: "string", 
              description: "New system prompt (replaces existing)" 
            },
            capabilities: { 
              type: "array", 
              items: { 
                type: "object",
                properties: {
                  name: { type: "string" },
                  schema: { type: "object" }
                }
              },
              description: "New list of capabilities (replaces existing)"
            },
            tools: {
              type: "array",
              items: { type: "string" },
              description: "New list of tool names (replaces existing)"
            },
            ai_model: {
              type: "string",
              description: "New AI model to use"
            },
            status: {
              type: "string",
              enum: %w[draft active deprecated],
              description: "New status for the agent"
            },
            skip_test: {
              type: "boolean",
              description: "Skip validation test after update. Default: false"
            }
          },
          required: ["agent_identifier"]
        }
      }
    end

    def execute(args)
      agent_identifier = args["agent_identifier"]
      Rails.logger.info "🔧 Updating agent: #{agent_identifier}"

      # Find the agent
      agent = find_agent(agent_identifier)
      
      unless agent
        return error_response("Agent '#{agent_identifier}' not found. Use 'list_available_agents' to see your agents.")
      end

      # Check ownership
      unless agent.editable_by?(@user)
        return error_response("You don't have permission to edit '#{agent.name}'. You can only edit agents you created.")
      end

      # Use the AgentFactory for validated updates
      factory = Factories::AgentFactory.new(user: @user, entity: @entity)
      
      update_params = {}
      update_params[:name] = args["name"] if args["name"].present?
      update_params[:description] = args["description"] if args["description"].present?
      update_params[:system_prompt] = args["system_prompt"] if args["system_prompt"].present?
      update_params[:capabilities] = args["capabilities"] if args["capabilities"].present?
      update_params[:tools] = args["tools"] if args["tools"].present?
      update_params[:ai_model] = args["ai_model"] if args["ai_model"].present?
      update_params[:status] = args["status"] if args["status"].present?
      update_params[:skip_test] = args["skip_test"] || false

      if update_params.except(:skip_test).empty?
        return error_response("No updates provided. Specify at least one field to update.")
      end

      result = factory.update(agent, update_params)

      if result[:success]
        agent = result[:agent]
        
        response = {
          success: true,
          message: "Successfully updated agent '#{agent.name}'",
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

        if result[:warnings].present?
          response[:warnings] = result[:warnings]
        end

        response
      else
        error_response(result[:error], errors: result[:errors], warnings: result[:warnings])
      end
    rescue => e
      Rails.logger.error "UpdateAgentTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to update agent: #{e.message}")
    end

    private

    def find_agent(identifier)
      # SECURITY: All lookups scoped to entity to prevent cross-entity agent access
      # Try by ID first
      if identifier.to_s.match?(/^\d+$/)
        agent = AgentPlugin.find_by(id: identifier, entity: @entity)
        return agent if agent
      end

      # Try by slug (check entity-specific first, then system agents with nil entity)
      agent = AgentPlugin.find_by(slug: identifier.to_s.parameterize.underscore, entity: @entity)
      agent ||= AgentPlugin.find_by(slug: identifier.to_s.parameterize.underscore, entity: nil)
      return agent if agent

      # Try by exact name (entity-scoped)
      agent = AgentPlugin.where(entity: @entity).where("LOWER(name) = ?", identifier.to_s.downcase).first
      return agent if agent

      # Try partial name match (entity-scoped)
      AgentPlugin.where(entity: @entity).where("LOWER(name) LIKE ?", "%#{identifier.to_s.downcase}%").first
    end
  end
end

