# Scout::UnifiedMemory
#
# The core unified memory system for Scout. Replaces session-based conversations
# with a continuous memory stream that decays naturally over time.
#
# Memory Layers:
# - L1: Active Context (last 15 messages, always in prompt)
# - L2: Recent Memory (last 100 messages, in Redis, quick retrieve)
# - L3: Working Memory (daily/weekly summaries, in Postgres)
# - L4: Long-term Memory (all history, RAG-indexed for semantic search)
#
# Usage:
#   memory = Scout::UnifiedMemory.new(user: user, entity: entity)
#   context = memory.build_context(current_message)
#   memory.store_message(role: 'user', content: message)
#
module Scout
  class UnifiedMemory
    # Configuration
    L1_SIZE = 15        # Messages always in context
    L2_SIZE = 100       # Messages in Redis for quick access
    L3_DAILY_THRESHOLD = 50   # Messages before daily summary
    REDIS_TTL = 7.days  # Keep L2 in Redis for a week
    
    attr_reader :user, :entity, :preferences, :current_space, :fresh_start_at
    
    def initialize(user:, entity:, space: nil, fresh_start_at: nil)
      @user = user
      @entity = entity
      @redis = $redis
      @preferences = load_preferences
      @current_space = space || user&.active_space || 'work'
      @fresh_start_at = fresh_start_at # If set, only load messages after this time
    end
    
    # Load user memory preferences
    def load_preferences
      return nil unless defined?(MemoryPreference)
      MemoryPreference.for_user(user: @user, entity: @entity)
    rescue => e
      Rails.logger.debug "Could not load memory preferences: #{e.message}"
      nil
    end
    
    # Check if memory is enabled for this user
    def memory_enabled?
      return true unless @preferences
      @preferences.memory_enabled
    end
    
    # Check if cross-session memory is enabled
    def cross_session_enabled?
      return true unless @preferences
      @preferences.cross_session_memory
    end
    
    # ═══════════════════════════════════════════════════════════════
    # CONTEXT BUILDING (called before each Scout response)
    # ═══════════════════════════════════════════════════════════════
    
    # Build the complete context for a new message
    # Returns a hash with all layers, ready for prompt construction
    #
    # Phase 5C: Cross-session memory is always-on (no regex gates).
    # L3 segments are always fetched for cross-session context.
    # L4 (RAG deep search) only triggers for explicit deep-history requests.
    def build_context(current_message = nil, options = {})
      start_time = Time.current
      
      # Check if memory is enabled
      unless memory_enabled?
        return {
          l1: [],
          l2: nil,
          l3: nil,
          l4: nil,
          memory_segments: [],
          bookmarks: [],
          proactive_context: nil,
          retrieval_time_ms: 0,
          memory_disabled: true
        }
      end
      
      # L1: Always loaded (instant)
      l1_messages = fetch_l1_messages
      
      context = {
        l1: l1_messages,
        l2: nil,
        l3: nil,
        l4: nil,
        memory_segments: [],
        bookmarks: [],
        proactive_context: nil,
        retrieval_time_ms: 0
      }
      
      # First, check for pre-warmed proactive memories (instant retrieval)
      proactive = fetch_proactive_memories
      if proactive.present?
        context[:proactive_context] = proactive
        context[:l3] = proactive[:segments] if proactive[:segments].present?
        context[:bookmarks] = proactive[:bookmarks] if proactive[:bookmarks].present?
        Rails.logger.info "🧠 Using pre-warmed proactive memories (#{proactive[:segments]&.count || 0} segments)"
      end
      
      # L3: Always fetch relevant segments if cross-session is enabled (no regex gate)
      # This is cheap (~5ms Postgres query) and ensures continuity across sessions.
      if cross_session_enabled? && context[:l3].blank?
        threads = []
        
        threads << Thread.new { context[:l3] = fetch_relevant_segments(current_message) }
        
        # L4 (RAG deep search): Only for explicit deep-history requests (expensive)
        if current_message.present? && deep_history_requested?(current_message)
          threads << Thread.new { context[:l4] = search_long_term_memory(current_message) }
        end
        
        threads.each(&:join)
      end
      
      context[:retrieval_time_ms] = ((Time.current - start_time) * 1000).round
      
      proactive_label = proactive.present? ? " (proactive)" : ""
      Rails.logger.info "🧠 Memory context built in #{context[:retrieval_time_ms]}ms (L1: #{l1_messages.count} msgs#{proactive_label})"
      
      context
    end
    
    # Fetch pre-warmed memories from proactive job cache
    def fetch_proactive_memories
      cache_key = "proactive_memory:#{user.id}:#{entity.id}"
      cached = Rails.cache.read(cache_key)
      
      return nil unless cached.present?
      
      # Check if cache is fresh (within last 10 minutes)
      fetched_at = Time.parse(cached[:fetched_at]) rescue nil
      return nil unless fetched_at && fetched_at > 10.minutes.ago
      
      cached
    rescue => e
      Rails.logger.debug "Could not fetch proactive memories: #{e.message}"
      nil
    end
    
    # Trigger proactive memory job for current message
    def trigger_proactive_fetch(current_message, session_id = nil)
      return unless current_message.present?
      
      ProactiveMemoryJob.perform_later(
        user.id,
        entity.id,
        session_id || current_session_id,
        current_message
      )
    rescue => e
      Rails.logger.debug "Could not trigger proactive fetch: #{e.message}"
    end
    
    # Format context for inclusion in system prompt
    def format_for_prompt(context)
      parts = []
      
      # Add proactive context summary if available
      if context[:proactive_context].present?
        proactive = context[:proactive_context]
        if proactive[:context_summary].present?
          parts << <<~PROACTIVE
            ═══════════════════════════════════════════════════════════════
            🧠 PROACTIVE MEMORY (auto-retrieved based on conversation)
            ═══════════════════════════════════════════════════════════════
            
            #{proactive[:context_summary]}
          PROACTIVE
        end
        
        # Add relevant user memories from proactive fetch
        if proactive[:user_memories].present?
          user_mem_text = proactive[:user_memories].map do |m|
            "• #{m[:content]} (#{m[:type]})"
          end.join("\n")
          parts << "RELEVANT USER CONTEXT:\n#{user_mem_text}"
        end
        
        # Add relevant learnings from proactive fetch
        if proactive[:learnings].present?
          learning_text = proactive[:learnings].map do |l|
            "• #{l[:content]}"
          end.join("\n")
          parts << "RELEVANT LEARNINGS:\n#{learning_text}"
        end
      end
      
      # Add memory segments (L3 summaries) if present
      if context[:l3].present?
        parts << format_memory_segments(context[:l3])
      end
      
      # Add L4 search results if present
      if context[:l4].present?
        parts << format_search_results(context[:l4])
      end
      
      parts.compact.join("\n\n")
    end
    
    # ═══════════════════════════════════════════════════════════════
    # L1: ACTIVE CONTEXT (always loaded, cached)
    # ═══════════════════════════════════════════════════════════════
    
    def fetch_l1_messages
      # If fresh_start_at is set, don't use cache (cache might have old messages)
      cache_key = l1_cache_key
      
      unless @fresh_start_at
        # Try cache first (< 5ms) - only if no fresh_start filter
        cached = Rails.cache.read(cache_key)
        return cached if cached.present?
      end
      
      # Fetch from DB
      scope = ScoutMessage.where(user_id: user.id, entity_id: entity.id)
      
      # Filter by fresh_start_at if set (excludes old messages from before Fresh Start)
      if @fresh_start_at
        scope = scope.where("created_at > ?", @fresh_start_at)
        Rails.logger.info "🧠 L1 filtered by fresh_start_at: #{@fresh_start_at}"
      end
      
      messages = scope.order(created_at: :desc)
                      .limit(L1_SIZE)
                      .select(:id, :role, :content, :created_at, :metadata, :importance_score)
      
      formatted = messages.reverse.map do |m|
        {
          role: m.role,
          content: m.content,
          timestamp: m.created_at.iso8601,
          importance: m.importance_score || 0.5
        }
      end
      
      # Only cache if no fresh_start filter (otherwise we'd cache filtered results)
      unless @fresh_start_at
        Rails.cache.write(cache_key, formatted, expires_in: 1.hour)
      end
      
      formatted
    end
    
    # Invalidate L1 cache (called when new message stored)
    def invalidate_l1_cache
      Rails.cache.delete(l1_cache_key)
    end
    
    # ═══════════════════════════════════════════════════════════════
    # L2: RECENT MEMORY (Redis, for quick retrieval)
    # ═══════════════════════════════════════════════════════════════
    
    def fetch_l2_messages(count: 50, offset: 0)
      redis_key = l2_redis_key
      
      # Try Redis first
      messages_json = @redis.lrange(redis_key, offset, offset + count - 1)
      
      if messages_json.present?
        return messages_json.map { |m| JSON.parse(m, symbolize_names: true) }
      end
      
      # Fallback to DB
      messages = ScoutMessage.where(user_id: user.id, entity_id: entity.id)
                             .order(created_at: :desc)
                             .offset(offset)
                             .limit(count)
                             .select(:id, :role, :content, :created_at, :topics)
      
      messages.reverse.map do |m|
        {
          id: m.id,
          role: m.role,
          content: m.content,
          timestamp: m.created_at.iso8601,
          topics: parse_json_array(m.topics)
        }
      end
    end
    
    # Search L2 by keyword
    def search_l2(keywords:, limit: 10)
      # Use PostgreSQL full-text search on recent messages
      ScoutMessage.where(user_id: user.id, entity_id: entity.id)
                  .where("content ILIKE ANY(ARRAY[?])", keywords.map { |k| "%#{k}%" })
                  .order(created_at: :desc)
                  .limit(limit)
                  .map { |m| format_message(m) }
    end
    
    # ═══════════════════════════════════════════════════════════════
    # L3: WORKING MEMORY (Summarized segments)
    # ═══════════════════════════════════════════════════════════════
    
    def fetch_relevant_segments(current_message, limit: 3)
      return [] unless defined?(MemorySegment)
      
      # Get recent active segments
      segments = MemorySegment.where(user_id: user.id, entity_id: entity.id)
                              .where(active: true)
                              .order(period_end: :desc)
                              .limit(limit)
      
      # If message has specific topic, try to find relevant segments
      if current_message.present?
        topic_keywords = extract_topic_keywords(current_message)
        if topic_keywords.any?
          # Add topic-relevant segments
          topic_segments = MemorySegment.where(user_id: user.id, entity_id: entity.id)
                                        .where(active: true)
                                        .where("key_topics ILIKE ANY(ARRAY[?])", topic_keywords.map { |k| "%#{k}%" })
                                        .order(period_end: :desc)
                                        .limit(2)
          
          segments = (segments + topic_segments).uniq.first(limit)
        end
      end
      
      segments.map do |seg|
        {
          type: seg.segment_type,
          period: "#{seg.period_start&.strftime('%b %d')} - #{seg.period_end&.strftime('%b %d')}",
          summary: seg.summary,
          topics: parse_json_array(seg.key_topics),
          decisions: parse_json_array(seg.key_decisions),
          action_items: parse_json_array(seg.action_items)
        }
      end
    end
    
    # ═══════════════════════════════════════════════════════════════
    # L4: LONG-TERM MEMORY (RAG semantic search)
    # ═══════════════════════════════════════════════════════════════
    
    def search_long_term_memory(query, limit: 5)
      # Use existing RAG infrastructure if available
      return [] unless defined?(RagStore)
      
      begin
        # Search conversation history in RAG
        results = RagStore.search(
          query: query,
          entity_id: entity.id,
          store_type: 'conversation_history',
          limit: limit
        )
        
        results.map do |r|
          {
            content: r[:content],
            relevance: r[:score],
            date: r[:metadata]&.dig(:date),
            context: r[:metadata]&.dig(:context)
          }
        end
      rescue => e
        Rails.logger.warn "L4 search failed: #{e.message}"
        []
      end
    end
    
    # ═══════════════════════════════════════════════════════════════
    # MESSAGE STORAGE
    # ═══════════════════════════════════════════════════════════════
    
    def store_message(role:, content:, metadata: {})
      # Calculate importance score based on content
      importance = calculate_importance(role, content)
      
      # Extract topics for indexing
      topics = extract_topics(content)
      
      # Create message
      message = ScoutMessage.create!(
        user_id: user.id,
        entity_id: entity.id,
        session_id: current_session_id,  # Keep for backward compat
        role: role,
        content: content,
        metadata: metadata,
        memory_layer: 'l1',
        importance_score: importance,
        topics: topics.to_json
      )
      
      # Invalidate L1 cache
      invalidate_l1_cache
      
      # Add to Redis L2
      store_in_redis(message)
      
      # Check if we need to create summaries
      check_summarization_needed
      
      message
    end
    
    # ═══════════════════════════════════════════════════════════════
    # CONTEXT RESET / JUMP
    # ═══════════════════════════════════════════════════════════════
    
    # Reset context to a specific point in conversation
    def reset_to_bookmark(bookmark_id)
      bookmark = MemoryBookmark.find_by(id: bookmark_id, user_id: user.id, entity_id: entity.id)
      return nil unless bookmark
      
      # Load the context snapshot from bookmark
      context_snapshot = JSON.parse(bookmark.context_snapshot || '{}')
      
      # Insert a system message indicating context reset
      store_message(
        role: 'assistant',
        content: "📍 *Context restored to: #{bookmark.title}*\n\n#{bookmark.description}",
        metadata: { 
          type: 'context_reset',
          bookmark_id: bookmark.id,
          original_message_id: bookmark.scout_message_id
        }
      )
      
      # Update bookmark retrieval stats
      bookmark.increment!(:view_count)
      
      context_snapshot
    end
    
    # Jump to a specific conversation topic/time
    def jump_to_context(query)
      # Search for relevant past context
      results = search_l2(keywords: query.split(/\s+/), limit: 5)
      
      if results.empty?
        results = search_long_term_memory(query, limit: 5)
      end
      
      return nil if results.empty?
      
      # Build context summary from results
      context_summary = results.map { |r| "- #{r[:content].truncate(200)}" }.join("\n")
      
      # Insert context restoration message
      store_message(
        role: 'assistant',
        content: "📍 *Found relevant context for \"#{query}\":*\n\n#{context_summary}",
        metadata: { type: 'context_jump', query: query }
      )
      
      results
    end
    
    # ═══════════════════════════════════════════════════════════════
    # BOOKMARKS / SAVED OUTPUTS
    # ═══════════════════════════════════════════════════════════════
    
    def save_bookmark(message_id:, title:, description: nil, shareable: false)
      # SECURITY: Validate message belongs to current user AND entity
      message = ScoutMessage.find_by(id: message_id, user_id: user.id, entity_id: entity.id)
      return nil unless message
      
      # Get surrounding context - SECURITY: scoped by user AND entity
      context_messages = ScoutMessage.where(user_id: user.id, entity_id: entity.id)
                                     .where("created_at >= ? AND created_at <= ?", 
                                            message.created_at - 10.minutes, 
                                            message.created_at + 2.minutes)
                                     .order(:created_at)
                                     .limit(8)
      
      context_snapshot = context_messages.map do |m|
        { role: m.role, content: m.content.truncate(500), timestamp: m.created_at.iso8601 }
      end
      
      bookmark = MemoryBookmark.create!(
        user_id: user.id,
        entity_id: entity.id,
        scout_message_id: message_id,
        title: title,
        description: description,
        context_snapshot: context_snapshot.to_json,
        shareable: shareable,
        share_token: shareable ? SecureRandom.urlsafe_base64(16) : nil
      )
      
      # Create work item for saved output
      create_work_item_for_bookmark(bookmark, message)
      
      bookmark
    end
    
    def list_bookmarks(limit: 20)
      MemoryBookmark.where(user_id: user.id, entity_id: entity.id)
                    .order(created_at: :desc)
                    .limit(limit)
                    .map do |b|
                      {
                        id: b.id,
                        title: b.title,
                        description: b.description,
                        type: b.bookmark_type,
                        created_at: b.created_at.iso8601,
                        shareable: b.shareable,
                        share_url: b.shareable ? "/shared/#{b.share_token}" : nil
                      }
                    end
    end
    
    # ═══════════════════════════════════════════════════════════════
    # PRIVATE HELPERS
    # ═══════════════════════════════════════════════════════════════
    
    private
    
    def l1_cache_key
      "scout:memory:l1:#{user.id}:#{entity.id}"
    end
    
    def l2_redis_key
      "scout:memory:l2:#{user.id}:#{entity.id}"
    end
    
    def current_session_id
      # Generate a daily session ID for backward compatibility
      # But conceptually we treat it as one continuous conversation
      "unified_#{user.id}_#{entity.id}_#{Date.current.to_s}"
    end
    
    def store_in_redis(message)
      redis_key = l2_redis_key
      
      message_data = {
        id: message.id,
        role: message.role,
        content: message.content,
        timestamp: message.created_at.iso8601,
        topics: parse_json_array(message.topics)
      }.to_json
      
      @redis.lpush(redis_key, message_data)
      @redis.ltrim(redis_key, 0, L2_SIZE - 1)  # Keep only L2_SIZE messages
      @redis.expire(redis_key, REDIS_TTL.to_i)
    end
    
    def needs_historical_context?(message)
      return false if message.blank?
      
      # Keywords that suggest user wants history
      history_triggers = [
        /what did (we|i|you) (talk|discuss|say|do)/i,
        /remember when/i,
        /earlier (today|this week|we)/i,
        /last (time|week|month)/i,
        /previously/i,
        /before/i,
        /history/i,
        /go back to/i,
        /what about that/i,
        /the (thing|project|idea) we/i
      ]
      
      history_triggers.any? { |pattern| message.match?(pattern) }
    end
    
    def deep_history_requested?(message)
      return false if message.blank?
      
      deep_triggers = [
        /last (month|year)/i,
        /a while (ago|back)/i,
        /way back/i,
        /originally/i,
        /in the beginning/i,
        /first time/i
      ]
      
      deep_triggers.any? { |pattern| message.match?(pattern) }
    end
    
    def calculate_importance(role, content)
      score = 0.5  # Base importance
      
      # User messages slightly more important (they drive conversation)
      score += 0.1 if role == 'user'
      
      # Longer messages often more substantive
      score += 0.1 if content.length > 200
      score += 0.1 if content.length > 500
      
      # Questions are important
      score += 0.1 if content.include?('?')
      
      # Decision language
      score += 0.15 if content.match?(/\b(decide|decided|choose|chose|let's go with|confirmed)\b/i)
      
      # Action items
      score += 0.1 if content.match?(/\b(todo|action item|next step|will do|going to)\b/i)
      
      # Important markers
      score += 0.2 if content.match?(/\b(important|critical|must|essential|key)\b/i)
      
      [score, 1.0].min  # Cap at 1.0
    end
    
    def extract_topics(content)
      # Simple topic extraction - could be enhanced with NLP
      topics = []
      
      # Common business topics
      topic_patterns = {
        'email' => /\b(email|campaign|newsletter|open rate)\b/i,
        'landing_page' => /\b(landing page|webpage|page design)\b/i,
        'contacts' => /\b(contact|lead|customer|subscriber)\b/i,
        'analytics' => /\b(analytics|metrics|report|data|performance)\b/i,
        'integration' => /\b(integration|connect|api|sync)\b/i,
        'scheduling' => /\b(schedule|automat|recurring|task)\b/i,
        'content' => /\b(content|blog|article|copy)\b/i,
        'sales' => /\b(sale|revenue|deal|pipeline)\b/i
      }
      
      topic_patterns.each do |topic, pattern|
        topics << topic if content.match?(pattern)
      end
      
      topics.uniq
    end
    
    def extract_topic_keywords(message)
      words = message.downcase.gsub(/[^a-z0-9\s]/, '').split
      
      # Filter to meaningful words
      stop_words = %w[the a an is are was were be been being have has had do does did will would could should may might must shall can]
      words.reject { |w| stop_words.include?(w) || w.length < 3 }
           .first(5)
           .map { |w| "%#{w}%" }
    end
    
    def format_message(message)
      {
        id: message.id,
        role: message.role,
        content: message.content,
        timestamp: message.created_at.iso8601
      }
    end
    
    def format_memory_segments(segments)
      return "" if segments.empty?
      
      formatted = segments.map do |seg|
        parts = ["📝 #{seg[:period]} (#{seg[:type]}):"]
        parts << seg[:summary]
        parts << "Topics: #{seg[:topics].join(', ')}" if seg[:topics].any?
        parts << "Decisions: #{seg[:decisions].join('; ')}" if seg[:decisions].any?
        parts << "Pending: #{seg[:action_items].join('; ')}" if seg[:action_items].any?
        parts.join("\n")
      end
      
      <<~PROMPT
        ═══════════════════════════════════════════════════════════════
        📚 FROM YOUR MEMORY (earlier conversations)
        ═══════════════════════════════════════════════════════════════
        
        #{formatted.join("\n\n")}
      PROMPT
    end
    
    def format_search_results(results)
      return "" if results.empty?
      
      formatted = results.map do |r|
        "• [#{r[:date] || 'past'}] #{r[:content].truncate(200)}"
      end
      
      <<~PROMPT
        ═══════════════════════════════════════════════════════════════
        🔍 RELEVANT PAST CONTEXT
        ═══════════════════════════════════════════════════════════════
        
        #{formatted.join("\n")}
      PROMPT
    end
    
    def check_summarization_needed
      # Count recent messages
      recent_count = ScoutMessage.where(user_id: user.id, entity_id: entity.id)
                                 .where("created_at > ?", 24.hours.ago)
                                 .where(summarized: false)
                                 .count
      
      if recent_count >= L3_DAILY_THRESHOLD
        # Queue summarization job
        CreateMemorySegmentJob.perform_later(user.id, entity.id, 'daily')
      end
    end
    
    def create_work_item_for_bookmark(bookmark, message)
      AgentWorkItem.create!(
        entity_id: entity.id,
        user_id: user.id,
        work_type: 'asset_created',  # Using existing type
        title: "Saved: #{bookmark.title}",
        summary: bookmark.description || message.content.truncate(200),
        details: message.content,
        asset_type: 'MemoryBookmark',
        asset_id: bookmark.id,
        priority: 'normal',
        metadata: {
          bookmark_type: bookmark.bookmark_type,
          shareable: bookmark.shareable,
          share_token: bookmark.share_token
        }
      )
    end
    
    def parse_json_array(json_string)
      return [] if json_string.blank?
      JSON.parse(json_string)
    rescue JSON::ParserError
      []
    end
  end
end
