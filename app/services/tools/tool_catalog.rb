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
      category = metadata[:category] || "general"

      @tools[name] = {
        class: tool_class,
        metadata: metadata,
        read_only: tool_class.read_only?
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
    def get_bedrock_tools(allowlist: nil, agent_loadout: nil, enable_caching: false)
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
              enum: [ "campaign_viewer", "analytics_dashboard", "landing_page_viewer",
                     "contact_viewer", "email_template_viewer", "email_campaign_viewer", 
                     "task_progress", "parallel_tasks", "dynamic_canvas", 
                     "integrations_manager", "landing_page_editor", "document_viewer",
                     "document_search_results" ]
            },
            canvas_data: {
              type: "object",
              description: "Optional data to pass to the canvas (e.g., campaign_id, landing_page_id)",
              properties: {},
              additionalProperties: true
            }
          },
          required: [ "canvas_name" ]
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
        next if tool_name == "*" # Skip wildcard

        if tool_info = @tools[tool_name]
          metadata = tool_info[:metadata]
          tools << {
            name: metadata[:name],
            description: metadata[:description],
            parameters: metadata[:input_schema] || metadata[:parameters]
          }
        end
      end

      # Add cache_control to the LAST tool (caches all tools + system prompt)
      if enable_caching && tools.any?
        tools.last[:cache_control] = { type: "ephemeral" }
        Rails.logger.info "💾 Prompt caching enabled for #{tools.length} tools (cache_control on last tool)"
      end

      Rails.logger.info "🤖 Providing #{tools.length} tools to Bedrock (filtered from #{@tools.length} total)"
      tools
    end

    # Get tool instance
    def get_tool(name, user: nil, entity: nil, context: {}, progress_callback: nil)
      tool_info = @tools[name]
      return nil unless tool_info

      tool_info[:class].new(user: user, entity: entity, context: context, progress_callback: progress_callback)
    end

    # Execute a tool
    def execute_tool(name, args, user: nil, entity: nil, context: {}, progress_callback: nil)
      tool = get_tool(name, user: user, entity: entity, context: context, progress_callback: progress_callback)
      return { success: false, error: "Unknown tool: #{name}" } unless tool

      tool.execute(args)
    end

    # Check if a tool exists
    def tool_exists?(name)
      @tools.key?(name.to_s) || @tools.key?(name.to_sym)
    end

    # Get tool definition in Bedrock format
    def get_tool_definition(name)
      tool_info = @tools[name]
      return nil unless tool_info

      metadata = tool_info[:metadata]
      {
        name: metadata[:name],
        description: metadata[:description],
        parameters: metadata[:input_schema] || metadata[:parameters]
      }
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

    # Get read-only tools (safe to use for planning/analysis)
    def read_only_tools
      @tools.select { |_, info| info[:read_only] }.map do |name, info|
        {
          name: name,
          description: info[:metadata][:description],
          category: info[:metadata][:category]
        }
      end
    end

    # Get runnable tools (modify state)
    def runnable_tools
      @tools.reject { |_, info| info[:read_only] }.map do |name, info|
        {
          name: name,
          description: info[:metadata][:description],
          category: info[:metadata][:category]
        }
      end
    end

    # Get tools available for a specific agent role
    def get_tools_for_role(role)
      case role
      when "planner"
        # Planner needs to know about ALL tools to create workflows
        # They don't execute them directly, but need to plan with them
        @tools.map do |name, info|
          {
            name: name,
            description: info[:metadata][:description]
          }
        end
      when "executor"
        # Executor can use most tools
        @tools.reject do |name, info|
          info[:metadata][:category] == "system"
        end.map do |name, info|
          {
            name: name,
            description: info[:metadata][:description]
          }
        end
      when "analyst"
        # Analyst uses data analysis tools
        @tools.select do |name, info|
          %w[analytics data].include?(info[:metadata][:category])
        end.map do |name, info|
          {
            name: name,
            description: info[:metadata][:description]
          }
        end
      else
        []
      end
    end

    private

    def load_all_tools
      # Auto-discover and register all tool classes
      Dir[Rails.root.join("app/services/tools/*_tool.rb")].each do |file|
        require_dependency file

        # Get the class name from the filename
        class_name = File.basename(file, ".rb").camelize
        next if class_name == "BaseTool"

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
