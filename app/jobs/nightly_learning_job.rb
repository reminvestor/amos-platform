# NightlyLearningJob
#
# Runs overnight (or periodically) to perform deep analysis of conversations
# and extract higher-level patterns, consolidate learnings, and update
# Scout's personality based on observed interactions.
#
# Features:
# - Deep analysis of all daily conversations
# - Extract meta-patterns (patterns of patterns)
# - Consolidate fragmented learnings
# - Update Scout personality based on user interactions
# - Generate weekly/monthly knowledge summaries
# - Clean up low-confidence or contradictory learnings
#
# Schedule: Daily at 2 AM (configured in solid_queue.yml or recurring jobs)
#
class NightlyLearningJob < ApplicationJob
  queue_as :low_priority

  # Minimum messages needed for analysis
  MIN_MESSAGES_FOR_ANALYSIS = 10
  
  # Confidence threshold for keeping learnings
  MIN_CONFIDENCE_THRESHOLD = 0.3
  
  # How many days to look back for pattern detection
  ANALYSIS_WINDOW_DAYS = 7

  def perform(options = {})
    @options = options.with_indifferent_access
    @stats = {
      entities_processed: 0,
      learnings_created: 0,
      learnings_consolidated: 0,
      learnings_removed: 0,
      personalities_updated: 0,
      segments_created: 0
    }
    
    start_time = Time.current
    Rails.logger.info "🌙 NightlyLearningJob: Starting nightly learning process"
    
    # Get entities with recent activity
    active_entities = get_active_entities
    
    Rails.logger.info "🌙 Processing #{active_entities.count} active entities"
    
    active_entities.each do |entity|
      process_entity(entity)
    end
    
    # Global cleanup tasks
    cleanup_stale_learnings
    consolidate_similar_learnings
    
    elapsed = ((Time.current - start_time) / 60.0).round(2)
    Rails.logger.info "🌙 NightlyLearningJob: Completed in #{elapsed} minutes - #{@stats}"
    
    @stats
  rescue => e
    Rails.logger.error "NightlyLearningJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    raise
  end

  private

  def get_active_entities
    # Find entities with messages in the last 24 hours
    entity_ids = ScoutMessage.where("created_at > ?", 24.hours.ago)
                             .distinct
                             .pluck(:entity_id)
    
    Entity.where(id: entity_ids)
  end

  def process_entity(entity)
    Rails.logger.info "🌙 Processing entity: #{entity.name} (#{entity.id})"
    
    # Get all users who interacted with this entity recently
    user_ids = ScoutMessage.where(entity_id: entity.id)
                          .where("created_at > ?", 24.hours.ago)
                          .distinct
                          .pluck(:user_id)
    
    user_ids.each do |user_id|
      user = User.find_by(id: user_id)
      next unless user
      
      process_user_entity(user, entity)
    end
    
    # Entity-level learning (patterns across all users)
    analyze_entity_patterns(entity)
    update_scout_personality(entity)
    
    @stats[:entities_processed] += 1
  end

  def process_user_entity(user, entity)
    # Get today's messages
    messages = ScoutMessage.where(user_id: user.id, entity_id: entity.id)
                          .where("created_at > ?", 24.hours.ago)
                          .order(created_at: :asc)
    
    return if messages.count < MIN_MESSAGES_FOR_ANALYSIS
    
    # Analyze conversations
    analyze_user_patterns(user, entity, messages)
    extract_user_learnings(user, entity, messages)
    create_memory_segments_if_needed(user, entity, messages)
  end

  # ═══════════════════════════════════════════════════════════════
  # USER PATTERN ANALYSIS
  # ═══════════════════════════════════════════════════════════════

  def analyze_user_patterns(user, entity, messages)
    # Analyze timing patterns
    timing_pattern = analyze_timing_patterns(messages)
    if timing_pattern
      record_user_pattern(user, entity, timing_pattern)
    end
    
    # Analyze topic patterns
    topic_pattern = analyze_topic_patterns(messages)
    if topic_pattern
      record_user_pattern(user, entity, topic_pattern)
    end
    
    # Analyze communication style
    style_pattern = analyze_communication_style(messages)
    if style_pattern
      record_user_pattern(user, entity, style_pattern)
    end
  end

  def analyze_timing_patterns(messages)
    return nil if messages.count < 5
    
    hours = messages.map { |m| m.created_at.hour }
    
    # Find peak hours
    hour_counts = hours.tally
    peak_hour = hour_counts.max_by { |_, v| v }&.first
    
    return nil unless peak_hour
    
    time_of_day = case peak_hour
    when 5..11 then "morning"
    when 12..17 then "afternoon"
    when 18..21 then "evening"
    else "late night"
    end
    
    {
      type: 'timing',
      pattern: "User is most active in the #{time_of_day}",
      confidence: 0.6,
      metadata: { peak_hour: peak_hour, sample_size: messages.count }
    }
  end

  def analyze_topic_patterns(messages)
    # Extract topics from all messages
    all_topics = messages.flat_map do |m|
      parse_json_array(m.topics)
    end.compact
    
    return nil if all_topics.empty?
    
    topic_counts = all_topics.tally
    top_topics = topic_counts.sort_by { |_, v| -v }.first(3)
    
    return nil if top_topics.empty?
    
    {
      type: 'topics',
      pattern: "User frequently discusses: #{top_topics.map(&:first).join(', ')}",
      confidence: 0.7,
      metadata: { topic_counts: topic_counts }
    }
  end

  def analyze_communication_style(messages)
    user_messages = messages.select { |m| m.role == 'user' }
    return nil if user_messages.count < 5
    
    # Analyze message length
    avg_length = user_messages.map { |m| m.content.to_s.length }.sum.to_f / user_messages.count
    
    style = if avg_length < 50
      "brief and direct"
    elsif avg_length < 150
      "moderate length"
    else
      "detailed and thorough"
    end
    
    # Analyze question frequency
    question_count = user_messages.count { |m| m.content.to_s.strip.end_with?('?') }
    question_ratio = question_count.to_f / user_messages.count
    
    question_style = if question_ratio > 0.6
      "primarily asks questions"
    elsif question_ratio > 0.3
      "mix of questions and statements"
    else
      "primarily gives directions"
    end
    
    {
      type: 'communication',
      pattern: "User communication is #{style}, #{question_style}",
      confidence: 0.6,
      metadata: { avg_length: avg_length.round, question_ratio: question_ratio.round(2) }
    }
  end

  def record_user_pattern(user, entity, pattern)
    return unless defined?(UserMemory)
    
    # Check for existing similar pattern
    existing = UserMemory.where(user: user, entity: entity, memory_type: 'pattern')
                        .where("content ILIKE ?", "%#{pattern[:type]}%")
                        .first
    
    if existing
      # Update confidence if pattern is reconfirmed
      new_confidence = [(existing.confidence + 0.05), 1.0].min
      existing.update!(confidence: new_confidence, last_accessed_at: Time.current)
    else
      UserMemory.create!(
        user: user,
        entity: entity,
        memory_type: 'pattern',
        category: 'communication',
        content: pattern[:pattern],
        source: 'observation',
        confidence: pattern[:confidence]
      )
      @stats[:learnings_created] += 1
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # LEARNING EXTRACTION
  # ═══════════════════════════════════════════════════════════════

  def extract_user_learnings(user, entity, messages)
    # Analyze tool usage patterns
    analyze_tool_usage_deep(entity, messages)
    
    # Analyze delegation outcomes
    analyze_delegation_outcomes(entity, messages)
    
    # Analyze error patterns
    analyze_error_patterns(entity, messages)
  end

  def analyze_tool_usage_deep(entity, messages)
    return unless defined?(ScoutLearning)
    
    assistant_messages = messages.select { |m| m.role == 'assistant' }
    
    # Track tool mentions and outcomes
    tool_outcomes = Hash.new { |h, k| h[k] = { success: 0, failure: 0 } }
    
    assistant_messages.each_with_index do |msg, idx|
      content = msg.content.to_s.downcase
      
      # Common tools to track
      %w[get_data load_canvas web_search query_document delegate_to_agent].each do |tool|
        if content.include?(tool.gsub('_', ' ')) || content.include?(tool)
          # Check if next user message is positive or negative
          next_user = messages.find { |m| m.role == 'user' && m.created_at > msg.created_at }
          if next_user
            if positive_feedback?(next_user.content)
              tool_outcomes[tool][:success] += 1
            elsif negative_feedback?(next_user.content)
              tool_outcomes[tool][:failure] += 1
            end
          end
        end
      end
    end
    
    # Record learnings for tools with clear patterns
    tool_outcomes.each do |tool, outcomes|
      total = outcomes[:success] + outcomes[:failure]
      next if total < 2
      
      success_rate = outcomes[:success].to_f / total
      
      if success_rate >= 0.7
        record_tool_learning(entity, tool, "#{tool} works well for this user", success_rate)
      elsif success_rate <= 0.3 && total >= 3
        record_tool_learning(entity, tool, "#{tool} may need different approach for this user", success_rate)
      end
    end
  end

  def positive_feedback?(content)
    content.to_s.downcase.match?(/\b(thanks|great|perfect|yes|correct|good|awesome|exactly|nice)\b/)
  end

  def negative_feedback?(content)
    content.to_s.downcase.match?(/\b(no|wrong|not what|incorrect|error|problem|issue|doesn't|don't)\b/)
  end

  def record_tool_learning(entity, tool, learning, success_rate)
    existing = ScoutLearning.where(entity: entity, learning_type: 'tool_usage')
                           .where("learning ILIKE ?", "%#{tool}%")
                           .first
    
    if existing
      existing.update!(
        success_rate: success_rate,
        confidence: [(existing.confidence + 0.05), 1.0].min,
        last_applied_at: Time.current
      )
    else
      ScoutLearning.create!(
        entity: entity,
        learning_type: 'tool_usage',
        learning: learning,
        context: tool,
        source: 'observation',
        confidence: 0.6,
        success_rate: success_rate
      )
      @stats[:learnings_created] += 1
    end
  end

  def analyze_delegation_outcomes(entity, messages)
    return unless defined?(ScoutLearning)
    
    # Find delegation messages
    delegation_messages = messages.select do |m|
      m.role == 'assistant' && m.content.to_s.downcase.match?(/delegate|specialist|agent/)
    end
    
    delegation_messages.each do |msg|
      # Extract agent name
      agent_match = msg.content.to_s.match(/(?:to|delegated to)\s+(\w+(?:\s+\w+)?)\s*(?:agent|specialist)?/i)
      next unless agent_match
      
      agent_name = agent_match[1].downcase.gsub(' ', '_')
      
      # Find subsequent messages to determine outcome
      subsequent = messages.select { |m| m.created_at > msg.created_at }.first(5)
      
      success = subsequent.any? { |m| m.role == 'user' && positive_feedback?(m.content) }
      failure = subsequent.any? { |m| m.role == 'user' && negative_feedback?(m.content) }
      
      if success && !failure
        ScoutLearning.remember_good_delegation(
          entity: entity,
          agent_slug: agent_name,
          task_type: infer_task_type(msg.content)
        ) rescue nil
        @stats[:learnings_created] += 1
      end
    end
  end

  def analyze_error_patterns(entity, messages)
    return unless defined?(ScoutLearning)
    
    # Find error mentions
    error_messages = messages.select do |m|
      m.content.to_s.downcase.match?(/\b(error|failed|couldn't|unable|problem|issue)\b/)
    end
    
    return if error_messages.empty?
    
    # Group by error type
    error_types = error_messages.map do |m|
      content = m.content.to_s.downcase
      if content.include?('timeout') || content.include?('slow')
        'timeout'
      elsif content.include?('permission') || content.include?('access')
        'permission'
      elsif content.include?('not found') || content.include?('missing')
        'not_found'
      else
        'general'
      end
    end.tally
    
    # Record patterns for frequent errors
    error_types.each do |error_type, count|
      next if count < 2
      
      existing = ScoutLearning.where(entity: entity, learning_type: 'error_recovery')
                             .where("context = ?", error_type)
                             .first
      
      unless existing
        ScoutLearning.create!(
          entity: entity,
          learning_type: 'error_recovery',
          learning: "#{error_type.titleize} errors occur frequently - may need special handling",
          context: error_type,
          source: 'observation',
          confidence: 0.5
        )
        @stats[:learnings_created] += 1
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ENTITY-LEVEL ANALYSIS
  # ═══════════════════════════════════════════════════════════════

  def analyze_entity_patterns(entity)
    # Get messages from the analysis window
    messages = ScoutMessage.where(entity_id: entity.id)
                          .where("created_at > ?", ANALYSIS_WINDOW_DAYS.days.ago)
    
    return if messages.count < 20
    
    # Analyze peak usage times
    analyze_entity_usage_patterns(entity, messages)
    
    # Analyze most common workflows
    analyze_workflow_patterns(entity, messages)
  end

  def analyze_entity_usage_patterns(entity, messages)
    # Day of week analysis
    day_counts = messages.group("EXTRACT(DOW FROM created_at)").count
    peak_day = day_counts.max_by { |_, v| v }&.first&.to_i
    
    day_names = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
    peak_day_name = day_names[peak_day] if peak_day
    
    if peak_day_name
      record_entity_optimization(
        entity,
        "Peak usage day is #{peak_day_name}",
        'usage_pattern'
      )
    end
  end

  def analyze_workflow_patterns(entity, messages)
    # Look for common sequences of actions
    # This is a simplified version - could use more sophisticated sequence mining
    
    assistant_messages = messages.where(role: 'assistant').order(created_at: :asc)
    
    # Track action sequences
    sequences = []
    current_sequence = []
    
    assistant_messages.each do |msg|
      actions = extract_actions(msg.content)
      if actions.any?
        current_sequence += actions
      else
        if current_sequence.length >= 2
          sequences << current_sequence.join(' → ')
        end
        current_sequence = []
      end
    end
    
    # Find common sequences
    sequence_counts = sequences.tally
    common_sequences = sequence_counts.select { |_, v| v >= 2 }.keys
    
    common_sequences.first(3).each do |sequence|
      record_entity_optimization(
        entity,
        "Common workflow: #{sequence}",
        'workflow'
      )
    end
  end

  def extract_actions(content)
    actions = []
    content_lower = content.to_s.downcase
    
    actions << 'search' if content_lower.match?(/search|find|look/)
    actions << 'show' if content_lower.match?(/show|display|load.*canvas/)
    actions << 'create' if content_lower.match?(/creat|build|generat/)
    actions << 'delegate' if content_lower.match?(/delegat|specialist|agent/)
    actions << 'analyze' if content_lower.match?(/analyz|report|dashboard/)
    
    actions
  end

  def record_entity_optimization(entity, learning, context)
    return unless defined?(ScoutLearning)
    
    existing = ScoutLearning.where(entity: entity, learning_type: 'optimization')
                           .where("learning ILIKE ?", "%#{learning.first(30)}%")
                           .first
    
    unless existing
      ScoutLearning.create!(
        entity: entity,
        learning_type: 'optimization',
        learning: learning,
        context: context,
        source: 'observation',
        confidence: 0.6
      )
      @stats[:learnings_created] += 1
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PERSONALITY UPDATES
  # ═══════════════════════════════════════════════════════════════

  def update_scout_personality(entity)
    return unless defined?(ScoutPersonality)
    
    personality = ScoutPersonality.find_or_initialize_by(entity: entity)
    
    # Set defaults for new personality
    if personality.new_record?
      personality.formality = 5
      personality.verbosity = 4
      personality.proactivity = 7
      personality.humor = 3
      personality.technicality = 5
      personality.greeting_style = 'warm'
      personality.response_length = 'concise'
      personality.use_emojis = true
      personality.show_thinking = false
      personality.name = 'Scout'
    end
    
    # Get user patterns to inform personality
    user_memories = UserMemory.where(entity: entity, memory_type: 'pattern')
                              .where("confidence >= ?", 0.6)
    
    return if user_memories.empty? && !personality.new_record?
    
    # Analyze communication preferences
    comm_patterns = user_memories.where(category: 'communication')
    
    if comm_patterns.any?
      # Adjust verbosity based on user style (1-10 scale)
      brief_count = comm_patterns.count { |m| m.content.to_s.include?('brief') }
      detailed_count = comm_patterns.count { |m| m.content.to_s.include?('detailed') || m.content.to_s.include?('thorough') }
      
      if brief_count > detailed_count
        personality.verbosity = [personality.verbosity - 1, 1].max
        personality.response_length = 'brief'
      elsif detailed_count > brief_count
        personality.verbosity = [personality.verbosity + 1, 10].min
        personality.response_length = 'detailed'
      end
    end
    
    # Set proactivity based on question ratio (1-10 scale)
    question_patterns = user_memories.where("content ILIKE ?", "%question%")
    if question_patterns.any?
      pattern = question_patterns.first
      if pattern.content.to_s.include?('primarily asks')
        personality.proactivity = [personality.proactivity - 1, 1].max # Wait for questions
      else
        personality.proactivity = [personality.proactivity + 1, 10].min # Be more proactive
      end
    end
    
    if personality.changed? || personality.new_record?
      personality.save!
      @stats[:personalities_updated] += 1
      Rails.logger.info "🌙 Updated Scout personality for entity #{entity.id}"
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # MEMORY SEGMENT CREATION
  # ═══════════════════════════════════════════════════════════════

  def create_memory_segments_if_needed(user, entity, messages)
    return unless defined?(MemorySegment)
    
    # Check if we already have a segment for today
    existing = MemorySegment.where(user_id: user.id, entity_id: entity.id)
                           .where(segment_type: 'daily')
                           .where("period_start >= ?", Date.current.beginning_of_day)
                           .exists?
    
    return if existing
    
    # Only create if we have enough messages
    return if messages.count < MIN_MESSAGES_FOR_ANALYSIS
    
    # Queue segment creation
    CreateMemorySegmentJob.perform_later(user.id, entity.id, 'daily')
    @stats[:segments_created] += 1
  end

  # ═══════════════════════════════════════════════════════════════
  # CLEANUP & CONSOLIDATION
  # ═══════════════════════════════════════════════════════════════

  def cleanup_stale_learnings
    return unless defined?(ScoutLearning)
    
    # Remove low-confidence learnings that haven't been applied
    stale = ScoutLearning.where(active: true)
                        .where("confidence < ?", MIN_CONFIDENCE_THRESHOLD)
                        .where("apply_count = 0")
                        .where("created_at < ?", 30.days.ago)
    
    count = stale.count
    stale.update_all(active: false)
    
    @stats[:learnings_removed] += count
    Rails.logger.info "🌙 Deactivated #{count} stale learnings"
  end

  def consolidate_similar_learnings
    return unless defined?(ScoutLearning)
    
    # Find and merge similar learnings
    Entity.find_each do |entity|
      learnings = ScoutLearning.where(entity: entity, active: true)
                              .order(created_at: :asc)
      
      next if learnings.count < 2
      
      # Group by type and context
      grouped = learnings.group_by { |l| [l.learning_type, l.context] }
      
      grouped.each do |(type, context), group|
        next if group.count < 2
        
        # Keep the one with highest success rate, deactivate others
        best = group.max_by { |l| [l.success_rate || 0, l.confidence] }
        others = group - [best]
        
        if others.any?
          others.each { |l| l.update!(active: false) }
          
          # Boost confidence of the kept learning
          best.update!(confidence: [best.confidence + 0.1, 1.0].min)
          
          @stats[:learnings_consolidated] += others.count
        end
      end
    end
    
    Rails.logger.info "🌙 Consolidated #{@stats[:learnings_consolidated]} duplicate learnings"
  end

  def infer_task_type(content)
    content_lower = content.to_s.downcase
    
    return 'landing_page' if content_lower.include?('landing page')
    return 'email_campaign' if content_lower.include?('email') && content_lower.include?('campaign')
    return 'integration' if content_lower.include?('connect') || content_lower.include?('integration')
    return 'data_import' if content_lower.include?('import')
    return 'analysis' if content_lower.include?('analyz') || content_lower.include?('report')
    
    'general'
  end

  def parse_json_array(json_string)
    return [] if json_string.blank?
    return json_string if json_string.is_a?(Array)
    
    JSON.parse(json_string)
  rescue JSON::ParserError
    []
  end
end
