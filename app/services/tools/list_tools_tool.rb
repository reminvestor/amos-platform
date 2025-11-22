module Tools
  class ListToolsTool < BaseTool
    def self.metadata
      {
        name: "list_tools",
        description: "List available tools in the system, including their descriptions and input schemas. Useful for finding the right tool for a job.",
        category: "system",
        input_schema: {
          type: "object",
          properties: {
            category: {
              type: "string",
              description: "Filter tools by category (e.g., 'system', 'data', 'communication')"
            },
            search: {
              type: "string",
              description: "Search term to filter tools by name or description"
            }
          }
        }
      }
    end

    def execute(args)
      category_filter = args["category"]
      search_term = args["search"]&.downcase

      tools = Tools::ToolCatalog.instance.tools.map do |name, tool_data|
        metadata = tool_data[:metadata] || {}
        {
          name: name,
          description: metadata[:description],
          category: metadata[:category],
          type: tool_data[:type], # :class or :definition
          input_schema: metadata[:input_schema] || metadata[:parameters]
        }
      end

      # Filter by category
      if category_filter.present?
        tools.select! { |t| t[:category] == category_filter }
      end

      # Filter by search term
      if search_term.present?
        tools.select! do |t|
          t[:name].downcase.include?(search_term) || 
          t[:description]&.downcase&.include?(search_term)
        end
      end

      success_response(
        tools: tools,
        count: tools.count
      )
    end
  end
end

