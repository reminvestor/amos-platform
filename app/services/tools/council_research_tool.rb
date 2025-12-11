module Tools
  class CouncilResearchTool < BaseTool
    def self.read_only?
      true # Research doesn't modify entity data
    end

    # Tool is only available when OpenRouter API key is configured
    def self.available?
      (Rails.application.credentials.openrouter&.api_key || ENV["OPENROUTER_API_KEY"]).present?
    end

    def self.metadata
      {
        name: "council_research",
        description: "Perform deep research using an AI council of multiple LLM models. Queries GPT-4.1, Claude, Gemini, Llama, and others in parallel, then synthesizes a comprehensive answer. Use for research queries, comparative analysis, fact-finding, or when you need multiple perspectives on a topic. Before calling this tool, check if the query needs clarification - if it's too vague, ambiguous, or missing important context, ask the user to clarify first rather than wasting API calls.",
        category: "research",
        input_schema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The research question or topic to investigate. Should be specific and clear."
            },
            depth: {
              type: "string",
              enum: ["quick", "standard", "deep"],
              description: "Research depth: 'quick' (2 models, ~15s), 'standard' (4 models, ~30s), 'deep' (6 models + peer review, ~60s)"
            },
            include_peer_review: {
              type: "boolean",
              description: "Whether models should review and rank each other's responses (adds ~30s but improves quality). Only applies to 'deep' mode by default."
            },
            skip_clarification: {
              type: "boolean",
              description: "Set to true to skip query analysis and proceed immediately. Use when user has confirmed they want to proceed as-is."
            }
          },
          required: ["query"]
        }
      }
    end

    # Query patterns that typically need clarification
    VAGUE_PATTERNS = [
      /^(what|how|why|when|where|who)\s+(is|are|do|does|can|should|would)\s+\w+\s*\??$/i, # Very short questions
      /^(tell me about|explain|describe)\s+\w+\s*$/i, # Single word topics
      /\b(best|better|good|bad|top)\b/i, # Subjective without criteria
      /\b(should i|should we)\b/i, # Decision questions without context
    ].freeze

    # Minimum query length for meaningful research
    MIN_QUERY_LENGTH = 20

    # Maximum words before we assume it's detailed enough
    DETAILED_QUERY_WORDS = 15

    def execute(args)
      log_execution(args)

      query = get_arg(args, :query)
      depth = get_arg(args, :depth, "standard")
      include_peer_review = get_arg(args, :include_peer_review)
      skip_clarification = get_arg(args, :skip_clarification, false)

      # Validate required args
      if error = validate_required_args(args, [:query])
        return error
      end

      # Analyze query quality unless user wants to skip
      unless skip_clarification
        clarification = analyze_query_for_clarification(query)
        if clarification[:needs_clarification]
          return success_response(
            status: "needs_clarification",
            query: query,
            message: clarification[:message],
            suggested_questions: clarification[:questions],
            suggestion: clarification[:suggestion],
            proceed_hint: "If the user confirms they want to proceed anyway, call council_research again with skip_clarification: true"
          )
        end
      end

      # Validate depth
      valid_depths = %w[quick standard deep]
      unless valid_depths.include?(depth.to_s)
        return error_response("Invalid depth '#{depth}'. Must be one of: #{valid_depths.join(', ')}")
      end

      begin
        # Generate a unique research ID for tracking
        research_id = SecureRandom.uuid

        # Check OpenRouter availability
        unless openrouter_configured?
          return error_response(
            "Council Research requires OpenRouter API key. Please configure OPENROUTER_API_KEY.",
            setup_required: true
          )
        end

        # Get the session_id from context for ActionCable broadcasts
        session_id = context[:session_id] || "scout_#{user.id}"

        # Get model info for display
        config = CouncilResearchService::DEPTH_CONFIGS[depth.to_sym]
        models_info = get_models_display_info(config[:models])

        # Queue the background job for async processing
        CouncilResearchJob.perform_later(
          entity_id: entity.id,
          user_id: user.id,
          session_id: session_id,
          research_id: research_id,
          query: query,
          depth: depth,
          include_peer_review: include_peer_review
        )

        # Build a nice visual display of the models being queried
        models_display = build_models_display(models_info, depth, include_peer_review || config[:peer_review])

        # Stream progress update with model info
        stream_progress(models_display)

        # Return immediately with research ID - canvas will update via ActionCable
        success_response(
          research_id: research_id,
          query: query,
          depth: depth,
          status: "queued",
          message: models_display,
          models_queried: models_info,
          canvas_action: {
            name: "research_council",
            data: {
              research_id: research_id,
              query: query,
              depth: depth,
              status: "in_progress",
              started_at: Time.current.iso8601
            }
          }
        )
      rescue => e
        Rails.logger.error "Council research failed to start: #{e.message}"
        error_response("Failed to start research: #{e.message}")
      end
    end

    private

    def openrouter_configured?
      (Rails.application.credentials.openrouter&.api_key || ENV["OPENROUTER_API_KEY"]).present?
    end

    # Get display information for the models being queried
    def get_models_display_info(model_keys)
      model_keys.map do |key|
        model_config = OpenrouterService::MODELS[key]
        next unless model_config

        {
          key: key,
          name: model_config[:name],
          provider: model_config[:provider]
        }
      end.compact
    end

    # Build a formatted display string showing the models being queried
    def build_models_display(models_info, depth, peer_review)
      depth_label = case depth.to_s
      when "quick" then "Quick"
      when "standard" then "Standard"
      when "deep" then "Deep"
      else depth.to_s.titleize
      end

      lines = []
      lines << "🔬 **AI Council Research** (#{depth_label} Mode)"
      lines << ""
      lines << "Querying #{models_info.size} AI models in parallel:"
      lines << ""

      models_info.each do |model|
        provider_emoji = provider_emoji_for(model[:provider])
        lines << "#{provider_emoji} **#{model[:name]}** (#{model[:provider]})"
      end

      lines << ""
      if peer_review
        lines << "📝 Peer review enabled - models will evaluate each other's responses"
      end
      lines << "🎯 Results will be synthesized by the Council Chairman"

      lines.join("\n")
    end

    # Return an emoji for each provider for visual distinction
    def provider_emoji_for(provider)
      case provider.to_s.downcase
      when "openai" then "🟢"
      when "anthropic" then "🟠"
      when "google" then "🔵"
      when "meta" then "🟣"
      when "xai" then "⚫"
      when "deepseek" then "🔴"
      when "mistral" then "🟡"
      else "⚪"
      end
    end

    # Analyze query to determine if clarification would improve results
    # Returns { needs_clarification: bool, message: string, questions: array, suggestion: string }
    def analyze_query_for_clarification(query)
      query = query.to_s.strip
      word_count = query.split(/\s+/).size
      issues = []
      questions = []

      # Check 1: Query too short
      if query.length < MIN_QUERY_LENGTH
        issues << :too_short
        questions << "Could you provide more details about what specifically you'd like to know?"
      end

      # Check 2: Very few words (likely vague)
      if word_count < 5 && query.length < 50
        issues << :too_brief
        questions << "What aspect of this topic interests you most?"
      end

      # Check 3: Subjective questions without criteria
      if query =~ /\b(best|better|top|worst)\b/i && query !~ /\b(for|criteria|based on|according to|compared to)\b/i
        issues << :subjective_no_criteria
        questions << "What criteria are most important to you (e.g., cost, quality, ease of use)?"
      end

      # Check 4: Decision questions without context
      if query =~ /\bshould\s+(i|we)\b/i && word_count < 12
        issues << :decision_no_context
        questions << "What's your current situation or constraints I should consider?"
      end

      # Check 5: Comparison without specifying what to compare
      if query =~ /\b(compare|vs|versus|difference|between)\b/i && query.scan(/\b[A-Z][a-z]+\b/).size < 2
        issues << :comparison_unclear
        questions << "Which specific options would you like me to compare?"
      end

      # Check 6: Time-sensitive without timeframe
      if query =~ /\b(latest|recent|current|now|today|this year)\b/i && query !~ /\b(20\d\d|q[1-4]|january|february|march|april|may|june|july|august|september|october|november|december)\b/i
        issues << :time_sensitive
        # Don't require clarification for time-sensitive queries - just note it
      end

      # Check 7: Industry/domain specific without context
      if query =~ /\b(industry|market|sector|field)\b/i && query.scan(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b/).empty?
        issues << :no_domain_specified
        questions << "Which industry or market are you interested in?"
      end

      # Only ask for clarification if there are significant issues
      # Skip if query is detailed enough (15+ words usually means they've thought it through)
      return { needs_clarification: false } if word_count >= DETAILED_QUERY_WORDS

      # Only ask for clarification on genuinely problematic queries
      significant_issues = issues - [:time_sensitive] # Time-sensitive isn't blocking
      return { needs_clarification: false } if significant_issues.empty?

      # Limit to 1-2 questions max to avoid frustration
      questions = questions.uniq.first(2)

      # Build a helpful message
      message = build_clarification_message(significant_issues, questions)
      suggestion = "Providing more context will help the AI Council give you more relevant and useful results."

      {
        needs_clarification: true,
        issues: significant_issues,
        message: message,
        questions: questions,
        suggestion: suggestion
      }
    end

    def build_clarification_message(issues, questions)
      case issues.first
      when :too_short, :too_brief
        "Your research query is quite brief. A bit more detail would help the AI Council provide more targeted insights."
      when :subjective_no_criteria
        "This question involves subjective judgment. Understanding your priorities would help provide more relevant recommendations."
      when :decision_no_context
        "To give you the best advice, it would help to understand your specific situation."
      when :comparison_unclear
        "To do a thorough comparison, I'd like to confirm exactly what you'd like compared."
      when :no_domain_specified
        "This topic varies significantly by industry. Knowing your focus area would improve the research."
      else
        "A quick clarification would help ensure the research is focused on what you need."
      end
    end
  end
end
