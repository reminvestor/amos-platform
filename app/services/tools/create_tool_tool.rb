module Tools
  class CreateToolTool < BaseTool
    def self.metadata
      {
        name: "create_tool",
        description: <<~DESC.strip,
          Creates a new custom Tool that agents can use. Uses the Tool Factory for validation
          and security checks. Tools can be either HTTP API wrappers or Ruby code.
          
          HTTP Request tools are recommended for:
          - Calling external APIs
          - Fetching data from web services
          - Integrating with third-party platforms
          
          Ruby Code tools are for:
          - Data transformations
          - Calculations
          - Complex logic that can't be done via API
          
          Security Note: Ruby code tools go through security validation. Dangerous operations
          like file system access, shell commands, and eval are blocked.
        DESC
        category: "system",
        input_schema: {
          type: "object",
          properties: {
            name: { 
              type: "string", 
              description: "Tool name in snake_case (e.g., 'search_github', 'calculate_roi')" 
            },
            description: { 
              type: "string", 
              description: "Clear description of what the tool does. This helps the AI use it correctly." 
            },
            execution_type: { 
              type: "string", 
              enum: ["http_request", "ruby_code"],
              description: "Type of tool: 'http_request' for API calls, 'ruby_code' for logic"
            },
            parameters: { 
              type: "object", 
              description: <<~SCHEMA.strip
                JSON Schema defining the tool's input parameters. Example:
                {
                  "type": "object",
                  "properties": {
                    "query": { "type": "string", "description": "Search query" },
                    "limit": { "type": "integer", "description": "Max results" }
                  },
                  "required": ["query"]
                }
              SCHEMA
            },
            api_config: {
              type: "object",
              description: <<~API.strip
                For http_request tools. Configuration for the API call:
                {
                  "url": "https://api.example.com/search?q={{query}}",
                  "method": "GET",
                  "headers": { "Authorization": "Bearer {{API_KEY}}" }
                }
                Use {{param_name}} for parameter interpolation.
              API
            },
            code: { 
              type: "string", 
              description: <<~CODE.strip
                For ruby_code tools. The Ruby code to execute.
                Access parameters via _args hash: _args['query']
                Access context via _context: _context[:user], _context[:entity]
                Return a hash with your result: { success: true, data: result }
              CODE
            },
            skip_test: {
              type: "boolean",
              description: "Skip validation test. Default: false"
            }
          },
          required: ["name", "description", "execution_type", "parameters"]
        }
      }
    end

    def execute(args)
      Rails.logger.info "🔧 Creating tool via ToolFactory: #{args['name']}"

      # Check user limits
      unless @user.admin?
        current_count = ToolDefinition.where(created_by: @user).count
        limit = @user.tools_limit || 10
        
        if current_count >= limit
          return error_response("You have reached the limit of #{limit} custom tools. Please upgrade your plan or delete unused tools.")
        end
      end

      # Use the ToolFactory
      factory = Factories::ToolFactory.new(user: @user, entity: @entity)
      
      result = factory.create(
        name: args["name"],
        description: args["description"],
        execution_type: args["execution_type"],
        parameters: args["parameters"],
        api_config: args["api_config"],
        code: args["code"],
        skip_test: args["skip_test"] || false
      )

      if result[:success]
        tool = result[:tool]
        
        response = {
          success: true,
          message: "Successfully created tool '#{tool.name}'",
          tool: {
            id: tool.id,
            name: tool.name,
            description: tool.description,
            execution_type: tool.execution_type,
            parameters: tool.parameters
          },
          usage: "Agents can now use this tool by name: '#{tool.name}'. Assign it to an agent using 'update_agent'."
        }

        if result[:warnings].present?
          response[:warnings] = result[:warnings]
        end

        response
      else
        error_response(result[:error], errors: result[:errors], warnings: result[:warnings])
      end
    rescue => e
      Rails.logger.error "CreateToolTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to create tool: #{e.message}")
    end
  end
end

