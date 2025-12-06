module Tools
  class WebSearchTool < BaseTool
    def self.read_only?
      true  # This tool only searches for information
    end

    def self.metadata
      {
        name: "web_search",
        description: "Search the web for information, documentation, or current data. For news/current events, include the year (e.g., '2025') in your query for accurate results.",
        category: "research",
        input_schema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The search query. For current events or news, ALWAYS include the current year (#{Date.current.year}) in the query."
            },
            num_results: {
              type: "integer",
              description: "Number of search results to return (default: 5, max: 10)"
            },
            time_filter: {
              type: "string",
              description: "Filter results by time: 'day' (past 24h), 'week' (past 7 days), 'month' (past 30 days), 'year' (past year). Use for current events.",
              enum: ["day", "week", "month", "year"]
            }
          },
          required: [ "query" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      query = get_arg(args, :query)
      num_results = get_arg(args, :num_results, 5)
      time_filter = get_arg(args, :time_filter)
      
      # Cap results to prevent context window explosion
      num_results = [num_results.to_i, 5].min

      # Validate required args
      if error = validate_required_args(args, [ :query ])
        return error
      end

      # Auto-enhance time-sensitive queries
      enhanced_query = enhance_query_for_recency(query)

      begin
        # Use real Serper API if available, otherwise fall back to mock
        if ENV["SERPER_API_KEY"].present?
          serper = SerperApiService.new
          result = serper.search(enhanced_query, num_results: num_results, time_filter: time_filter)

          if result[:success]
            # Truncate snippets to save tokens
            truncated_results = result[:results].map do |r|
              r.merge(snippet: r[:snippet]&.truncate(300))
            end
            
            success_response(
              query: query,
              results: truncated_results,
              count: truncated_results.length,
              source: "serper"
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

    # Automatically enhance time-sensitive queries with the current year
    # This ensures searches for "latest news" or "recent updates" include 2025
    def enhance_query_for_recency(query)
      current_year = Date.current.year.to_s
      current_month = Date.current.strftime("%B")
      
      # Skip if query already has the current year
      return query if query.include?(current_year)
      
      # Detect time-sensitive keywords
      time_sensitive_patterns = [
        /\b(latest|recent|new|current|today|this week|this month|breaking)\b/i,
        /\b(news|updates|announcements|releases|developments)\b/i,
        /\b(what's happening|what happened|trending)\b/i
      ]
      
      is_time_sensitive = time_sensitive_patterns.any? { |pattern| query.match?(pattern) }
      
      if is_time_sensitive
        # Append current year and optionally month for very recent queries
        if query.match?(/\b(today|this week|breaking|trending)\b/i)
          "#{query} #{current_month} #{current_year}"
        else
          "#{query} #{current_year}"
        end
      else
        query
      end
    end

    def use_mock_results(query, num_results)
      results = query.match?(/API|documentation|auth/i) ?
        generate_api_doc_search_results(query) :
        generate_general_search_results(query)

      success_response(
        query: query,
        results: results.first(num_results),
        count: results.length,
        source: "mock"
      )
    end

    def generate_api_doc_search_results(query)
      app_name = query.match(/(\w+)\s+API/i)&.captures&.first || "Service"

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
