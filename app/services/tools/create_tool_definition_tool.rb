module Tools
  class CreateToolDefinitionTool < BaseTool
    def self.metadata
      {
        name: "create_tool_definition",
        description: "Creates a new custom Tool that agents can use. Can be an HTTP API wrapper or Ruby code.",
        category: "system",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Tool name (snake_case, e.g. 'search_github')" },
            description: { type: "string", description: "What the tool does" },
            execution_type: { type: "string", enum: ["http_request", "ruby_code"] },
            input_schema: { type: "object", description: "JSON Schema for the tool arguments" },
            
            # For HTTP tools
            api_config: {
              type: "object",
              properties: {
                url: { type: "string" },
                method: { type: "string", enum: ["GET", "POST", "PUT", "DELETE"] },
                headers: { type: "object" }
              }
            },
            
            # For Ruby tools
            code: { type: "string", description: "The Ruby code to execute (for 'ruby_code' type)" }
          },
          required: ["name", "description", "execution_type", "input_schema"]
        }
      }
    end

    def execute(args)
      name = args["name"]
      exec_type = args["execution_type"]
      
      # Check availability
      if ToolDefinition.exists?(name: name) || Tools::ToolCatalog.instance.get_tool_definition(name)
        return error_response("Tool '#{name}' already exists. Please choose a unique name.")
      end

      # Check user limits
      unless @user.admin?
        current_count = ToolDefinition.where(created_by: @user).count
        limit = @user.tools_limit || 5
        
        if current_count >= limit
          return error_response("You have reached the limit of #{limit} custom tools. Please contact support to increase your limit.")
        end
      end

      tool = ToolDefinition.create!(
        name: name,
        description: args["description"],
        execution_type: exec_type,
        parameters: args["input_schema"],
        api_config: args["api_config"],
        code: args["code"],
        admin_only: false # Created via agent = public
      )

      # Refresh catalog so it's immediately available
      Tools::ToolCatalog.instance.refresh_dynamic_tools!

      {
        success: true,
        message: "Tool '#{name}' created successfully!",
        tool_id: tool.id,
        usage: "Agents can now be assigned this tool by name: '#{name}'"
      }
    rescue => e
      Rails.logger.error "Failed to create tool: #{e.message}"
      error_response("Failed to create tool: #{e.message}")
    end
  end
end

