class SerperApiService
  include HTTParty
  base_uri "https://google.serper.dev"

  def initialize
    @api_key = ENV["SERPER_API_KEY"]
    raise "Serper API key not configured" unless @api_key.present?
  end

  def search(query, num_results: 10, search_type: "search", time_filter: nil)
    Rails.logger.info "🔍 Serper API search: #{query} (time_filter: #{time_filter || 'none'})"

    body = {
      q: query,
      num: num_results
    }
    
    # Add time-based search filter if specified
    # Serper uses Google's tbs parameter format
    if time_filter.present?
      body[:tbs] = case time_filter.to_s
        when 'day'   then 'qdr:d'   # Past 24 hours
        when 'week'  then 'qdr:w'   # Past week
        when 'month' then 'qdr:m'   # Past month
        when 'year'  then 'qdr:y'   # Past year
        else nil
      end
    end

    response = self.class.post("/#{search_type}", {
      headers: {
        "X-API-KEY" => @api_key,
        "Content-Type" => "application/json"
      },
      body: body.compact.to_json
    })

    if response.success?
      parse_search_results(response.parsed_response)
    else
      Rails.logger.error "Serper API error: #{response.code} - #{response.message}"
      { success: false, error: "Search failed: #{response.message}", results: [] }
    end
  rescue => e
    Rails.logger.error "Serper API exception: #{e.message}"
    { success: false, error: e.message, results: [] }
  end

  def search_documentation(app_name, additional_terms: [])
    # Build a comprehensive search query for API documentation
    terms = [
      "#{app_name} API documentation",
      "#{app_name} REST API reference",
      "#{app_name} authentication guide",
      "#{app_name} API getting started",
      "#{app_name} developer docs"
    ] + additional_terms

    all_results = []

    # Search for each term to get comprehensive coverage
    terms.each do |term|
      result = search(term, num_results: 5)
      if result[:success]
        all_results.concat(result[:results])
      end
    end

    # Deduplicate by URL and prioritize official docs
    deduplicated = all_results.uniq { |r| r[:url] }
    prioritized = prioritize_documentation_sources(deduplicated, app_name)

    {
      success: true,
      app_name: app_name,
      results: prioritized.first(20), # Top 20 most relevant results
      total_found: deduplicated.length
    }
  end

  private

  def parse_search_results(response)
    results = []

    # Parse organic results
    if response["organic"].present?
      response["organic"].each do |result|
        results << {
          title: result["title"],
          url: result["link"],
          snippet: result["snippet"],
          source: extract_source(result["link"]),
          type: "web"
        }
      end
    end

    # Parse knowledge graph if available
    if response["knowledgeGraph"].present?
      kg = response["knowledgeGraph"]
      if kg["website"].present?
        results.unshift({
          title: "#{kg['title']} - Official Website",
          url: kg["website"],
          snippet: kg["description"],
          source: "Official",
          type: "official"
        })
      end
    end

    { success: true, results: results }
  end

  def extract_source(url)
    uri = URI.parse(url)
    domain = uri.host.gsub("www.", "")

    # Identify common documentation platforms
    case domain
    when /docs\./i, /developer\./i, /api\./i
      "Official Documentation"
    when /github\.com/i
      "GitHub"
    when /stackoverflow\.com/i
      "Stack Overflow"
    when /medium\.com/i
      "Medium"
    when /dev\.to/i
      "Dev.to"
    else
      domain.split(".").first.capitalize
    end
  rescue
    "Web"
  end

  def prioritize_documentation_sources(results, app_name)
    # Score each result based on relevance
    scored_results = results.map do |result|
      score = 0
      url = result[:url].downcase
      title = result[:title].downcase

      # Official documentation indicators
      score += 100 if url.include?("#{app_name.downcase}.com") || url.include?("#{app_name.downcase}.io")
      score += 50 if url.include?("docs.") || url.include?("developer.") || url.include?("api.")
      score += 30 if result[:source] == "Official Documentation" || result[:type] == "official"

      # Content relevance
      score += 20 if title.include?("api") && title.include?("documentation")
      score += 15 if title.include?("getting started") || title.include?("quickstart")
      score += 15 if title.include?("authentication") || title.include?("auth")
      score += 10 if title.include?("reference")
      score += 10 if url.include?("github.com") && url.include?("/wiki")

      # Recency (if we can detect it from the snippet)
      current_year = Date.current.year
      score += 5 if result[:snippet]&.include?(current_year.to_s)
      score += 3 if result[:snippet]&.include?((current_year - 1).to_s)

      result.merge(relevance_score: score)
    end

    # Sort by score descending
    scored_results.sort_by { |r| -r[:relevance_score] }
  end
end
