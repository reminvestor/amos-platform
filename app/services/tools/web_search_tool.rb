module Tools
  class WebSearchTool < BaseTool
    def self.metadata
      {
        name: 'web_search',
        description: 'Search the web for information, documentation, or current data',
        category: 'research',
        input_schema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'The search query to look up'
            },
            num_results: {
              type: 'integer',
              description: 'Number of search results to return (default: 5, max: 10)'
            }
          },
          required: ['query']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      query = get_arg(args, :query)
      num_results = get_arg(args, :num_results, 5)
      
      # Validate required args
      if error = validate_required_args(args, [:query])
        return error
      end
      
      begin
        # Use real Serper API if available, otherwise fall back to mock
        if ENV['SERPER_API_KEY'].present?
          serper = SerperApiService.new
          result = serper.search(query, num_results: num_results)
          
          if result[:success]
            success_response(
              query: query,
              results: result[:results],
              count: result[:results].length,
              source: 'serper'
            )
          else
            # Fall back to mock on error
            Rails.logger.warn "Serper API failed, using mock results: #{result[:error]}"
            use_mock_results(query, num_results)
          end
        else
          # Use mock results when Serper is not configured
          use_mock_results(query, num_results)
        end
      rescue => e
        Rails.logger.error "Web search failed: #{e.message}"
        error_response("Search failed: #{e.message}")
      end
    end
    
    private
    
    def use_mock_results(query, num_results)
      results = query.match?(/API|documentation|auth/i) ? 
        generate_api_doc_search_results(query) : 
        generate_general_search_results(query)
      
      success_response(
        query: query,
        results: results.first(num_results),
        count: results.length,
        source: 'mock'
      )
    end
    
    def generate_api_doc_search_results(query)
      app_name = query.match(/(\w+)\s+API/i)&.captures&.first || 'Service'
      
      [
        {
          title: "#{app_name} API Documentation - Getting Started",
          url: "https://docs.#{app_name.downcase}.com/api/getting-started",
          snippet: "Learn how to authenticate and make your first API call to #{app_name}.",
          source: "Official Documentation"
        },
        {
          title: "#{app_name} REST API Reference",
          url: "https://api.#{app_name.downcase}.com/reference",
          snippet: "Complete reference documentation for all #{app_name} API endpoints.",
          source: "API Reference"
        },
        {
          title: "#{app_name} Authentication Guide",
          url: "https://docs.#{app_name.downcase}.com/api/authentication",
          snippet: "Detailed guide on #{app_name} authentication methods.",
          source: "Security Documentation"
        }
      ]
    end
    
    def generate_general_search_results(query)
      [
        {
          title: "Search Result for: #{query}",
          url: "https://example.com/result1",
          snippet: "This is a relevant search result about #{query}.",
          source: "Web"
        },
        {
          title: "Understanding #{query} - Complete Guide",
          url: "https://example.com/guide",
          snippet: "A comprehensive guide covering all aspects of #{query}.",
          source: "Tutorial"
        }
      ]
    end
  end
end
