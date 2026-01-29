# frozen_string_literal: true

module Amos
  # LearnedBehaviors - Persistent learning that survives topic changes
  #
  # Unlike SessionFocus (clears on topic change) and SessionTopic (30 min TTL),
  # Learned Behaviors persist longer and help Amos avoid repeating mistakes.
  #
  # This integrates with:
  # - Living Platform / Evolution Engine: For long-term pattern learning
  # - Learning::ImmediateExperienceService: For quick corrections
  # - Learning::SemanticAdvantageService: For extracting what works
  # - Scout::MemoryAnalyzer: For explicit "remember this" requests
  #
  # Behavior Types:
  # - tool_corrections: "Don't use X for Y, use Z instead"
  # - format_preferences: "User prefers tables over bullet points"
  # - workflow_patterns: "Always ask for approval before sending"
  # - communication_style: "Keep responses brief and direct"
  #
  class LearnedBehaviors
    REDIS_PREFIX = "amos:learned"
    DEFAULT_TTL = 24.hours.to_i  # Persist for 24 hours (longer than session topic)
    MAX_BEHAVIORS_PER_TYPE = 10  # Keep most recent N per type
    
    BEHAVIOR_TYPES = %i[
      tool_correction
      format_preference
      workflow_pattern
      communication_style
      content_preference
      error_recovery
      domain_knowledge
    ].freeze

    attr_reader :user, :entity, :key_prefix

    def initialize(user:, entity:, key_prefix: nil)
      @user = user
      @entity = entity
      @key_prefix = key_prefix  # Optional prefix for testing isolation
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CORE OPERATIONS
    # ═══════════════════════════════════════════════════════════════════════════

    # Record a learned behavior
    # @param type [Symbol] One of BEHAVIOR_TYPES
    # @param behavior [String] The behavior description
    # @param source [String] Where this came from (implicit_feedback, explicit_correction, etc.)
    # @param confidence [Float] How confident we are (0.0-1.0)
    def learn(type:, behavior:, source: 'explicit', confidence: 0.8)
      type_sym = type.to_sym
      unless BEHAVIOR_TYPES.include?(type_sym)
        Rails.logger.warn "[LearnedBehaviors] Invalid behavior type: #{type}"
        return false
      end

      behaviors = get_behaviors(type_sym)
      
      # Add new behavior
      new_behavior = {
        behavior: behavior,
        source: source,
        confidence: confidence,
        learned_at: Time.current.iso8601,
        applied_count: 0,
        last_applied_at: nil
      }
      
      # Deduplicate (don't add if similar behavior exists)
      unless duplicate_behavior?(behaviors, behavior)
        behaviors.unshift(new_behavior)
        behaviors = behaviors.first(MAX_BEHAVIORS_PER_TYPE)
        save_behaviors(type_sym, behaviors)
        
        Rails.logger.info "🧠 [LearnedBehaviors] Learned #{type_sym}: #{behavior.truncate(50)}"
        
        # Also persist to database for Evolution Engine
        persist_to_database(type_sym, new_behavior)
      end
      
      true
    rescue => e
      Rails.logger.error "[LearnedBehaviors] Failed to learn: #{e.message}"
      false
    end

    # Get all behaviors of a specific type
    def get_behaviors(type)
      data = $redis.get(behavior_key(type))
      return [] unless data.present?
      
      JSON.parse(data, symbolize_names: true)
    rescue JSON::ParserError
      []
    rescue => e
      Rails.logger.error "[LearnedBehaviors] Failed to get behaviors: #{e.message}"
      []
    end

    # Get all learned behaviors
    def all_behaviors
      result = {}
      BEHAVIOR_TYPES.each do |type|
        behaviors = get_behaviors(type)
        result[type] = behaviors if behaviors.any?
      end
      result
    end

    # Mark a behavior as applied (for tracking effectiveness)
    def mark_applied(type:, behavior_index: 0)
      behaviors = get_behaviors(type)
      return false if behaviors.empty? || behavior_index >= behaviors.length
      
      behaviors[behavior_index][:applied_count] = (behaviors[behavior_index][:applied_count] || 0) + 1
      behaviors[behavior_index][:last_applied_at] = Time.current.iso8601
      
      save_behaviors(type, behaviors)
      true
    end

    # Forget a specific behavior
    def forget(type:, behavior_index: 0)
      behaviors = get_behaviors(type)
      return false if behaviors.empty? || behavior_index >= behaviors.length
      
      removed = behaviors.delete_at(behavior_index)
      save_behaviors(type, behaviors)
      
      Rails.logger.info "🧠 [LearnedBehaviors] Forgot #{type}: #{removed[:behavior].truncate(50)}"
      true
    end

    # Clear all behaviors of a type
    def clear_type(type)
      $redis.del(behavior_key(type))
      true
    end

    # Clear all learned behaviors
    def clear_all
      BEHAVIOR_TYPES.each { |type| clear_type(type) }
      true
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # INTEGRATION WITH LIVING PLATFORM
    # ═══════════════════════════════════════════════════════════════════════════

    # Load behaviors from database (for persistence across Redis restarts)
    def load_from_database
      return unless defined?(ScoutLearning)
      
      # Load recent scout learnings
      learnings = ScoutLearning.where(entity: @entity)
        .where(learning_type: BEHAVIOR_TYPES.map(&:to_s))
        .where('created_at > ?', 7.days.ago)
        .order(created_at: :desc)
        .limit(50)
      
      learnings.each do |learning|
        type = learning.learning_type.to_sym
        behaviors = get_behaviors(type)
        
        # Don't re-add if already in Redis
        next if behaviors.any? { |b| b[:behavior] == learning.content }
        
        behaviors.unshift(
          behavior: learning.content,
          source: 'database',
          confidence: learning.confidence || 0.8,
          learned_at: learning.created_at.iso8601,
          applied_count: learning.applied_count || 0,
          last_applied_at: nil
        )
        
        save_behaviors(type, behaviors.first(MAX_BEHAVIORS_PER_TYPE))
      end
      
      Rails.logger.info "🧠 [LearnedBehaviors] Loaded #{learnings.count} behaviors from database"
    rescue => e
      Rails.logger.warn "[LearnedBehaviors] Could not load from database: #{e.message}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PROMPT FORMATTING
    # ═══════════════════════════════════════════════════════════════════════════

    # Format all learned behaviors for injection into system prompt
    def format_for_prompt
      behaviors = all_behaviors
      return "" if behaviors.empty?

      lines = ["🧠 LEARNED BEHAVIORS (avoid past mistakes):"]
      
      behaviors.each do |type, type_behaviors|
        type_label = type.to_s.titleize.gsub('_', ' ')
        lines << "\n#{type_label}:"
        
        type_behaviors.first(3).each do |b|
          confidence_emoji = b[:confidence] >= 0.9 ? "⚠️" : "💡"
          lines << "  #{confidence_emoji} #{b[:behavior]}"
        end
      end

      <<~BEHAVIORS
        ═══════════════════════════════════════════════════════════════
        #{lines.join("\n")}
        ═══════════════════════════════════════════════════════════════
      BEHAVIORS
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # AUTO-LEARNING FROM CONVERSATION
    # ═══════════════════════════════════════════════════════════════════════════

    # Analyze a message for implicit corrections
    # Called after Amos responds and user provides feedback
    def analyze_for_corrections(user_message:, amos_response:, user_reaction: nil)
      # Explicit correction patterns
      correction_patterns = [
        /no,?\s+(actually|instead|rather|don't|stop)/i,
        /that's (wrong|not right|incorrect)/i,
        /i (said|meant|wanted|asked for)/i,
        /you (missed|forgot|ignored|didn't)/i,
        /please (stop|don't|always|never)/i,
        /in the future,?\s+(please|always|never|don't)/i,
        /remember (to|that|this)/i,
        /next time,?\s+(please|don't|always)/i
      ]
      
      if correction_patterns.any? { |p| user_message.match?(p) }
        extract_correction(user_message)
      end
      
      # Implicit negative feedback (from Living Platform)
      if user_reaction == :negative || user_reaction == :retry
        learn(
          type: :error_recovery,
          behavior: "Previous approach didn't work for: #{amos_response.truncate(100)}",
          source: 'implicit_feedback',
          confidence: 0.6
        )
      end
    end

    private

    def behavior_key(type)
      prefix = @key_prefix || REDIS_PREFIX
      "#{prefix}:#{@user.id}:#{@entity.id}:#{type}"
    end

    def save_behaviors(type, behaviors)
      $redis.setex(behavior_key(type), DEFAULT_TTL, behaviors.to_json)
    end

    def duplicate_behavior?(behaviors, new_behavior)
      behaviors.any? do |existing|
        # Simple similarity check - could be enhanced with embeddings
        existing[:behavior].downcase.include?(new_behavior.downcase.first(30)) ||
        new_behavior.downcase.include?(existing[:behavior].downcase.first(30))
      end
    end

    def extract_correction(message)
      # Extract what the correction is about
      correction = message
        .gsub(/no,?\s+(actually|instead|rather)?/i, '')
        .gsub(/please\s*/i, '')
        .strip
        .truncate(200)
      
      # Determine type based on keywords
      type = if message.match?(/format|table|list|bullet|output/i)
        :format_preference
      elsif message.match?(/tool|use|don't use|instead of/i)
        :tool_correction
      elsif message.match?(/tone|style|voice|brief|detailed|formal/i)
        :communication_style
      else
        :workflow_pattern
      end
      
      learn(
        type: type,
        behavior: correction,
        source: 'explicit_correction',
        confidence: 0.9
      )
    end

    def persist_to_database(type, behavior_data)
      return unless defined?(ScoutLearning)
      
      ScoutLearning.create(
        entity: @entity,
        user: @user,
        learning_type: type.to_s,
        content: behavior_data[:behavior],
        confidence: behavior_data[:confidence],
        source: behavior_data[:source],
        applied_count: 0
      )
    rescue => e
      Rails.logger.debug "[LearnedBehaviors] Could not persist to database: #{e.message}"
    end
  end
end
