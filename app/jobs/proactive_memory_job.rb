# ProactiveMemoryJob
#
# Runs during active conversations to proactively analyze and pre-warm
# relevant memories BEFORE Scout needs them. This creates a parallel
# memory retrieval process that enriches context in real-time.
#
# Features:
# - Analyzes conversation trajectory to predict what memories will be needed
# - Pre-fetches relevant L3/L4 memories into Redis cache
# - Broadcasts memory hints to the conversation via ActionCable
# - Runs asynchronously to not block the main conversation flow
#
# Triggered:
# - After every user message (with debouncing)
# - When topic changes are detected
# - When user references past conversations
#
class ProactiveMemoryJob < ApplicationJob
  queue_as :high_priority

  # Cache key prefix for pre-warmed memories
  CACHE_PREFIX = "proactive_memory"
  
  # How long to keep pre-warmed memories in cache
  CACHE_TTL = 10.minutes
  
  # Minimum confidence to include a memory hint
  MIN_CONFIDENCE = 0.4

  def perform(user_id, entity_id, session_id, current_message, options = {})
    @user = User.find_by(id: user_id)
    @entity = Entity.find_by(id: entity_id)
    @session_id = session_id
    @current_message = current_message
    @options = options.with_indifferent_access
    
    return unless @user && @entity
    
    start_time = Time.current
    Rails.logger.info "🧠 ProactiveMemoryJob: Starting for user #{user_id}"
    
    # Build a profile of what this conversation might need
    context_profile = analyze_conversation_context
    
    # Parallel fetch relevant memories
    memories = fetch_relevant_memories(context_profile)
    
    # Cache the pre-warmed memories for instant retrieval
    cache_memories(memories) if memories[:total_count] > 0
    
    # Broadcast memory hints if significant
    broadcast_memory_hints(memories) if memories[:should_broadcast]
    
    elapsed = ((Time.current - start_time) * 1000).round
    Rails.logger.info "🧠 ProactiveMemoryJob: Completed in #{elapsed}ms - found #{memories[:total_count]} relevant memories"
    
  rescue => e
    Rails.logger.error "ProactiveMemoryJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  # Analyze the current conversation to predict what context might be needed
  def analyze_conversation_context
    profile = {
      topics: [],
      entities_mentioned: [],
      time_references: [],
      intent: nil,
      needs_history: false,
      needs_facts: false,
      needs_decisions: false,
      urgency: :normal
    }
    
    message_lower = @current_message.to_s.downcase
    
    # Detect time references (user asking about past)
    time_patterns = [
      /\b(yesterday|last week|last month|earlier|before|previously|remember when)\b/,
      /\b(what did we|when did we|have we ever|did I mention)\b/,
      /\b(go back to|recall|remind me about)\b/
    ]
    
    profile[:needs_history] = time_patterns.any? { |p| message_lower.match?(p) }
    profile[:time_references] = extract_time_references(message_lower)
    
    # Detect fact-seeking patterns
    fact_patterns = [
      /\b(what is|what's|how many|how much|who is|when is)\b/,
      /\b(our|my|the company's|business)\b.*(budget|revenue|goal|target|employee)/
    ]
    profile[:needs_facts] = fact_patterns.any? { |p| message_lower.match?(p) }
    
    # Detect decision-related patterns
    decision_patterns = [
      /\b(should we|should I|decide|decision|choose|option)\b/,
      /\b(what did we decide|the decision about)\b/
    ]
    profile[:needs_decisions] = decision_patterns.any? { |p| message_lower.match?(p) }
    
    # Extract topics
    profile[:topics] = extract_topics(@current_message)
    
    # Detect mentioned entities (agents, tools, integrations)
    profile[:entities_mentioned] = extract_mentioned_entities(message_lower)
    
    # Detect intent
    profile[:intent] = detect_intent(message_lower)
    
    # Detect urgency
    if message_lower.match?(/\b(urgent|asap|immediately|right now|quickly)\b/)
      profile[:urgency] = :high
    end
    
    profile
  end

  def extract_time_references(text)
    references = []
    
    # Relative time
    references << :yesterday if text.include?('yesterday')
    references << :last_week if text.match?(/last\s+week/)
    references << :last_month if text.match?(/last\s+month/)
    references << :earlier_today if text.match?(/earlier\s+today|this\s+morning/)
    references << :past if text.match?(/before|previously|earlier|remember/)
    
    references.uniq
  end

  def extract_topics(text)
    # Common business topics
    topic_keywords = {
      'campaign' => :marketing,
      'email' => :email,
      'landing page' => :landing_page,
      'integration' => :integrations,
      'connect' => :integrations,
      'import' => :data_import,
      'export' => :data_export,
      'contact' => :contacts,
      'lead' => :leads,
      'automation' => :automation,
      'workflow' => :automation,
      'report' => :analytics,
      'analytics' => :analytics,
      'dashboard' => :analytics,
      'budget' => :finance,
      'revenue' => :finance,
      'goal' => :goals,
      'target' => :goals
    }
    
    text_lower = text.to_s.downcase
    topics = []
    
    topic_keywords.each do |keyword, topic|
      topics << topic if text_lower.include?(keyword)
    end
    
    topics.uniq
  end

  def extract_mentioned_entities(text)
    entities = []
    
    # Check for agent mentions
    agent_patterns = [
      /landing\s*page\s*(creator|agent|builder)/i,
      /email\s*(campaign|agent|builder)/i,
      /integration\s*(agent|helper)/i,
      /data\s*(import|export)\s*agent/i
    ]
    
    agent_patterns.each_with_index do |pattern, idx|
      entities << [:agent, pattern.source.split('\\s').first] if text.match?(pattern)
    end
    
    # Check for tool mentions
    tool_keywords = %w[search analyze import export connect integrate]
    tool_keywords.each do |tool|
      entities << [:tool, tool] if text.include?(tool)
    end
    
    entities
  end

  def detect_intent(text)
    return :question if text.end_with?('?') || text.match?(/^(what|who|where|when|why|how|can|could|would)\b/)
    return :command if text.match?(/^(show|list|get|find|search|create|make|build|send|schedule)\b/)
    return :continuation if text.match?(/^(yes|no|ok|sure|great|thanks|that|this)\b/)
    return :clarification if text.match?(/\b(what do you mean|clarify|explain|more detail)\b/)
    :statement
  end

  # Fetch relevant memories based on the context profile
  def fetch_relevant_memories(profile)
    memories = {
      segments: [],
      user_memories: [],
      learnings: [],
      bookmarks: [],
      related_messages: [],
      total_count: 0,
      should_broadcast: false,
      context_summary: nil
    }
    
    threads = []
    
    # Fetch L3 segments if needed
    if profile[:needs_history] || profile[:topics].any?
      threads << Thread.new do
        memories[:segments] = fetch_relevant_segments(profile)
      end
    end
    
    # Fetch user memories (facts, preferences)
    if profile[:needs_facts] || profile[:topics].include?(:goals)
      threads << Thread.new do
        memories[:user_memories] = fetch_relevant_user_memories(profile)
      end
    end
    
    # Fetch relevant learnings
    if profile[:entities_mentioned].any? || profile[:topics].include?(:automation)
      threads << Thread.new do
        memories[:learnings] = fetch_relevant_learnings(profile)
      end
    end
    
    # Fetch bookmarks if user references "saved" items
    if @current_message.to_s.downcase.match?(/\b(saved|bookmark|important|remember)\b/)
      threads << Thread.new do
        memories[:bookmarks] = fetch_recent_bookmarks
      end
    end
    
    # Fetch related messages from L2
    if profile[:needs_history] && profile[:topics].any?
      threads << Thread.new do
        memories[:related_messages] = fetch_related_messages(profile)
      end
    end
    
    # Wait for all fetches
    threads.each(&:join)
    
    # Count total
    memories[:total_count] = [
      memories[:segments],
      memories[:user_memories],
      memories[:learnings],
      memories[:bookmarks],
      memories[:related_messages]
    ].flatten.compact.count
    
    # Determine if we should broadcast (significant context found)
    memories[:should_broadcast] = memories[:total_count] >= 2 || 
                                   memories[:segments].any? ||
                                   memories[:bookmarks].any?
    
    # Build context summary
    if memories[:total_count] > 0
      memories[:context_summary] = build_context_summary(memories, profile)
    end
    
    memories
  end

  def fetch_relevant_segments(profile)
    return [] unless defined?(MemorySegment)
    
    segments = []
    
    # Get topic-relevant segments
    if profile[:topics].any?
      topic_keywords = profile[:topics].map(&:to_s)
      segments += MemorySegment.where(user_id: @user.id, entity_id: @entity.id)
                               .where(active: true)
                               .where("key_topics ILIKE ANY(ARRAY[?])", topic_keywords.map { |k| "%#{k}%" })
                               .order(period_end: :desc)
                               .limit(3)
                               .to_a
    end
    
    # Get time-relevant segments
    if profile[:time_references].include?(:yesterday)
      segments += MemorySegment.where(user_id: @user.id, entity_id: @entity.id)
                               .where("period_end >= ?", 2.days.ago)
                               .order(period_end: :desc)
                               .limit(2)
                               .to_a
    elsif profile[:time_references].include?(:last_week)
      segments += MemorySegment.where(user_id: @user.id, entity_id: @entity.id)
                               .where("period_end >= ?", 8.days.ago)
                               .where(segment_type: 'weekly')
                               .limit(1)
                               .to_a
    end
    
    segments.uniq.first(5).map do |seg|
      {
        id: seg.id,
        type: seg.segment_type,
        period: "#{seg.period_start&.strftime('%b %d')} - #{seg.period_end&.strftime('%b %d')}",
        summary: seg.summary,
        topics: parse_json_array(seg.key_topics),
        relevance: calculate_segment_relevance(seg, profile)
      }
    end
  end

  def fetch_relevant_user_memories(profile)
    return [] unless defined?(UserMemory)
    
    memories = UserMemory.where(user: @user, entity: @entity)
                         .active
                         .high_confidence
    
    # Filter by topic-related categories
    if profile[:topics].include?(:goals)
      memories = memories.or(UserMemory.where(user: @user, entity: @entity, memory_type: 'goal'))
    end
    
    if profile[:topics].include?(:finance)
      memories = memories.or(UserMemory.where(user: @user, entity: @entity, category: 'business'))
    end
    
    memories.order(access_count: :desc).limit(5).map do |mem|
      {
        id: mem.id,
        type: mem.memory_type,
        content: mem.content,
        confidence: mem.confidence,
        category: mem.category
      }
    end
  end

  def fetch_relevant_learnings(profile)
    return [] unless defined?(ScoutLearning)
    
    learnings = ScoutLearning.where(entity: @entity)
                             .active
                             .high_confidence
    
    # Filter by context if we have entities mentioned
    if profile[:entities_mentioned].any?
      entity_names = profile[:entities_mentioned].map { |_, name| name }
      learnings = learnings.where("context ILIKE ANY(ARRAY[?])", entity_names.map { |n| "%#{n}%" })
    end
    
    learnings.order(success_rate: :desc).limit(3).map do |learning|
      {
        id: learning.id,
        type: learning.learning_type,
        content: learning.learning,
        context: learning.context,
        success_rate: learning.success_rate
      }
    end
  end

  def fetch_recent_bookmarks
    return [] unless defined?(MemoryBookmark)
    
    MemoryBookmark.where(user_id: @user.id, entity_id: @entity.id)
                  .order(created_at: :desc)
                  .limit(5)
                  .map do |bm|
      {
        id: bm.id,
        title: bm.title,
        description: bm.description,
        created_at: bm.created_at.iso8601
      }
    end
  end

  def fetch_related_messages(profile)
    return [] if profile[:topics].empty?
    
    topic_keywords = profile[:topics].map(&:to_s)
    
    ScoutMessage.where(user_id: @user.id, entity_id: @entity.id)
                .where("topics ILIKE ANY(ARRAY[?])", topic_keywords.map { |t| "%#{t}%" })
                .where("created_at > ?", 30.days.ago)
                .order(created_at: :desc)
                .limit(5)
                .map do |msg|
      {
        id: msg.id,
        role: msg.role,
        content: msg.content.truncate(200),
        created_at: msg.created_at.iso8601,
        topics: parse_json_array(msg.topics)
      }
    end
  end

  def calculate_segment_relevance(segment, profile)
    relevance = 0.5
    
    # Boost for matching topics
    segment_topics = parse_json_array(segment.key_topics)
    matching_topics = (segment_topics.map(&:to_s) & profile[:topics].map(&:to_s)).count
    relevance += matching_topics * 0.15
    
    # Boost for recency
    if segment.period_end && segment.period_end > 7.days.ago
      relevance += 0.2
    elsif segment.period_end && segment.period_end > 30.days.ago
      relevance += 0.1
    end
    
    # Apply decay factor
    relevance *= (segment.relevance_decay || 1.0)
    
    relevance.clamp(0.0, 1.0)
  end

  def build_context_summary(memories, profile)
    parts = []
    
    if memories[:segments].any?
      topics = memories[:segments].flat_map { |s| s[:topics] }.compact.uniq.first(3)
      parts << "Found #{memories[:segments].count} conversation segments about #{topics.join(', ')}"
    end
    
    if memories[:user_memories].any?
      types = memories[:user_memories].map { |m| m[:type] }.uniq
      parts << "Recalled #{memories[:user_memories].count} #{types.join('/')} memories"
    end
    
    if memories[:bookmarks].any?
      parts << "#{memories[:bookmarks].count} saved items may be relevant"
    end
    
    parts.join(". ")
  end

  # Cache memories for instant retrieval by Scout
  def cache_memories(memories)
    cache_key = "#{CACHE_PREFIX}:#{@user.id}:#{@entity.id}"
    
    cached_data = {
      fetched_at: Time.current.iso8601,
      context_summary: memories[:context_summary],
      segments: memories[:segments],
      user_memories: memories[:user_memories],
      learnings: memories[:learnings],
      bookmarks: memories[:bookmarks],
      related_messages: memories[:related_messages]
    }
    
    Rails.cache.write(cache_key, cached_data, expires_in: CACHE_TTL)
    
    Rails.logger.info "🧠 Cached #{memories[:total_count]} proactive memories"
  end

  # Broadcast memory hints to the conversation
  def broadcast_memory_hints(memories)
    return unless memories[:should_broadcast]
    
    hint_data = {
      type: 'memory_hint',
      context_summary: memories[:context_summary],
      segment_count: memories[:segments].count,
      memory_count: memories[:user_memories].count,
      has_bookmarks: memories[:bookmarks].any?,
      topics: memories[:segments].flat_map { |s| s[:topics] }.compact.uniq.first(5),
      timestamp: Time.current.iso8601
    }
    
    # Broadcast to the user-specific scout channel
    ActionCable.server.broadcast(
      "scout_user_#{@user.id}",
      hint_data
    )
    
    # Also broadcast to session if we have it
    if @session_id.present?
      ActionCable.server.broadcast(
        "scout_channel_#{@session_id}",
        hint_data
      )
    end
    
    Rails.logger.info "🧠 Broadcast memory hints: #{memories[:context_summary]}"
  rescue => e
    Rails.logger.warn "Failed to broadcast memory hints: #{e.message}"
  end

  def parse_json_array(json_string)
    return [] if json_string.blank?
    return json_string if json_string.is_a?(Array)
    
    JSON.parse(json_string)
  rescue JSON::ParserError
    []
  end
end
