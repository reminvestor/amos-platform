module Tools
  class ToolCatalog
    include Singleton

    attr_reader :tools

    def initialize
      @tools = {}
      @categories = {}
      load_all_tools
      load_dynamic_tools
    end

    # Register a tool class
    def register(tool_class)
      metadata = tool_class.metadata
      name = metadata[:name]
      category = metadata[:category] || "general"

      @tools[name] = {
        type: :class,
        class: tool_class,
        metadata: metadata,
        read_only: tool_class.read_only?
      }

      @categories[category] ||= []
      @categories[category] << name

      Rails.logger.info "📚 Registered tool: #{name} in category: #{category}"
    end

    # Register a dynamic tool definition
    def register_definition(definition)
      name = definition.name
      # Dynamic tools are considered "custom" category for now
      category = "custom" 
      
      @tools[name] = {
        type: :definition,
        definition: definition,
        metadata: {
          name: name,
          description: definition.description,
          parameters: definition.parameters,
          category: category
        },
        read_only: false # Assume dynamic tools perform actions
      }
      
      @categories[category] ||= []
      unless @categories[category].include?(name)
        @categories[category] << name
      end
      
      Rails.logger.info "📚 Registered dynamic tool: #{name}"
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
    # Now supports tiered discovery for scaling to thousands of tools
    def get_bedrock_tools(allowlist: nil, agent_loadout: nil, enable_caching: false, user: nil, entity: nil, prompt: nil)
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

      # Add ask_user tool (always available to agents)
      if allowlist.nil? || allowlist.include?('ask_user') || agent_loadout&.tool_allowlist&.include?('ask_user')
        if tool_info = @tools['ask_user']
          metadata = tool_info[:metadata]
          tools << {
            name: metadata[:name],
            description: metadata[:description],
            parameters: metadata[:input_schema] || metadata[:parameters]
          }
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # TOOL SELECTION ARCHITECTURE:
      # 1. ALWAYS start with base tools from allowlist (DB-driven)
      # 2. OPTIONALLY add discovered tools via RAG if enabled
      # This allows the system to evolve while maintaining a stable base
      # ═══════════════════════════════════════════════════════════════

      # Step 1: Get base tools from allowlist (always applied)
      tool_names = if agent_loadout&.tool_allowlist.present?
        agent_loadout.tool_allowlist
      elsif allowlist.present?
        allowlist
      else
        # No allowlist = wildcard access (for backwards compatibility)
        @tools.keys
      end

      # Convert base tools to Bedrock format
      tool_names.each do |tool_name|
        next if tool_name == "*" # Skip wildcard marker
        next if tool_name == "ask_user" # Already added
        next if tool_name == "load_canvas" # Already added

        if tool_info = @tools[tool_name]
          metadata = tool_info[:metadata]
          tools << {
            name: metadata[:name],
            description: metadata[:description],
            parameters: metadata[:input_schema] || metadata[:parameters]
          }
        end
      end

      base_tool_count = tools.length
      Rails.logger.info "📦 Base tools from allowlist: #{base_tool_count}"

      # Step 2: OPTIONALLY add discovered tools via tiered discovery
      # This is controlled by ScoutLoadoutConfiguration.use_tiered_discovery for Scout
      # or can be enabled per-agent for other agents
      if prompt.present? && user.present? && entity.present?
        # Check if tiered discovery is enabled (passed via agent_loadout or entity config)
        tiered_enabled = agent_loadout&.respond_to?(:enable_tiered_discovery) && agent_loadout.enable_tiered_discovery
        
        # For Scout (main_chat), check the ScoutLoadoutConfiguration
        if agent_loadout&.agent_role == "main_chat"
          scout_config = ScoutLoadoutConfiguration.find_by(entity: entity)
          tiered_enabled = scout_config&.use_tiered_discovery || false
        end

        if tiered_enabled
          discovered_tools = get_tiered_tools(user: user, entity: entity, prompt: prompt, agent_loadout: agent_loadout)
          # Only add tools not already in the base set
          existing_names = tools.map { |t| t[:name] }
          new_tools = discovered_tools.reject { |t| existing_names.include?(t[:name]) }
          tools += new_tools
          Rails.logger.info "🔍 Tiered discovery: +#{new_tools.length} additional tools discovered (#{discovered_tools.length} total matched)"
        else
          Rails.logger.info "⚡ Tiered discovery disabled - using base tools only"
        end
      end

      # Deduplicate by name
      tools = tools.uniq { |t| t[:name] }

      # Add cache_control to the LAST tool (caches all tools + system prompt)
      if enable_caching && tools.any?
        tools.last[:cache_control] = { type: "ephemeral" }
        Rails.logger.info "💾 Prompt caching enabled for #{tools.length} tools (cache_control on last tool)"
      end

      Rails.logger.info "🤖 Providing #{tools.length} tools to Bedrock (filtered from #{@tools.length} total)"
      tools
    end

    # Get tools using tiered discovery (RAG-based)
    def get_tiered_tools(user:, entity:, prompt:, agent_loadout: nil)
      discovery = TieredDiscoveryService.new(user: user, entity: entity, prompt: prompt)
      discovered = discovery.discover_tools(include_core: true)

      # If agent has a specific loadout, filter discovered tools
      if agent_loadout&.tool_allowlist.present? && !agent_loadout.tool_allowlist.include?("*")
        allowed = agent_loadout.tool_allowlist
        discovered = discovered.select { |t| allowed.include?(t[:name]) }
      end

      # Convert to Bedrock format
      discovered.map do |tool|
        {
          name: tool[:name],
          description: tool[:description],
          parameters: tool[:parameters]
        }.compact
      end
    end

    # Get tool instance
    def get_tool(name, user: nil, entity: nil, context: {}, progress_callback: nil)
      tool_info = @tools[name]
      return nil unless tool_info

      tool_info[:class].new(user: user, entity: entity, context: context, progress_callback: progress_callback)
    end

    # Execute a tool
    def execute_tool(name, args, user: nil, entity: nil, context: {}, progress_callback: nil)
      tool_info = @tools[name]
      return { success: false, error: "Unknown tool: #{name}" } unless tool_info

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = nil
      success = false

      begin
        if tool_info[:type] == :definition
          # Dynamic tool execution
          definition = tool_info[:definition]
          # Pass rich context to the dynamic tool
          execution_context = context.merge({
            user: user,
            entity: entity,
            progress_callback: progress_callback
          })
          result = definition.execute(args, execution_context)
        else
          # Class-based tool execution
          tool = get_tool(name, user: user, entity: entity, context: context, progress_callback: progress_callback)
          return { success: false, error: "Could not instantiate tool: #{name}" } unless tool
          result = tool.execute(args)
        end

        success = result.is_a?(Hash) ? result[:success] != false : true
        result
      rescue => e
        # Don't swallow execution suspension signals
        if e.class.name.include?('ExecutionSuspended') || e.is_a?(Tools::AskUserTool::ExecutionSuspended)
          raise e
        end

        Rails.logger.error "Tool execution failed (#{name}): #{e.message}"
        result = { success: false, error: e.message, backtrace: e.backtrace.first(5) }
        success = false
        result
      ensure
        # Record usage metrics (async to avoid slowing down execution)
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        latency_ms = ((end_time - start_time) * 1000).round

        record_tool_usage(
          name: name,
          user: user,
          entity: entity,
          tool_info: tool_info,
          success: success,
          latency_ms: latency_ms,
          context: context
        )
      end
    end

    def record_tool_usage(name:, user:, entity:, tool_info:, success:, latency_ms:, context:)
      return unless defined?(ToolUsageMetric)

      ToolUsageMetric.record(
        tool_name: name,
        user: user,
        entity: entity,
        tool_definition: tool_info[:type] == :definition ? tool_info[:definition] : nil,
        tool_type: tool_info[:type].to_s,
        success: success,
        latency_ms: latency_ms,
        context: context[:execution_context] || "unknown",
        agent_slug: context[:agent_slug],
        metadata: {
          category: tool_info.dig(:metadata, :category)
        }
      )
    rescue => e
      # Don't let metrics recording break tool execution
      Rails.logger.debug "Tool usage metric recording failed: #{e.message}"
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
      
      # Ensure parameters schema is valid for Bedrock
      params = metadata[:input_schema] || metadata[:parameters]
      
      {
        name: metadata[:name],
        description: metadata[:description],
        parameters: params
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

    def refresh_dynamic_tools!
      Rails.logger.info "🔄 Refreshing dynamic tools..."
      
      # Clear existing dynamic tools from memory
      @tools.delete_if { |_, info| info[:type] == :definition }
      
      # Remove dynamic tools from categories
      @categories.each do |cat, tools|
        tools.delete_if { |name| @tools[name].nil? }
      end
      
      # Reload
      load_dynamic_tools
    end

    private

    def load_dynamic_tools
      return unless ActiveRecord::Base.connection.table_exists?('tool_definitions')
      
      ToolDefinition.find_each do |tool_def|
        register_definition(tool_def)
      end
    rescue => e
      Rails.logger.warn "Failed to load dynamic tools: #{e.message}"
    end

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
