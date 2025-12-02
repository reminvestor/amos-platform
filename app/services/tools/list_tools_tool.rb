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

      # Use RAG to find relevant tools if a search term is provided
      if search_term.present?
        # Find relevant tool definitions via vector search
        rag_tools = ToolDefinition.search_by_similarity(search_term, limit: 10)
        rag_tool_names = rag_tools.map(&:name)
      else
        rag_tool_names = []
      end

      tools = Tools::ToolCatalog.instance.tools.map do |name, tool_data|
        metadata = tool_data[:metadata] || {}
        {
          name: name,
          description: metadata[:description],
          category: metadata[:category],
          type: tool_data[:type], # :class or :definition
          input_schema: metadata[:input_schema] || metadata[:parameters],
          relevance: rag_tool_names.include?(name) ? 1 : 0 # Boost score for RAG matches
        }
      end

      # Filter by category
      if category_filter.present?
        tools.select! { |t| t[:category] == category_filter }
      end

      # Filter by search term (hybrid: RAG + keyword)
      if search_term.present?
        tools.select! do |t|
          t[:relevance] > 0 || # Keep RAG matches
          t[:name].downcase.include?(search_term) || 
          t[:description]&.downcase&.include?(search_term)
        end
        
        # Sort by relevance (RAG matches first)
        tools.sort_by! { |t| -t[:relevance] }
      end

      success_response(
        tools: tools,
        count: tools.count
      )
    end
  end
end

