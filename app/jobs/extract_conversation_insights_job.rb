# ExtractConversationInsightsJob
#
# Runs after conversations to extract:
# - Business insights (via BusinessExtractor)
# - User memories/preferences (patterns, facts, goals)
# - Scout learnings (what worked, what didn't)
#
# Triggered:
# - After every N messages (batch processing)
# - When a session ends (user leaves)
# - Periodically for active sessions
#
class ExtractConversationInsightsJob < ApplicationJob
  queue_as :low_priority

  # Minimum messages needed to run extraction
  MIN_MESSAGES_FOR_EXTRACTION = 4

  def perform(session_id, user_id, entity_id, options = {})
    @user = User.find_by(id: user_id)
    @entity = Entity.find_by(id: entity_id)
    @session_id = session_id
    @options = options.with_indifferent_access

    return unless @user && @entity

    Rails.logger.info "🧠 ExtractConversationInsightsJob: Processing session #{session_id}"

    # Get recent messages for this session
    messages = ScoutMessage.where(session_id: session_id)
                          .order(created_at: :desc)
                          .limit(20)

    return if messages.count < MIN_MESSAGES_FOR_EXTRACTION

    # Format conversation for extraction
    conversation_text = format_conversation(messages)

    # Run extractions in parallel (they're independent)
    threads = []

    # 1. Extract business insights
    threads << Thread.new { extract_business_insights(conversation_text) }

    # 2. Extract user memories
    threads << Thread.new { extract_user_memories(conversation_text, messages) }

    # 3. Extract Scout learnings
    threads << Thread.new { extract_scout_learnings(messages) }

    # Wait for all extractions
    threads.each(&:join)

    Rails.logger.info "🧠 ExtractConversationInsightsJob: Completed for session #{session_id}"
  rescue => e
    Rails.logger.error "ExtractConversationInsightsJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  def format_conversation(messages)
    messages.reverse.map do |m|
      role = m.role == 'user' ? 'User' : 'Scout'
      "#{role}: #{m.content}"
    end.join("\n\n")
  end

  def extract_business_insights(conversation_text)
    return unless defined?(AmosAI::BusinessExtractor)

    begin
      extractor = AmosAI::BusinessExtractor.new(user: @user, entity: @entity)
      result = extractor.extract(conversation_context: conversation_text)

      # Store extracted insights
      if result[:insights].present?
        result[:insights].each do |insight|
          next if insight[:confidence].to_f < 0.5

          # Check for duplicates
          existing = BusinessInsight.where(entity: @entity, insight_type: insight[:type])
                                   .where("content ILIKE ?", "%#{insight[:content].first(50)}%")
                                   .exists?
          next if existing

          BusinessInsight.create!(
            entity: @entity,
            insight_type: insight[:type],
            content: insight[:content],
            confidence_score: insight[:confidence],
            source_conversation_id: find_conversation_id
          )

          Rails.logger.info "📊 Extracted insight: #{insight[:type]} - #{insight[:content].truncate(50)}"
        end
      end

      # Update business profile if needed
      if result[:business_profile_updates].present?
        update_business_profile(result[:business_profile_updates])
      end
    rescue => e
      Rails.logger.error "Business insight extraction failed: #{e.message}"
    end
  end

  def extract_user_memories(conversation_text, messages)
    return unless defined?(UserMemory)

    begin
      # Use AI to extract user preferences and facts
      ai_service = BedrockService.new(user: @user, entity: @entity)

      extraction_prompt = <<~PROMPT
        Analyze this conversation and extract user preferences, facts, and goals.
        Focus on information that would help personalize future interactions.

        CONVERSATION:
        #{conversation_text}

        Extract the following (JSON format):
        {
          "preferences": [
            {"content": "...", "confidence": 0.0-1.0}
          ],
          "facts": [
            {"content": "...", "category": "business|personal|product", "confidence": 0.0-1.0}
          ],
          "goals": [
            {"content": "...", "confidence": 0.0-1.0}
          ]
        }

        Only include high-confidence extractions. Return empty arrays if nothing notable.
        Focus on NEW information, not obvious things.
      PROMPT

      response = ai_service.send_message(
        "You are an analyst extracting user information from conversations. Return only valid JSON.",
        [{ role: "user", content: extraction_prompt }],
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1000
      )

      # Parse response
      json_match = response.match(/\{[\s\S]*\}/m)
      return unless json_match

      data = JSON.parse(json_match[0])

      # Store preferences
      data['preferences']&.each do |pref|
        next if pref['confidence'].to_f < 0.6

        UserMemory.create(
          user: @user,
          entity: @entity,
          memory_type: 'preference',
          category: 'communication',
          content: pref['content'],
          source: 'inferred',
          confidence: pref['confidence']
        )
      end

      # Store facts
      data['facts']&.each do |fact|
        next if fact['confidence'].to_f < 0.6

        UserMemory.create(
          user: @user,
          entity: @entity,
          memory_type: 'fact',
          category: fact['category'] || 'business',
          content: fact['content'],
          source: 'inferred',
          confidence: fact['confidence']
        )
      end

      # Store goals
      data['goals']&.each do |goal|
        next if goal['confidence'].to_f < 0.6

        UserMemory.create(
          user: @user,
          entity: @entity,
          memory_type: 'goal',
          category: 'business',
          content: goal['content'],
          source: 'inferred',
          confidence: goal['confidence']
        )
      end

      Rails.logger.info "👤 Extracted user memories: #{data['preferences']&.count || 0} prefs, #{data['facts']&.count || 0} facts, #{data['goals']&.count || 0} goals"
    rescue JSON::ParserError => e
      Rails.logger.warn "User memory extraction JSON parse failed: #{e.message}"
    rescue => e
      Rails.logger.error "User memory extraction failed: #{e.message}"
    end
  end

  def extract_scout_learnings(messages)
    return unless defined?(ScoutLearning)

    begin
      # Analyze tool usage patterns
      tool_patterns = analyze_tool_usage(messages)

      tool_patterns.each do |pattern|
        # Check if we already have this learning
        existing = ScoutLearning.where(entity: @entity)
                               .where("learning ILIKE ?", "%#{pattern[:pattern].first(30)}%")
                               .exists?
        next if existing

        ScoutLearning.learn!(
          entity: @entity,
          learning_type: pattern[:type],
          learning: pattern[:pattern],
          context: pattern[:context],
          source: 'observation',
          confidence: 0.6
        )

        Rails.logger.info "🤖 Scout learned: #{pattern[:pattern].truncate(50)}"
      end

      # Analyze delegation patterns
      analyze_delegation_patterns(messages)
    rescue => e
      Rails.logger.error "Scout learning extraction failed: #{e.message}"
    end
  end

  def analyze_tool_usage(messages)
    patterns = []

    # Look for successful tool usage patterns in assistant messages
    assistant_messages = messages.select { |m| m.role == 'assistant' }

    # Count tool mentions
    tool_mentions = Hash.new(0)
    assistant_messages.each do |msg|
      content = msg.content.to_s.downcase
      
      # Common tool patterns
      %w[get_data load_canvas web_search query_document delegate_to_agent].each do |tool|
        tool_mentions[tool] += 1 if content.include?(tool.gsub('_', ' ')) || content.include?(tool)
      end
    end

    # Generate patterns from frequent successful tool usage
    tool_mentions.each do |tool, count|
      next if count < 2

      patterns << {
        type: 'tool_usage',
        pattern: "#{tool} is frequently useful for this user",
        context: 'general'
      }
    end

    patterns
  end

  def analyze_delegation_patterns(messages)
    # Look for successful delegations
    assistant_messages = messages.select { |m| m.role == 'assistant' }

    assistant_messages.each do |msg|
      content = msg.content.to_s

      # Check for delegation mentions
      if content.include?('delegate') || content.include?('specialist')
        # Extract agent type if mentioned
        agent_match = content.match(/(?:to|delegated to|specialist|agent)[\s:]+(\w+_?\w*)/i)
        if agent_match
          agent_slug = agent_match[1].downcase.gsub(' ', '_')

          # What type of task was it?
          task_type = infer_task_type(content)

          if task_type
            ScoutLearning.remember_good_delegation(
              entity: @entity,
              agent_slug: agent_slug,
              task_type: task_type
            )
          end
        end
      end
    end
  end

  def infer_task_type(content)
    content_lower = content.downcase

    return 'landing_page' if content_lower.include?('landing page')
    return 'email_campaign' if content_lower.include?('email') && content_lower.include?('campaign')
    return 'integration' if content_lower.include?('connect') || content_lower.include?('integration')
    return 'data_import' if content_lower.include?('import')
    return 'analysis' if content_lower.include?('analyz') || content_lower.include?('report')

    nil
  end

  def find_conversation_id
    ScoutConversation.find_by(session_id: @session_id)&.id
  end

  def update_business_profile(updates)
    profile = @entity.business_profiles&.first
    profile ||= @user&.business_profile rescue nil
    return unless profile

    updates.each do |field, value|
      next if value.blank?

      if profile.respond_to?("#{field}=")
        profile.send("#{field}=", value)
      end
    end

    profile.save if profile.changed?
  end
end
