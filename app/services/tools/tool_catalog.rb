module Tools
  class ToolCatalog
    include Singleton
    
    attr_reader :tools
    
    def initialize
      @tools = {}
      @categories = {}
      load_all_tools
    end
    
    # Register a tool class
    def register(tool_class)
      metadata = tool_class.metadata
      name = metadata[:name]
      category = metadata[:category] || 'general'
      
      @tools[name] = {
        class: tool_class,
        metadata: metadata
      }
      
      @categories[category] ||= []
      @categories[category] << name
      
      Rails.logger.info "📚 Registered tool: #{name} in category: #{category}"
    end
    
    # Get all tools (optionally filtered)
    def all_tools(filter: nil)
      case filter
      when Array
        # Filter by specific tool names
        @tools.select { |name, _| filter.include?(name) }
      when Hash
        # Filter by categories
        if filter[:categories]
          categories_to_include = Array(filter[:categories])
          @tools.select do |name, tool_info|
            categories_to_include.include?(tool_info[:metadata][:category])
          end
        else
          @tools
        end
      else
        @tools
      end
    end
    
    # Get tools for Bedrock format
    def get_bedrock_tools(allowlist: nil, agent_loadout: nil)
      tools = []
      
      # Add canvas loading tool (always available)
      tools << {
        name: "load_canvas",
        description: "Load a specific canvas view in the Scout interface",
        parameters: {
          type: "object",
          properties: {
            canvas_name: {
              type: "string",
              description: "The name of the canvas to load",
              enum: ["campaign_viewer", "analytics_dashboard", "landing_page_viewer", 
                     "contact_viewer", "email_template_viewer", "task_progress", 
                     "dynamic_canvas", "integrations_manager"]
            }
          },
          required: ["canvas_name"]
        }
      }
      
      # Filter tools based on agent loadout or allowlist
      tool_names = if agent_loadout&.tool_allowlist.present?
        agent_loadout.tool_allowlist
      elsif allowlist.present?
        allowlist
      else
        @tools.keys
      end
      
      # Convert to Bedrock format
      tool_names.each do |tool_name|
        next if tool_name == '*' # Skip wildcard
        
        if tool_info = @tools[tool_name]
          metadata = tool_info[:metadata]
          tools << {
            name: metadata[:name],
            description: metadata[:description],
            parameters: metadata[:input_schema] || metadata[:parameters]
          }
        end
      end
      
      Rails.logger.info "🤖 Providing #{tools.length} tools to Bedrock (filtered from #{@tools.length} total)"
      tools
    end
    
    # Get tool instance
    def get_tool(name, context = {})
      tool_info = @tools[name]
      return nil unless tool_info
      
      tool_info[:class].new(**context)
    end
    
    # Execute a tool
    def execute_tool(name, args, context = {})
      tool = get_tool(name, context)
      return { success: false, error: "Unknown tool: #{name}" } unless tool
      
      tool.execute(args)
    end
    
    # Get tool metadata
    def get_metadata(name)
      @tools[name]&.dig(:metadata)
    end
    
    # Get tools by category
    def tools_by_category(category)
      @categories[category] || []
    end
    
    # Get all categories
    def categories
      @categories.keys
    end
    
    private
    
    def load_all_tools
      # Auto-discover and register all tool classes
      Dir[Rails.root.join('app/services/tools/*_tool.rb')].each do |file|
        require_dependency file
        
        # Get the class name from the filename
        class_name = File.basename(file, '.rb').camelize
        next if class_name == 'BaseTool'
        
        begin
          tool_class = "Tools::#{class_name}".constantize
          register(tool_class) if tool_class < Tools::BaseTool
        rescue => e
          Rails.logger.error "Failed to load tool #{class_name}: #{e.message}"
        end
      end
    end
  end
end
