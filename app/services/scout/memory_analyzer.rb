# Scout::MemoryAnalyzer
#
# Analyzes explicit "remember this" requests from users and determines
# the best place to store the information:
#
# - UserMemory: Preferences, communication style, personal facts
# - BusinessInsight: Business facts, metrics, decisions
# - ScoutLearning: Patterns, workflows, "how I like things done"
# - MemoryBookmark: Specific outputs to revisit
# - ImportantMemory: General important facts that don't fit elsewhere
#
module Scout
  class MemoryAnalyzer
    MEMORY_CATEGORIES = {
      user_preference: {
        patterns: [
          /i (prefer|like|want|always want|don't like|hate|never want)/i,
          /call me/i,
          /my (name|title|role) is/i,
          /i('m| am) (a|an|the)/i,
          /(always|never) (do|use|send|show|include)/i,
          /my (style|tone|preference)/i
        ],
        storage: :user_memory,
        memory_type: 'preference'
      },
      business_fact: {
        patterns: [
          /our (company|business|team|product|service)/i,
          /we (have|are|sell|offer|provide)/i,
          /(revenue|sales|customers|employees|clients)/i,
          /our (target|audience|market|industry)/i,
          /(pricing|cost|budget|goal|target)/i,
          /we('re| are) (based|located|headquartered)/i
        ],
        storage: :business_insight,
        memory_type: 'fact'
      },
      business_decision: {
        patterns: [
          /we('ve| have) decided/i,
          /our (decision|choice|plan) is/i,
          /going (forward|with)/i,
          /we('re| are) (going to|planning to)/i,
          /(approved|confirmed|finalized)/i
        ],
        storage: :business_insight,
        memory_type: 'decision'
      },
      workflow_pattern: {
        patterns: [
          /when (i|we) (ask|want|need)/i,
          /(always|usually|typically) (do|start|use)/i,
          /the (way|process|workflow)/i,
          /step (one|1|first)/i,
          /(before|after) (you|we|i)/i
        ],
        storage: :scout_learning,
        memory_type: 'task_pattern'
      },
      contact_info: {
        patterns: [
          /(email|phone|address|website|url)/i,
          /@[a-z0-9.-]+\.[a-z]{2,}/i,  # email pattern
          /\d{3}[-.]?\d{3}[-.]?\d{4}/,  # phone pattern
          /https?:\/\//i
        ],
        storage: :user_memory,
        memory_type: 'fact'
      },
      important_date: {
        patterns: [
          /(birthday|anniversary|deadline|launch|event)/i,
          /(january|february|march|april|may|june|july|august|september|october|november|december)/i,
          /\d{1,2}\/\d{1,2}/,
          /(next|this) (week|month|quarter|year)/i
        ],
        storage: :user_memory,
        memory_type: 'fact'
      },
      goal: {
        patterns: [
          /(goal|objective|target|aim)/i,
          /want to (achieve|reach|hit|get)/i,
          /trying to/i,
          /(increase|decrease|improve|grow|reduce)/i
        ],
        storage: :user_memory,
        memory_type: 'goal'
      }
    }.freeze

    attr_reader :user, :entity

    def initialize(user:, entity:)
      @user = user
      @entity = entity
    end

    # Analyze what the user wants remembered and store it appropriately
    def analyze_and_store(content:, context: nil, source: 'explicit')
      return { success: false, error: "Nothing to remember" } if content.blank?

      # Determine the best category
      category = determine_category(content)
      
      # Extract the core fact/preference to remember
      extracted = extract_memory_content(content, category)
      
      # Store in the appropriate place
      result = store_memory(
        category: category,
        content: extracted[:content],
        raw_content: content,
        context: context,
        source: source,
        confidence: extracted[:confidence]
      )

      {
        success: true,
        category: category,
        storage: MEMORY_CATEGORIES.dig(category, :storage) || :important_memory,
        content: extracted[:content],
        message: result[:message]
      }
    end

    private

    def determine_category(content)
      # Check each category's patterns
      MEMORY_CATEGORIES.each do |category, config|
        if config[:patterns].any? { |pattern| content.match?(pattern) }
          return category
        end
      end

      # Default to general important memory
      :important_memory
    end

    def extract_memory_content(content, category)
      # Use AI to extract the core memory if content is complex
      if content.length > 100 || content.include?("\n")
        extract_with_ai(content, category)
      else
        # Simple content - use as-is with light cleanup
        {
          content: clean_memory_content(content),
          confidence: 0.9
        }
      end
    end

    def clean_memory_content(content)
      # Remove common prefixes
      content = content.gsub(/^(remember( that)?|don't forget|note( that)?|keep in mind( that)?)[:\s]*/i, '')
      content = content.gsub(/^(please|always|make sure( to)?)[:\s]*/i, '')
      content.strip.gsub(/\s+/, ' ')
    end

    def extract_with_ai(content, category)
      ai_service = BedrockService.new(user: @user, entity: @entity)

      prompt = <<~PROMPT
        Extract the core fact or preference to remember from this user request.
        
        User said: "#{content}"
        
        Category detected: #{category}
        
        Return JSON:
        {
          "core_memory": "The essential fact/preference in 1-2 sentences",
          "confidence": 0.0-1.0
        }
        
        Focus on what should be remembered long-term. Be concise.
      PROMPT

      response = ai_service.send_message(
        "You extract memories from user requests. Return only JSON.",
        [{ role: "user", content: prompt }],
        model: "claude-haiku-4-5-20251001",
        max_tokens: 200
      )

      json_match = response.match(/\{[\s\S]*\}/m)
      if json_match
        data = JSON.parse(json_match[0])
        {
          content: data['core_memory'],
          confidence: data['confidence'] || 0.8
        }
      else
        {
          content: clean_memory_content(content),
          confidence: 0.7
        }
      end
    rescue => e
      Rails.logger.warn "Memory extraction failed: #{e.message}"
      {
        content: clean_memory_content(content),
        confidence: 0.6
      }
    end

    def store_memory(category:, content:, raw_content:, context:, source:, confidence:)
      config = MEMORY_CATEGORIES[category] || {}
      storage = config[:storage] || :important_memory
      memory_type = config[:memory_type] || 'fact'

      case storage
      when :user_memory
        store_user_memory(content, memory_type, source, confidence)
      when :business_insight
        store_business_insight(content, memory_type, source, confidence)
      when :scout_learning
        store_scout_learning(content, memory_type, source, confidence)
      else
        store_important_memory(content, raw_content, context, source, confidence)
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
        category: 'explicit',  # User explicitly asked to remember
        content: content,
        source: source,
        confidence: [confidence, 0.95].min  # Explicit requests are high confidence
      )

      { message: "✅ I'll remember: #{content.truncate(100)}", id: memory.id }
    end

    def store_business_insight(content, memory_type, source, confidence)
      # Check for existing insight
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

      { message: "✅ Noted about your business: #{content.truncate(100)}", id: insight.id }
    rescue => e
      # Fallback to UserMemory if BusinessInsight fails
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

      { message: "✅ I'll do it that way: #{content.truncate(100)}", id: learning.id }
    end

    def store_important_memory(content, raw_content, context, source, confidence)
      # Store as high-priority UserMemory with special category
      memory = UserMemory.create!(
        user: @user,
        entity: @entity,
        memory_type: 'fact',
        category: 'important',  # Special category for explicit "remember this"
        key: "important_#{Time.current.to_i}",
        content: content,
        source: source,
        confidence: 0.95  # Explicit requests are always high confidence
      )

      { message: "✅ I'll remember: #{content.truncate(100)}", id: memory.id }
    end
  end
end
