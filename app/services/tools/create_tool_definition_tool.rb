module Tools
  class CreateToolDefinitionTool < BaseTool
    def self.metadata
      {
        name: "create_tool_definition",
        description: <<~DESC.strip,
          Creates a new custom Tool that agents can use. Can be an HTTP API wrapper or Ruby code.
          Uses the ToolFactory for validation and security checks.
          
          DEPRECATED: Use 'create_tool' instead for better validation and testing.
        DESC
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
      Rails.logger.info "🔧 CreateToolDefinitionTool delegating to ToolFactory"

      # Check user limits
      unless @user.admin?
        current_count = ToolDefinition.where(created_by: @user).count
        limit = @user.tools_limit || 10
        
        if current_count >= limit
          return error_response("You have reached the limit of #{limit} custom tools. Please contact support to increase your limit.")
        end
      end

      # Use the ToolFactory for proper validation
      factory = Factories::ToolFactory.new(user: @user, entity: @entity)
      
      result = factory.create(
        name: args["name"],
        description: args["description"],
        execution_type: args["execution_type"],
        parameters: args["input_schema"],
        api_config: args["api_config"],
        code: args["code"],
        skip_test: true  # Legacy behavior: skip test
      )

      if result[:success]
        tool = result[:tool]
        
        {
          success: true,
          message: "Tool '#{tool.name}' created successfully!",
          tool_id: tool.id,
          usage: "Agents can now be assigned this tool by name: '#{tool.name}'"
        }
      else
        error_response(result[:error])
      end
    rescue => e
      Rails.logger.error "Failed to create tool: #{e.message}"
      error_response("Failed to create tool: #{e.message}")
    end
  end
end

