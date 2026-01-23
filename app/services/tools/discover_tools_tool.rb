# frozen_string_literal: true

module Tools
  # DiscoverToolsTool
  # Allows Amos to dynamically search for tools when he doesn't have the right one available.
  # This is a fallback mechanism - if the preprocessor didn't discover the right tool,
  # Amos can self-heal by searching for it.
  #
  # Usage by AI:
  #   When you need a capability that isn't in your current tool list, use this to find it.
  #   Examples: "I need to generate an image", "I need to send an email", "I need to analyze data"
  #
  class DiscoverToolsTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: "discover_tools",
        description: "Search for tools by description when you need a capability that isn't in your current tool list. " \
                     "Use this as a FALLBACK when you think a tool should exist but you don't see it. " \
                     "Returns matching tools that you can then use. " \
                     "Example queries: 'generate image', 'send email', 'analyze spreadsheet', 'create workflow'",
        category: "system",
        input_schema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Description of the capability you need. Be specific about what you want to do."
            },
            category: {
              type: "string",
              description: "Optional: Filter by tool category",
              enum: %w[data integration memory canvas agent research creation system]
            }
          },
          required: ["query"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      query = get_arg(args, :query)
      category = get_arg(args, :category)

      return error_response("Please describe what capability you need") if query.blank?

      begin
        # Use TieredDiscoveryService for semantic search
        discovery = TieredDiscoveryService.new(
          user: @user,
          entity: @entity,
          prompt: query
        )

        # Discover tools matching the query
        discovered = discovery.discover_tools(prompt: query, include_core: false)

        # Filter by category if specified
        if category.present?
          discovered = discovered.select { |t| t[:category]&.to_s == category }
        end

        # Limit results
        discovered = discovered.first(8)

        if discovered.empty?
          return success_response(
            found: false,
            message: "No matching tools found for '#{query}'. Try a different description or the task may need to be delegated to a specialist agent.",
            suggestion: "Consider using delegate_to_agent to hand this off to a specialist."
          )
        end

        # Format tools for Amos to understand
        tools_info = discovered.map do |tool|
          {
            name: tool[:name],
            description: tool[:description]&.truncate(200),
            category: tool[:category],
            how_to_use: "Call this tool with the appropriate parameters"
          }
        end

        # Notify that new tools are available
        # The actual tool injection happens on the next turn
        notify_tool_discovery(discovered.map { |t| t[:name] })

        success_response(
          found: true,
          tools: tools_info,
          count: tools_info.length,
          message: "Found #{tools_info.length} tools matching '#{query}'. You can now use these tools.",
          instruction: "These tools are now available for your next action. Choose the most appropriate one and call it."
        )
      rescue => e
        Rails.logger.error "[DiscoverToolsTool] Error: #{e.message}"
        error_response("Failed to search for tools: #{e.message}")
      end
    end

    private

    def notify_tool_discovery(tool_names)
      # Store discovered tools in session context for next turn
      # This allows the next LLM call to include these tools
      session_id = @context&.dig(:session_id) || @context&.dig("session_id")
      return unless session_id.present?

      cache_key = "discovered_tools:#{session_id}"
      existing = Rails.cache.read(cache_key) || []
      new_tools = (existing + tool_names).uniq.last(15) # Keep last 15 discovered

      Rails.cache.write(cache_key, new_tools, expires_in: 30.minutes)
      Rails.logger.info "[DiscoverToolsTool] Cached #{tool_names.length} tools for session #{session_id}"
    end
  end
end
