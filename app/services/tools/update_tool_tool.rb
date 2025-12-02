module Tools
  class UpdateToolTool < BaseTool
    def self.metadata
      {
        name: "update_tool",
        description: <<~DESC.strip,
          Updates an existing custom Tool that you created. You can modify the tool's description,
          parameters, code, or API configuration.
          
          Note: You can only update tools that you created. System tools cannot be modified.
          
          Use this tool when:
          - A tool isn't working correctly and needs fixing
          - You need to update an API endpoint or add new parameters
          - The tool's logic needs to be changed
        DESC
        category: "system",
        input_schema: {
          type: "object",
          properties: {
            tool_name: { 
              type: "string", 
              description: "The name of the tool to update" 
            },
            description: { 
              type: "string", 
              description: "New description for the tool" 
            },
            parameters: { 
              type: "object", 
              description: "New JSON Schema for the tool's input parameters" 
            },
            api_config: {
              type: "object",
              description: "New API configuration (for http_request tools)"
            },
            code: { 
              type: "string", 
              description: "New Ruby code (for ruby_code tools)" 
            }
          },
          required: ["tool_name"]
        }
      }
    end

    def execute(args)
      tool_name = args["tool_name"]
      Rails.logger.info "🔧 Updating tool: #{tool_name}"

      # Find the tool
      tool = ToolDefinition.find_by(name: tool_name)
      
      unless tool
        return error_response("Tool '#{tool_name}' not found. Note: You can only update custom tools, not built-in tools.")
      end

      # Check ownership
      unless tool.editable_by?(@user)
        return error_response("You don't have permission to edit '#{tool.name}'. You can only edit tools you created.")
      end

      # Use the ToolFactory for validated updates
      factory = Factories::ToolFactory.new(user: @user, entity: @entity)
      
      update_params = {}
      update_params[:description] = args["description"] if args["description"].present?
      update_params[:parameters] = args["parameters"] if args["parameters"].present?
      update_params[:api_config] = args["api_config"] if args["api_config"].present?
      update_params[:code] = args["code"] if args["code"].present?

      if update_params.empty?
        return error_response("No updates provided. Specify at least one field to update.")
      end

      result = factory.update(tool, update_params)

      if result[:success]
        tool = result[:tool]
        
        response = {
          success: true,
          message: "Successfully updated tool '#{tool.name}'",
          tool: {
            id: tool.id,
            name: tool.name,
            description: tool.description,
            execution_type: tool.execution_type,
            parameters: tool.parameters
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
      Rails.logger.error "UpdateToolTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to update tool: #{e.message}")
    end
  end
end

