class CouncilResearchService
  # Depth configurations - which models to query
  DEPTH_CONFIGS = {
    quick: {
      models: [:openai, :anthropic],
      peer_review: false,
      description: "Fast research using 2 leading models"
    },
    standard: {
      models: [:openai, :anthropic, :google, :meta],
      peer_review: false,
      description: "Balanced research using 4 diverse models"
    },
    deep: {
      models: [:openai, :anthropic, :google, :meta, :xai, :deepseek],
      peer_review: true,
      description: "Comprehensive research with peer review"
    }
  }.freeze

  # Chairman model for final synthesis (uses Bedrock)
  # Qwen3-Next-80B provides excellent synthesis at much lower cost
  CHAIRMAN_MODEL = "qwen3-next-80b"

  # Cache TTL for research results
  CACHE_TTL = 1.hour

  attr_reader :entity, :user, :openrouter, :bedrock

  def initialize(entity, user: nil)
    @entity = entity
    @user = user
    # Pass user/entity to OpenrouterService for token billing
    @openrouter = OpenrouterService.new(user: user, entity: entity)
    @bedrock = BedrockService.new
  end

  # Main entry point: Execute a research query
  def execute(query:, depth: :standard, include_peer_review: nil, use_cache: true)
    depth_sym = depth.to_sym
    config = DEPTH_CONFIGS[depth_sym]
    raise ArgumentError, "Invalid depth: #{depth}. Available: #{DEPTH_CONFIGS.keys.join(', ')}" unless config

    # Override peer review if explicitly specified
    do_peer_review = include_peer_review.nil? ? config[:peer_review] : include_peer_review

    # Check cache first
    cache_key = research_cache_key(query, depth_sym, do_peer_review)
    if use_cache
      cached = Rails.cache.read(cache_key)
      if cached
        Rails.logger.info "🎯 Council Research cache hit for: #{query.truncate(50)}"
        return cached.merge(from_cache: true)
      end
    end

    Rails.logger.info "🔬 Starting Council Research (#{depth}) for: #{query.truncate(100)}"
    started_at = Time.current

    result = {
      query: query,
      depth: depth_sym,
      status: "in_progress",
      started_at: started_at,
      responses: {},
      peer_reviews: nil,
      synthesis: nil,
      metadata: {
        entity_id: entity.id,
        user_id: user&.id,
        models_queried: config[:models],
        peer_review_enabled: do_peer_review
      }
    }

    begin
      # Stage 1: Query all council models in parallel
      result[:responses] = stage1_individual_responses(query, config[:models])

      successful_responses = result[:responses].select { |_, r| r[:success] }
      if successful_responses.empty?
        result[:status] = "error"
        result[:error] = "All models failed to respond"
        return result
      end

      # Stage 2: Peer review (optional)
      if do_peer_review && successful_responses.size >= 2
        result[:peer_reviews] = stage2_peer_review(query, successful_responses)
      end

      # Stage 3: Synthesis by chairman
      result[:synthesis] = stage3_synthesis(query, successful_responses, result[:peer_reviews])

      result[:status] = "complete"
      result[:completed_at] = Time.current
      result[:duration_ms] = ((result[:completed_at] - started_at) * 1000).round

      # Calculate total cost
      result[:total_cost] = calculate_total_cost(result)

      # Cache successful results
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL) if use_cache

      Rails.logger.info "✅ Council Research complete in #{result[:duration_ms]}ms"
      result
    rescue => e
      Rails.logger.error "❌ Council Research failed: #{e.message}"
      result[:status] = "error"
      result[:error] = e.message
      result[:completed_at] = Time.current
      result
    end
  end

  # Stage 1: Query all models in parallel and collect responses
  def stage1_individual_responses(query, model_keys)
    system_prompt = build_research_prompt(query)

    Rails.logger.info "📊 Stage 1: Querying #{model_keys.size} models..."
    responses = openrouter.query_models(
      system_prompt,
      query,
      model_keys: model_keys,
      max_tokens: 4000,
      temperature: 0.7
    )

    # Log results
    responses.each do |model, response|
      status = response[:success] ? "✓" : "✗"
      Rails.logger.info "  #{status} #{response[:model_name]}: #{response[:duration_ms]}ms"
    end

    responses
  end

  # Stage 2: Each model reviews and ranks the other responses
  def stage2_peer_review(query, responses)
    Rails.logger.info "🔍 Stage 2: Peer review..."

    reviews = {}
    response_summaries = format_responses_for_review(responses)

    responses.each_key do |reviewer_model|
      other_responses = response_summaries.reject { |k, _| k == reviewer_model }
      next if other_responses.empty?

      review_prompt = build_peer_review_prompt(query, other_responses)

      result = openrouter.send_message(
        "You are a critical reviewer evaluating research responses.",
        review_prompt,
        model_key: reviewer_model,
        max_tokens: 1000,
        temperature: 0.3
      )

      if result[:success]
        reviews[reviewer_model] = {
          reviewer: result[:model_name],
          evaluation: result[:content],
          duration_ms: result[:duration_ms]
        }
      end
    end

    Rails.logger.info "  Collected #{reviews.size} peer reviews"
    reviews
  end

  # Stage 3: Chairman synthesizes all responses into final answer
  def stage3_synthesis(query, responses, peer_reviews)
    Rails.logger.info "📝 Stage 3: Chairman synthesis..."

    synthesis_prompt = build_synthesis_prompt(query, responses, peer_reviews)

    # Use Bedrock Claude for synthesis (our primary model)
    begin
      content = bedrock.send_message(
        synthesis_system_prompt,
        synthesis_prompt,
        max_tokens: 6000,
        temperature: 0.5
      )

      # Parse structured synthesis if possible
      parsed = parse_synthesis(content)

      {
        content: content,
        key_points: parsed[:key_points],
        consensus_areas: parsed[:consensus_areas],
        dissenting_views: parsed[:dissenting_views],
        confidence: parsed[:confidence],
        sources_cited: parsed[:sources_cited],
        chairman_model: CHAIRMAN_MODEL
      }
    rescue => e
      Rails.logger.error "Chairman synthesis failed: #{e.message}"
      {
        content: "Synthesis failed: #{e.message}",
        error: true
      }
    end
  end

  private

  def research_cache_key(query, depth, peer_review)
    normalized_query = query.downcase.strip.gsub(/\s+/, " ")
    hash = Digest::SHA256.hexdigest("#{normalized_query}:#{depth}:#{peer_review}")[0..15]
    "council_research:#{entity.id}:#{hash}"
  end

  def build_research_prompt(query)
    <<~PROMPT
      You are a research expert participating in a council of AI models. Your task is to provide a thorough, well-researched response to the user's query.

      Guidelines:
      1. Be comprehensive but focused - cover key aspects without unnecessary tangents
      2. Cite sources, studies, or data when available (use your training knowledge)
      3. Acknowledge uncertainty or limitations in your knowledge
      4. Provide practical insights and actionable information when relevant
      5. Structure your response clearly with key points

      Your response will be combined with responses from other AI models to create a comprehensive synthesis.
    PROMPT
  end

  def format_responses_for_review(responses)
    responses.transform_values do |r|
      {
        model_name: r[:model_name],
        provider: r[:provider],
        content: r[:content]&.truncate(2000) # Truncate for review context
      }
    end
  end

  def build_peer_review_prompt(query, other_responses)
    responses_text = other_responses.map do |model, data|
      "### #{data[:model_name]} (#{data[:provider]})\n#{data[:content]}"
    end.join("\n\n---\n\n")

    <<~PROMPT
      Original Query: #{query}

      Below are responses from other AI models. Please evaluate each response for:
      1. Accuracy and correctness
      2. Completeness of coverage
      3. Quality of reasoning
      4. Practical usefulness

      Rate each response on a scale of 1-10 and briefly explain your rating.

      Responses to review:

      #{responses_text}
    PROMPT
  end

  def synthesis_system_prompt
    <<~PROMPT
      You are the Chairman of an AI research council. Your role is to synthesize multiple AI model responses into a comprehensive, authoritative final answer.

      Your synthesis should:
      1. Identify areas of consensus across models
      2. Highlight valuable unique insights from individual models
      3. Note any significant disagreements or alternative perspectives
      4. Provide a clear, actionable final answer
      5. Assess overall confidence in the synthesized response

      Structure your response with clear sections:
      - **Executive Summary**: 2-3 sentence overview
      - **Key Findings**: Main points of consensus
      - **Detailed Analysis**: Comprehensive synthesis
      - **Alternative Perspectives**: Where models disagreed
      - **Confidence Assessment**: How reliable is this synthesis (Low/Medium/High)
      - **Recommendations**: Actionable next steps if applicable
    PROMPT
  end

  def build_synthesis_prompt(query, responses, peer_reviews)
    # Format all responses
    responses_text = responses.map do |model, data|
      <<~RESPONSE
        ### #{data[:model_name]} (#{data[:provider]})
        #{data[:content]}
      RESPONSE
    end.join("\n---\n\n")

    # Format peer reviews if available
    reviews_text = if peer_reviews.present?
      peer_reviews.map do |model, review|
        "**#{review[:reviewer]}'s evaluation:**\n#{review[:evaluation]}"
      end.join("\n\n")
    else
      "No peer reviews conducted."
    end

    <<~PROMPT
      ## Original Research Query
      #{query}

      ## Council Responses
      The following #{responses.size} AI models provided their analysis:

      #{responses_text}

      ## Peer Review Results
      #{reviews_text}

      ## Your Task
      Synthesize all the above into a comprehensive, authoritative response. Identify consensus, highlight unique insights, note disagreements, and provide a confidence-rated final answer.
    PROMPT
  end

  def parse_synthesis(content)
    # Try to extract structured elements from the synthesis
    {
      key_points: extract_key_points(content),
      consensus_areas: extract_section(content, "Key Findings", "Consensus"),
      dissenting_views: extract_section(content, "Alternative Perspectives", "Disagreements"),
      confidence: extract_confidence(content),
      sources_cited: extract_sources(content)
    }
  end

  def extract_key_points(content)
    # Look for bullet points or numbered lists in Key Findings section
    section = content[/Key Findings.*?(?=##|\z)/mi] || content[/Executive Summary.*?(?=##|\z)/mi]
    return [] unless section

    points = section.scan(/[-*•]\s*(.+)/).flatten
    points = section.scan(/\d+\.\s*(.+)/).flatten if points.empty?
    points.map(&:strip).first(5)
  end

  def extract_section(content, *headers)
    headers.each do |header|
      match = content[/#{header}.*?(?=##|\z)/mi]
      return match&.strip if match.present?
    end
    nil
  end

  def extract_confidence(content)
    case content.downcase
    when /confidence.*?high/i, /high.*?confidence/i
      0.85
    when /confidence.*?medium/i, /medium.*?confidence/i, /moderate.*?confidence/i
      0.65
    when /confidence.*?low/i, /low.*?confidence/i
      0.40
    else
      0.70 # Default moderate confidence
    end
  end

  def extract_sources(content)
    # Extract any URLs or study references
    urls = content.scan(/https?:\/\/[^\s\)]+/).uniq
    studies = content.scan(/(?:study|research|paper|report)\s+(?:by|from)\s+([^,.]+)/i).flatten.uniq
    (urls + studies).first(10)
  end

  def calculate_total_cost(result)
    total = 0.0

    # Sum costs from individual responses
    result[:responses].each_value do |response|
      total += response[:cost_estimate] if response[:cost_estimate]
    end

    # Add peer review costs
    if result[:peer_reviews]
      result[:peer_reviews].each_value do |review|
        # Estimate peer review cost (usually smaller responses)
        total += 0.005 # Rough estimate
      end
    end

    # Add synthesis cost (using Bedrock, not OpenRouter pricing)
    total += 0.02 # Rough estimate for Claude synthesis

    total.round(4)
  end
end
