# frozen_string_literal: true

module V3
  # ToolRegistry - Registry of V3 tools
  #
  # Single-model architecture (Pi-inspired). One model, direct tool access.
  # No respond_to_user — the model outputs text naturally when it wants to talk.
  # No tool_choice: any — the model decides when to use tools vs when to respond.
  # No Brain delegation — the model calls platform tools directly.
  #
  # LLM-facing tools (Amos's full toolkit):
  #   platform_create  — create any platform object
  #   platform_update  — update any platform object
  #   platform_query   — read any platform data
  #   platform_execute — run actions (integrations, send email, delete, generate, publish)
  #   web_search       — search the internet for info (text results)
  #   view_web_page    — open a website in the interactive viewer
  #   read_file        — read uploaded documents and knowledge base content
  #   bash             — math, computation, escape hatch
  #   browser_use      — autonomous web browsing
  #   load_canvas      — show things to the user
  #
  class ToolRegistry
    extend V3::ToolSecurity

    # Tools exposed to the LLM — the model's full toolkit
    LLM_TOOLS = {
      "platform_create"  => V3::Tools::PlatformCreateTool,
      "platform_update"  => V3::Tools::PlatformUpdateTool,
      "platform_query"   => V3::Tools::PlatformQueryTool,
      "platform_execute" => V3::Tools::PlatformExecuteTool,
      "web_search"       => ::Tools::WebSearchTool,
      "view_web_page"    => ::Tools::WebPageViewTool,
      "read_file"        => V3::Tools::ReadFileTool,
      "bash"             => V3::Tools::BashTool,
      "browser_use"      => V3::Tools::BrowserUseTool,
      "load_canvas"      => nil, # Special: built inline in get_bedrock_tools
    }.freeze

    # Internal tools: NOT exposed to LLM, available for backward compatibility
    INTERNAL_TOOLS = {
      "platform_do"      => V3::Tools::PlatformDoTool,  # Kept for backward compat
      "discover"         => V3::Tools::DiscoverTool,
    }.freeze

    # All tools (for execution -- LLM might still reference old names during transition)
    ALL_TOOLS = LLM_TOOLS.merge(INTERNAL_TOOLS).freeze

    # Legacy alias for backward compatibility
    POWER_TOOLS = ALL_TOOLS

    class << self
      # Get tools in Bedrock format for LLM consumption (only LLM_TOOLS)
      def get_bedrock_tools(entity: nil)
        tools = []

        # 1. Add load_canvas (special: needs dynamic enum)
        tools << build_canvas_tool(entity)

        # 2. Add LLM-facing tools
        LLM_TOOLS.each do |name, tool_class|
          next if name == "load_canvas" # Already added
          next unless tool_class # Skip nil entries

          metadata = tool_class.metadata
          tools << {
            name: metadata[:name],
            description: metadata[:description],
            parameters: metadata[:input_schema] || metadata[:parameters]
          }
        end

        # 3. Add memory tools (reuse existing)
        memory_tools = build_memory_tools
        tools.concat(memory_tools)

        tools
      end

      # Execute a V3 tool by name
      # Supports BOTH LLM tools and internal tools (for backward compat & recipes)
      #
      # Phase 6B: All tool execution now goes through the shared ToolSecurity layer
      # (confirmation gate + CAMEL sanitization), regardless of whether the call
      # comes from the AgentLoop directly or from the PlatformBrain.
      def execute(name, args, user:, entity:, context: {}, progress_callback: nil)
        tool_class = ALL_TOOLS[name]

        # Check if it's a memory tool (no security needed -- internal data only)
        if tool_class.nil? && memory_tool?(name)
          return execute_memory_tool(name, args, user: user, entity: entity, context: context)
        end

        return { success: false, error: "Unknown V3 tool: #{name}" } unless tool_class

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          # Apply shared security: confirmation gate (pre) + CAMEL sanitization (post)
          result = with_security(name, args) do
            tool = tool_class.new(
              user: user,
              entity: entity,
              context: context,
              progress_callback: progress_callback
            )
            tool.execute(args)
          end

          # Record metrics
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          latency_ms = ((end_time - start_time) * 1000).round
          success = result.is_a?(Hash) ? result[:success] != false : true

          Rails.logger.info "[V3::ToolRegistry] #{name}: #{success ? '✅' : '❌'} (#{latency_ms}ms)"

          record_usage(name, user, entity, success, latency_ms, context)

          result
        rescue ::Tools::AskUserTool::ExecutionSuspended => e
          raise e # Let ask_user suspension propagate
        rescue => e
          Rails.logger.error "[V3::ToolRegistry] #{name} failed: #{e.message}"
          { success: false, error: e.message, backtrace: e.backtrace.first(5) }
        end
      end

      # List all available tool names (LLM-facing only)
      def tool_names
        names = LLM_TOOLS.keys.reject { |k| k == "load_canvas" }
        names += %w[load_canvas]
        names += memory_tool_names
        names
      end

      # List all tool names including internal ones
      def all_tool_names
        ALL_TOOLS.keys + memory_tool_names
      end

      # Check if a tool exists (checks both LLM and internal)
      def tool_exists?(name)
        ALL_TOOLS.key?(name) || memory_tool?(name)
      end

      private

      def build_canvas_tool(entity)
        # Build dynamic canvas enum (reuse V2 logic)
        canvas_enum = ::Tools::ToolCatalog.instance.build_canvas_enum(entity) rescue default_canvas_enum

        {
          name: "load_canvas",
          description: <<~DESC.strip,
            Show a visual canvas/view to the user.
            
            Key canvases:
            - 'landing_page_editor' — View/edit a landing page (pass landing_page_id in canvas_data)
            - 'automation_dashboard' — View all automations and their status
            - 'contact_viewer' — View and manage contacts list
            - 'pipeline_viewer' — Visual CRM pipeline
            - 'integrations_manager' — Manage connected external services
            - 'my_creations' — View all user's created assets
            - 'module_manager' — View installed apps/modules
            - 'dashboard' — Main dashboard
            - 'freeform_canvas' — Custom visualization: timelines, charts, interactive displays, data dashboards, or any rich HTML content.
              Pass canvas_data: { title: "Title", html: "<div>...</div>", css: "body { ... }", javascript: "// interactive code" }
              Optional: library_css (e.g. CDN links), library_scripts (e.g. Chart.js CDN), data_script (inline data).
              Use this instead of creating a landing page when the user wants a visualization, timeline, chart, or interactive display.
            
            Use load_canvas to VIEW things that already exist, or to display custom visualizations via 'freeform'.
          DESC
          parameters: {
            type: "object",
            properties: {
              canvas_name: {
                type: "string",
                description: "The canvas to show",
                enum: canvas_enum
              },
              canvas_data: {
                type: "object",
                description: "Data to pass (e.g., landing_page_id for editing, plan_id for viewing)",
                properties: {},
                additionalProperties: true
              }
            },
            required: ["canvas_name"]
          }
        }
      end

      def default_canvas_enum
        %w[
          dashboard campaign_viewer analytics_dashboard landing_page_editor
          contact_viewer integrations_manager custom_domains document_viewer
          work_inbox scheduled_tasks my_creations
          pipeline_viewer contact_detail support_tickets wallet
          module_manager favorites
          automation_dashboard sequence_manager
          activities_viewer settings
          freeform_canvas
        ]
      end

      def build_memory_tools
        return [] unless defined?(::Tools::MemoryTools)

        ::Tools::MemoryTools.definitions.map do |tool_def|
          {
            name: tool_def[:name],
            description: tool_def[:description],
            parameters: tool_def[:input_schema]
          }
        end
      rescue => e
        Rails.logger.warn "[V3::ToolRegistry] Could not load memory tools: #{e.message}"
        []
      end

      def memory_tool_names
        return [] unless defined?(::Tools::MemoryTools)
        ::Tools::MemoryTools.definitions.map { |d| d[:name] }
      rescue
        []
      end

      def memory_tool?(name)
        memory_tool_names.include?(name)
      end

      def execute_memory_tool(name, args, user:, entity:, context:)
        memory_tools = ::Tools::MemoryTools.new({
          user: user,
          entity: entity,
          session_id: context[:session_id]
        })
        memory_tools.execute(name, args)
      end

      def record_usage(name, user, entity, success, latency_ms, context)
        return unless defined?(ToolUsageMetric)

        ToolUsageMetric.record(
          tool_name: name,
          user: user,
          entity: entity,
          tool_type: "v3_power_tool",
          success: success,
          latency_ms: latency_ms,
          context: context[:execution_context] || "v3_agent_loop",
          metadata: { version: "v3" }
        )
      rescue => e
        Rails.logger.debug "[V3] Metric recording failed: #{e.message}"
      end
    end
  end
end
