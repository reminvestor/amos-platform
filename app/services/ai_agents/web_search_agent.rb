module AiAgents
  class WebSearchAgent < BaseAgent
    def execute
      log_execution_start
      Rails.logger.info("WebSearchAgent: Starting search for: #{context[:topic]}")

      # Extract topic and related terms from context
      topic = context[:topic]
      entity = context[:entity]
      business_profile = context[:business_profile]

      # Generate search queries based on the topic
      Rails.logger.info("WebSearchAgent: Generating search queries for topic: #{topic}")
      search_queries = generate_search_queries(topic, entity, business_profile)
      Rails.logger.info("WebSearchAgent: Generated #{search_queries.size} search queries: #{search_queries.join(', ')}")

      # For each query, perform web search and extract relevant information
      search_results = []
      search_queries.each_with_index do |query, index|
        Rails.logger.info("WebSearchAgent: Executing search query #{index+1}/#{search_queries.size}: '#{query}'")
        results = perform_web_search(query)
        Rails.logger.info("WebSearchAgent: Query '#{query}' returned #{results.size} results")
        search_results.concat(results)
      end

      # Store the search results in the vector database
      Rails.logger.info("WebSearchAgent: Storing #{search_results.size} search results in vector database")
      store_search_results(search_results)

      # Update context with search results summary
      update_context({
        web_search_completed: true,
        search_results_count: search_results.length,
        search_topics: search_queries
      })

      Rails.logger.info("WebSearchAgent: Completed search with #{search_results.length} results")
      log_execution_complete
      context
    end

    private

    def generate_search_queries(topic, entity, business_profile)
      Rails.logger.info("WebSearchAgent: Building prompt for query generation")
      # Use LLM to generate relevant search queries based on the topic
      prompt = <<~PROMPT
        I need to create a landing page about "#{topic}" for a business with the following profile:

        Business Name: #{business_profile&.name || entity&.name || 'Unknown'}
        Industry: #{business_profile&.industry || 'Unknown'}
        Description: #{business_profile&.description || 'Unknown'}

        To gather information for this landing page, I need to search for relevant information online.

        Please generate 3-5 specific search queries that would help me gather the most relevant information for creating this landing page.
        Each query should be targeted to find different aspects needed for the landing page (e.g. industry trends, best practices, competitive analysis, etc.).

        Format your response as a JSON array of strings, like:
        ["query 1", "query 2", "query 3"]
      PROMPT

      response = call_openai_api(prompt)

      # Parse the response to extract queries
      begin
        # Find JSON array in the response
        json_match = response.match(/\[.*\]/m)
        if json_match
          Rails.logger.info("WebSearchAgent: Successfully parsed JSON response for queries")
          queries = JSON.parse(json_match[0])
        else
          # Fallback if no JSON array found
          Rails.logger.warn("WebSearchAgent: No JSON array found in response, parsing as text")
          queries = response.split("\n").map(&:strip).reject(&:empty?).first(5)
        end
      rescue JSON::ParserError => e
        # Fallback if JSON parsing fails
        Rails.logger.error("WebSearchAgent: Error parsing search queries: #{e.message}")
        queries = [ "#{topic} best practices", "#{topic} landing page examples", "#{topic} industry trends" ]
        Rails.logger.info("WebSearchAgent: Using fallback queries: #{queries.join(', ')}")
      end

      # Add the original topic as a query
      unless queries.include?(topic)
        Rails.logger.info("WebSearchAgent: Adding original topic to queries")
        queries.unshift(topic)
      end

      # Return unique queries
      Rails.logger.info("WebSearchAgent: Final queries: #{queries.uniq.join(', ')}")
      queries.uniq
    end

    def perform_web_search(query)
      Rails.logger.info("WebSearchAgent: Simulating web search for query: '#{query}'")
      # Mock implementation - in a real application, this would call a search API like Google, Bing, etc.
      # For this implementation, we'll use LLM to simulate search results

      prompt = <<~PROMPT
        I'm simulating a web search for: "#{query}"

        Please provide 3 realistic search results that might appear for this query. For each result, include:
        1. A title
        2. A URL
        3. A snippet/summary of content

        Format your response as a JSON array with objects having keys: title, url, and snippet.

        Example format:
        [
          {
            "title": "Example Title 1",
            "url": "https://example.com/page1",
            "snippet": "This is a summary of the content for this result..."
          },
          ...
        ]
      PROMPT

      response = call_openai_api(prompt)

      begin
        # Find JSON array in the response
        json_match = response.match(/\[.*\]/m)
        unless json_match
          Rails.logger.warn("WebSearchAgent: No JSON array found in search results response")
          return []
        end

        results = JSON.parse(json_match[0])
        Rails.logger.info("WebSearchAgent: Parsed #{results.size} search results")

        # Add query and timestamp to each result
        results.each do |result|
          result["query"] = query
          result["timestamp"] = Time.current.to_s
        end

        results
      rescue JSON::ParserError => e
        Rails.logger.error("WebSearchAgent: Error parsing search results: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        []
      end
    end

    def store_search_results(results)
      Rails.logger.info("WebSearchAgent: Storing #{results.size} search results in vector store")
      added_count = 0

      results.each do |result|
        # Combine title and snippet for the vector store
        text = "#{result['title']}\n#{result['snippet']}"

        # Add to vector store with metadata
        vector_store.add(text, {
          title: result["title"],
          url: result["url"],
          query: result["query"],
          source: "web_search"
        })
        added_count += 1
      end

      Rails.logger.info("WebSearchAgent: Successfully added #{added_count} items to vector store")
    end
  end
end
