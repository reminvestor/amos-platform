# Scout::MemoryAnalyzer
#
# Analyzes explicit "remember this" requests from users and determines
# the best place to store the information.
#
# Phase 5C: Replaced fragile regex-based categorization with AI-powered
# classification. A single Haiku call categorizes AND extracts the core
# memory in one shot, then routes to the appropriate storage model:
#
# - UserMemory: Preferences, communication style, personal facts, goals, dates
# - BusinessInsight: Business facts, metrics, decisions
# - ScoutLearning: Patterns, workflows, "how I like things done"
#
module Scout
  class MemoryAnalyzer
    # Valid categories the AI can return
    VALID_CATEGORIES = %w[
      user_preference
      business_fact
      business_decision
      workflow_pattern
      goal
      important_memory
    ].freeze

    # Map categories to storage destinations
    CATEGORY_STORAGE = {
      "user_preference"   => { storage: :user_memory, memory_type: "preference" },
      "business_fact"     => { storage: :business_insight, memory_type: "fact" },
      "business_decision" => { storage: :business_insight, memory_type: "decision" },
      "workflow_pattern"  => { storage: :scout_learning, memory_type: "task_pattern" },
      "goal"              => { storage: :user_memory, memory_type: "goal" },
      "important_memory"  => { storage: :user_memory, memory_type: "fact" },
    }.freeze

    attr_reader :user, :entity

    def initialize(user:, entity:)
      @user = user
      @entity = entity
    end

    # Analyze what the user wants remembered and store it appropriately
    def analyze_and_store(content:, context: nil, source: 'explicit')
      return { success: false, error: "Nothing to remember" } if content.blank?

      # Use AI to categorize and extract in one call
      analysis = analyze_with_ai(content, context)

      category = analysis[:category]
      extracted_content = analysis[:core_memory]
      confidence = analysis[:confidence]

      # Store in the appropriate place
      config = CATEGORY_STORAGE[category] || CATEGORY_STORAGE["important_memory"]
      result = store_memory(
        storage: config[:storage],
        memory_type: config[:memory_type],
        content: extracted_content,
        raw_content: content,
        context: context,
        source: source,
        confidence: confidence
      )

      {
        success: true,
        category: category.to_sym,
        storage: config[:storage],
        content: extracted_content,
        message: result[:message]
      }
    end

    private

    # Single AI call to categorize AND extract the core memory
    def analyze_with_ai(content, context)
      ai_service = BedrockService.new(user: @user, entity: @entity)

      context_note = context.present? ? "\nAdditional context: #{context}" : ""

      prompt = <<~PROMPT
        Analyze this user request to remember something and classify it.

        User said: "#{content}"#{context_note}

        Return JSON with exactly these fields:
        {
          "category": "one of: user_preference, business_fact, business_decision, workflow_pattern, goal, important_memory",
          "core_memory": "The essential fact/preference in 1-2 concise sentences",
          "confidence": 0.8
        }

        Category guide:
        - user_preference: Personal preferences, communication style, name, role ("call me X", "I prefer brief responses")
        - business_fact: Company info, metrics, audience, industry ("we have 50 employees", "our target market is...")
        - business_decision: Decisions made ("we decided to use Stripe", "approved the Q4 budget")
        - workflow_pattern: How things should be done ("always start emails with...", "when I ask for a report, include...")
        - goal: Objectives and targets ("increase open rates to 30%", "launch by March")
        - important_memory: Anything that doesn't fit above

        Focus on what should be remembered long-term. Be concise.
      PROMPT

      response = ai_service.send_message(
        "You classify and extract memories. Return only JSON.",
        [{ role: "user", content: prompt }],
        model: "claude-haiku-4-5-20251001",
        max_tokens: 250
      )

      json_match = response.match(/\{[\s\S]*\}/m)
      if json_match
        data = JSON.parse(json_match[0])
        category = data['category'].to_s
        category = "important_memory" unless VALID_CATEGORIES.include?(category)

        {
          category: category,
          core_memory: data['core_memory'] || clean_memory_content(content),
          confidence: (data['confidence'] || 0.85).to_f.clamp(0.0, 1.0)
        }
      else
        fallback_analysis(content)
      end
    rescue => e
      Rails.logger.warn "[MemoryAnalyzer] AI analysis failed: #{e.message}"
      fallback_analysis(content)
    end

    # Fallback if AI call fails — simple cleanup, store as important_memory
    def fallback_analysis(content)
      {
        category: "important_memory",
        core_memory: clean_memory_content(content),
        confidence: 0.7
      }
    end

    def clean_memory_content(content)
      content = content.gsub(/^(remember( that)?|don't forget|note( that)?|keep in mind( that)?)[:\s]*/i, '')
      content = content.gsub(/^(please|always|make sure( to)?)[:\s]*/i, '')
      content.strip.gsub(/\s+/, ' ')
    end

    def store_memory(storage:, memory_type:, content:, raw_content:, context:, source:, confidence:)
      case storage
      when :user_memory
        store_user_memory(content, memory_type, source, confidence)
      when :business_insight
        store_business_insight(content, memory_type, source, confidence)
      when :scout_learning
        store_scout_learning(content, memory_type, source, confidence)
      else
        store_user_memory(content, 'fact', source, confidence)
      end
    end

    def store_user_memory(content, memory_type, source, confidence)
      # Check for duplicates
      existing = UserMemory.where(user: @user, entity: @entity)
                          .where("content ILIKE ?", "%#{content.first(50)}%")
                          .first

      if existing
        existing.update!(confidence: [existing.confidence, confidence].max)
        return { message: "Updated existing memory", id: existing.id }
      end

      memory = UserMemory.create!(
        user: @user,
        entity: @entity,
        memory_type: memory_type,
        category: 'explicit',
        content: content,
        source: source,
        confidence: [confidence, 0.95].min
      )

      { message: "I'll remember: #{content.truncate(100)}", id: memory.id }
    end

    def store_business_insight(content, memory_type, source, confidence)
      existing = BusinessInsight.where(entity: @entity)
                               .where("content ILIKE ?", "%#{content.first(50)}%")
                               .first

      if existing
        existing.update!(confidence_score: [existing.confidence_score, confidence].max)
        return { message: "Updated business insight", id: existing.id }
      end

      insight = BusinessInsight.create!(
        entity: @entity,
        insight_type: memory_type,
        content: content,
        confidence_score: [confidence, 0.95].min,
        source: source
      )

      { message: "Noted about your business: #{content.truncate(100)}", id: insight.id }
    rescue => e
      Rails.logger.warn "BusinessInsight creation failed: #{e.message}, falling back to UserMemory"
      store_user_memory(content, 'fact', source, confidence)
    end

    def store_scout_learning(content, memory_type, source, confidence)
      learning = ScoutLearning.learn!(
        entity: @entity,
        learning_type: memory_type,
        learning: content,
        context: 'explicit_request',
        source: source,
        confidence: [confidence, 0.95].min
      )

      { message: "I'll do it that way: #{content.truncate(100)}", id: learning.id }
    end
  end
end
