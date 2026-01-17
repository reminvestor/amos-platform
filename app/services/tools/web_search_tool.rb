module Tools
  class WebSearchTool < BaseTool
    def self.read_only?
      true  # This tool only searches for information
    end

    def self.metadata
      {
        name: "web_search",
        description: "Search the web for information. Use depth='deep' for comprehensive research across multiple sources (sports rosters, news, complex topics). Default is 'quick' for simple lookups.",
        category: "research",
        input_schema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The search query. For current events or news, ALWAYS include the current year (#{Date.current.year}) in the query."
            },
            depth: {
              type: "string",
              description: "Search depth: 'quick' (default, 5 results) or 'deep' (comprehensive research with 15+ results from multiple query variations, synthesized findings). Use 'deep' for sports data, news, complex research.",
              enum: ["quick", "deep"]
            },
            num_results: {
              type: "integer",
              description: "Number of search results (default: 5 for quick, 15 for deep, max: 20)"
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
      depth = get_arg(args, :depth, "quick")
      num_results = get_arg(args, :num_results)
      time_filter = get_arg(args, :time_filter)
      
      # Set defaults based on depth
      if depth == "deep"
        num_results ||= 15
        num_results = [num_results.to_i, 20].min
      else
        num_results ||= 5
        num_results = [num_results.to_i, 10].min
      end

      # Validate required args
      if error = validate_required_args(args, [ :query ])
        return error
      end

      begin
        if depth == "deep"
          execute_deep_search(query, num_results, time_filter)
        else
          execute_quick_search(query, num_results, time_filter)
        end
      rescue => e
        Rails.logger.error "Web search failed: #{e.message}"
        error_response("Search failed: #{e.message}")
      end
    end

    private

    def execute_quick_search(query, num_results, time_filter)
      enhanced_query = enhance_query_for_recency(query)

        if ENV["SERPER_API_KEY"].present?
          serper = SerperApiService.new
          result = serper.search(enhanced_query, num_results: num_results, time_filter: time_filter)

          if result[:success]
            truncated_results = result[:results].map do |r|
              r.merge(snippet: r[:snippet]&.truncate(300))
            end
            
            success_response(
              query: query,
            depth: "quick",
              results: truncated_results,
              count: truncated_results.length,
              source: "serper"
            )
          else
            Rails.logger.warn "Serper API failed, using mock results: #{result[:error]}"
            use_mock_results(query, num_results)
          end
        else
          use_mock_results(query, num_results)
      end
    end

    def execute_deep_search(query, num_results, time_filter)
      Rails.logger.info "[WebSearch] Deep search for: #{query}"
      
      unless ENV["SERPER_API_KEY"].present?
        return use_mock_results(query, num_results, deep: true)
      end

      serper = SerperApiService.new
      all_results = []
      queries_run = []
      
      # Generate query variations for comprehensive coverage
      query_variations = generate_query_variations(query)
      
      # Run multiple searches in parallel-ish fashion
      query_variations.each_with_index do |variation, idx|
        break if all_results.length >= num_results
        
        enhanced = enhance_query_for_recency(variation)
        queries_run << enhanced
        
        # Distribute results across queries
        per_query_limit = [(num_results / query_variations.length.to_f).ceil, 5].max
        
        result = serper.search(enhanced, num_results: per_query_limit, time_filter: time_filter)
        
        if result[:success]
          result[:results].each do |r|
            # Deduplicate by URL
            unless all_results.any? { |existing| existing[:url] == r[:url] }
              all_results << r.merge(
                snippet: r[:snippet]&.truncate(400),
                query_source: variation
              )
            end
          end
        end
        
        # Small delay to avoid rate limiting
        sleep(0.1) if idx < query_variations.length - 1
      end
      
      # Sort by relevance (prefer results that match more query terms)
      query_terms = query.downcase.split(/\s+/)
      all_results.sort_by! do |r|
        text = "#{r[:title]} #{r[:snippet]}".downcase
        -query_terms.count { |term| text.include?(term) }
      end
      
      # Take top results
      final_results = all_results.first(num_results)
      
      # Generate synthesis for deep search
      synthesis = synthesize_findings(query, final_results)
      
      success_response(
        query: query,
        depth: "deep",
        queries_run: queries_run,
        results: final_results,
        count: final_results.length,
        total_sources_checked: all_results.length,
        synthesis: synthesis,
        source: "serper_deep"
      )
    end

    def generate_query_variations(query)
      variations = [query]  # Always include original
      
      # Detect query type and add relevant variations
      query_lower = query.downcase
      
      # Sports queries
      if query_lower.match?(/\b(roster|lineup|starting|team|player|game|match|score|nfl|nba|mlb|nhl|49ers|cowboys|lakers|yankees)\b/i)
        team_match = query.match(/\b(49ers|cowboys|patriots|chiefs|eagles|packers|dolphins|bills|ravens|bengals|lions|vikings|saints|buccaneers|falcons|panthers|bears|commanders|giants|jets|browns|steelers|colts|titans|jaguars|texans|broncos|raiders|chargers|seahawks|cardinals|rams)\b/i)
        team = team_match ? team_match[0] : nil
        
        if team
          variations << "#{team} official roster #{Date.current.year}"
          variations << "#{team} starting lineup today"
          variations << "#{team} depth chart #{Date.current.year}"
        end
        
        if query_lower.include?("lineup") || query_lower.include?("starting")
          variations << "#{query} confirmed"
          variations << "#{query} official"
        end
      end
      
      # News/current events
      if query_lower.match?(/\b(news|latest|current|today|recent|update|breaking)\b/)
        variations << "#{query} #{Date.current.strftime('%B %Y')}"
        variations << "#{query} official announcement"
      end
      
      # People queries
      if query_lower.match?(/\b(who is|current role|ceo|president|founder|director)\b/)
        variations << "#{query} #{Date.current.year}"
        variations << "#{query} linkedin"
        variations << "#{query} official"
      end
      
      # General enhancement - add "official" for factual queries
      if query_lower.match?(/\b(roster|schedule|price|hours|address|phone|contact)\b/)
        variations << "#{query} official"
      end
      
      # Limit to 4 variations max to avoid too many API calls
      variations.uniq.first(4)
    end

    def synthesize_findings(query, results)
      return nil if results.empty?
      
      # Extract key information from results
      sources = results.map { |r| r[:source] || URI.parse(r[:url]).host rescue "unknown" }.uniq.first(5)
      
      # Look for common themes/facts across results
      all_text = results.map { |r| "#{r[:title]} #{r[:snippet]}" }.join(" ")
      
      {
        sources_analyzed: results.length,
        unique_domains: sources,
        recommendation: "Review the #{results.length} results above for comprehensive information. Top sources include: #{sources.first(3).join(', ')}."
      }
    end

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

    def use_mock_results(query, num_results, deep: false)
      results = query.match?(/API|documentation|auth/i) ?
        generate_api_doc_search_results(query) :
        generate_general_search_results(query)

      response = {
        query: query,
        depth: deep ? "deep" : "quick",
        results: results.first(num_results),
        count: results.length,
        source: "mock"
      }
      
      response[:synthesis] = synthesize_findings(query, results) if deep
      
      success_response(**response)
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
