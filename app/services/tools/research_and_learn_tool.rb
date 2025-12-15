# frozen_string_literal: true

module Tools
  class ResearchAndLearnTool < BaseTool
    def self.metadata
      {
        name: 'research_and_learn',
        description: <<~DESC.strip,
          Research a topic on the web and optionally save useful findings to your knowledge base.
          This is perfect for building up your domain expertise over time.
          
          Use this when you need to:
          - Look up documentation for an API or integration
          - Research best practices for a task
          - Find current information about a topic
          - Learn something new to help with the user's request
          
          The tool will search the web and return results. You can then decide which
          findings are valuable enough to save to your knowledge base for future use.
        DESC
        category: 'knowledge',
        input_schema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'The search query (be specific for better results)'
            },
            save_to_knowledge: {
              type: 'boolean',
              description: 'Whether to automatically save the best result to your knowledge base (default: false)'
            },
            knowledge_title: {
              type: 'string',
              description: 'If saving, the title for the knowledge entry'
            },
            num_results: {
              type: 'integer',
              description: 'Number of search results to return (default: 5, max: 10)'
            }
          },
          required: %w[query]
        }
      }
    end

    def execute(args)
      log_execution(args)

      query = get_arg(args, :query)
      save_to_knowledge = get_arg(args, :save_to_knowledge, false)
      knowledge_title = get_arg(args, :knowledge_title)
      num_results = [get_arg(args, :num_results, 5).to_i, 10].min

      if query.blank?
        return error_response('Query is required')
      end

      # Perform web search
      search_results = perform_web_search(query, num_results)

      if search_results[:error]
        return error_response(search_results[:error])
      end

      results = search_results[:results] || []

      # Optionally save the best result to knowledge base
      saved_doc = nil
      if save_to_knowledge && results.any?
        agent = @context[:agent_plugin]
        if agent
          best_result = results.first
          title = knowledge_title || "Research: #{query.truncate(50)}"
          
          # Compile the content from search results
          content = compile_search_content(query, results)
          
          saved_doc = agent.add_to_knowledge(
            title: title,
            content: content,
            source: best_result[:url],
            metadata: {
              query: query,
              search_results_count: results.size,
              tags: extract_tags(query)
            }
          )
        end
      end

      response = {
        query: query,
        results_count: results.size,
        results: results.map do |r|
          {
            title: r[:title],
            snippet: r[:snippet],
            url: r[:url]
          }
        end
      }

      if saved_doc
        response[:saved_to_knowledge] = true
        response[:knowledge_document_id] = saved_doc.id
        response[:message] = "Found #{results.size} results and saved key findings to your knowledge base."
      else
        response[:saved_to_knowledge] = false
        response[:message] = "Found #{results.size} results. Use save_to_knowledge_base tool to save valuable findings."
      end

      success_response(response)
    rescue => e
      Rails.logger.error "[ResearchAndLearnTool] Error: #{e.message}"
      error_response("Research failed: #{e.message}")
    end

    private

    def perform_web_search(query, num_results)
      # Use the existing web search tool
      web_search_tool = Tools::WebSearchTool.new(context: @context)
      
      result = web_search_tool.execute({
        'query' => query,
        'num_results' => num_results
      })

      if result[:success]
        { results: result[:results] || result[:data] || [] }
      else
        { error: result[:error] || 'Search failed' }
      end
    rescue => e
      Rails.logger.error "[ResearchAndLearnTool] Web search failed: #{e.message}"
      { error: "Search failed: #{e.message}" }
    end

    def compile_search_content(query, results)
      parts = []
      parts << "# Research: #{query}"
      parts << ""
      parts << "Compiled from web search on #{Time.current.strftime('%Y-%m-%d')}"
      parts << ""

      results.each_with_index do |result, i|
        parts << "## #{i + 1}. #{result[:title]}"
        parts << ""
        parts << result[:snippet] if result[:snippet].present?
        parts << ""
        parts << "Source: #{result[:url]}"
        parts << ""
      end

      parts.join("\n")
    end

    def extract_tags(query)
      # Extract meaningful tags from the query
      words = query.downcase.split(/\W+/)
      
      # Filter out common words
      stopwords = %w[the a an is are was were be been being have has had do does did will would could should may might must shall can this that these those what which who whom whose where when why how]
      
      words.reject { |w| stopwords.include?(w) || w.length < 3 }
           .first(5)
    end
  end
end
