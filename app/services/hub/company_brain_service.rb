# frozen_string_literal: true

module Hub
  # CompanyBrainService
  #
  # Searchable institutional knowledge from Hub conversations.
  # "What did we decide about X?" / "How have we handled this before?"
  #
  class CompanyBrainService
    def initialize(entity:, user:)
      @entity = entity
      @user = user
    end

    # ============================================
    # SEARCH
    # ============================================

    # Full-text search across accessible Hub content
    def search(query, limit: 20)
      accessible_thread_ids = accessible_thread_ids_for(@user)
      
      return [] if accessible_thread_ids.empty?

      results = HubMessage.where(hub_thread_id: accessible_thread_ids)
                          .where(deleted: false)
                          .where('content ILIKE ?', "%#{query}%")
                          .includes(:hub_thread, :sender)
                          .order(created_at: :desc)
                          .limit(limit)

      results.map { |m| format_search_result(m) }
    end

    # Semantic search (if embeddings are available)
    def semantic_search(query, limit: 10)
      # For now, fall back to text search
      # Could integrate with vector store for semantic matching
      search(query, limit: limit)
    end

    # Search within a specific time range
    def search_in_period(query, from:, to:, limit: 20)
      accessible_thread_ids = accessible_thread_ids_for(@user)
      
      HubMessage.where(hub_thread_id: accessible_thread_ids)
                .where(deleted: false)
                .where('content ILIKE ?', "%#{query}%")
                .where(created_at: from..to)
                .includes(:hub_thread, :sender)
                .order(created_at: :desc)
                .limit(limit)
                .map { |m| format_search_result(m) }
    end

    # ============================================
    # KNOWLEDGE QUERIES
    # ============================================

    # "What did we decide about X?"
    def find_decisions_about(topic)
      accessible_thread_ids = accessible_thread_ids_for(@user)
      
      # Look for decision-related messages
      decision_patterns = [
        "decided to",
        "agreed on",
        "approved",
        "confirmed",
        "going with",
        "let's do",
        "we'll use",
        "final decision"
      ]

      results = HubMessage.where(hub_thread_id: accessible_thread_ids)
                          .where(deleted: false)
                          .where('content ILIKE ?', "%#{topic}%")
                          .where(decision_patterns.map { |p| "content ILIKE '%#{p}%'" }.join(' OR '))
                          .includes(:hub_thread, :sender)
                          .order(created_at: :desc)
                          .limit(10)

      results.map { |m| format_decision_result(m) }
    end

    # "How have we handled X before?"
    def find_precedents_for(situation)
      accessible_thread_ids = accessible_thread_ids_for(@user)
      
      # Look for resolution/handling messages
      resolution_patterns = [
        "we handled",
        "solution was",
        "fixed by",
        "resolved",
        "worked around",
        "our approach"
      ]

      # Also check completed handoffs
      results = HubMessage.where(hub_thread_id: accessible_thread_ids)
                          .where(deleted: false)
                          .where('content ILIKE ?', "%#{situation}%")
                          .or(
                            HubMessage.where(hub_thread_id: accessible_thread_ids)
                                     .where(is_handoff: true, handoff_status: 'completed')
                                     .where('content ILIKE ?', "%#{situation}%")
                          )
                          .includes(:hub_thread, :sender)
                          .order(created_at: :desc)
                          .limit(10)

      results.map { |m| format_precedent_result(m) }
    end

    # "What does the team know about X?"
    def gather_context_about(topic, limit: 20)
      accessible_thread_ids = accessible_thread_ids_for(@user)
      
      messages = HubMessage.where(hub_thread_id: accessible_thread_ids)
                           .where(deleted: false)
                           .where('content ILIKE ?', "%#{topic}%")
                           .includes(:hub_thread, :sender)
                           .order(created_at: :desc)
                           .limit(limit)

      {
        topic: topic,
        message_count: messages.size,
        thread_count: messages.pluck(:hub_thread_id).uniq.size,
        first_mentioned: messages.last&.created_at,
        last_mentioned: messages.first&.created_at,
        key_messages: messages.take(10).map { |m| format_context_message(m) },
        participants_involved: extract_participants(messages),
        agents_involved: extract_agents(messages)
      }
    end

    # ============================================
    # AGENT MEMORY
    # ============================================

    # Get context an agent can use when processing a task
    def context_for_agent(agent, topic, limit: 10)
      agent_context = Hub::AgentContextService.new(agent: agent, entity: @entity)
      
      # Only search threads the agent has access to
      agent_thread_ids = agent_context.accessible_threads.pluck(:id)
      
      return [] if agent_thread_ids.empty?

      HubMessage.where(hub_thread_id: agent_thread_ids)
                .where(deleted: false)
                .where('content ILIKE ?', "%#{topic}%")
                .order(created_at: :desc)
                .limit(limit)
                .map(&:as_context_json)
    end

    # ============================================
    # TRENDING & INSIGHTS
    # ============================================

    # What topics are being discussed recently?
    def trending_topics(days: 7, limit: 10)
      accessible_thread_ids = accessible_thread_ids_for(@user)
      since = days.days.ago

      # Simple keyword extraction from recent messages
      messages = HubMessage.where(hub_thread_id: accessible_thread_ids)
                           .where(deleted: false)
                           .where('created_at > ?', since)
                           .pluck(:content)

      extract_topics(messages, limit: limit)
    end

    # Active discussions (threads with recent activity)
    def active_discussions(limit: 10)
      accessible_thread_ids = accessible_thread_ids_for(@user)

      HubThread.where(id: accessible_thread_ids)
               .where('last_activity_at > ?', 7.days.ago)
               .order(last_activity_at: :desc)
               .limit(limit)
               .map do |thread|
        {
          id: thread.id,
          subject: thread.subject || thread.display_name(for_participant: @user),
          thread_type: thread.thread_type,
          message_count: thread.message_count,
          last_activity: thread.last_activity_at,
          participants: thread.participants.map { |p| p.respond_to?(:name) ? p.name : 'Unknown' }
        }
      end
    end

    private

    def accessible_thread_ids_for(user)
      HubParticipant.where(participant: user, left_at: nil)
                    .joins(:hub_thread)
                    .where(hub_threads: { entity: @entity })
                    .pluck(:hub_thread_id)
    end

    def format_search_result(message)
      {
        id: message.id,
        content: message.content.truncate(300),
        sender: message.sender_name,
        sender_type: message.sender_type,
        thread_id: message.hub_thread_id,
        thread_subject: message.hub_thread.subject || message.hub_thread.display_name(for_participant: @user),
        created_at: message.created_at,
        message_type: message.message_type,
        is_handoff: message.is_handoff
      }
    end

    def format_decision_result(message)
      format_search_result(message).merge(
        decision_context: extract_surrounding_context(message, window: 3)
      )
    end

    def format_precedent_result(message)
      format_search_result(message).merge(
        resolution_context: extract_surrounding_context(message, window: 5),
        was_handoff: message.is_handoff,
        handoff_status: message.handoff_status
      )
    end

    def format_context_message(message)
      {
        id: message.id,
        content: message.content.truncate(200),
        sender: message.sender_name,
        from_agent: message.from_agent?,
        created_at: message.created_at
      }
    end

    def extract_surrounding_context(message, window: 3)
      messages = HubMessage.where(hub_thread_id: message.hub_thread_id)
                           .where('id >= ? AND id <= ?', message.id - window, message.id + window)
                           .where(deleted: false)
                           .order(created_at: :asc)

      messages.map do |m|
        {
          sender: m.sender_name,
          content: m.content.truncate(150),
          is_target: m.id == message.id
        }
      end
    end

    def extract_participants(messages)
      messages.select { |m| m.from_user? }
              .map(&:sender_name)
              .uniq
    end

    def extract_agents(messages)
      messages.select { |m| m.from_agent? }
              .map(&:sender_name)
              .uniq
    end

    def extract_topics(messages, limit: 10)
      # Simple word frequency analysis
      # In production, could use NLP for better topic extraction
      
      stop_words = %w[the a an is are was were be been being have has had do does did will would could should may might must shall can and or but if then else when where what which who whom whose how why this that these those it its i you he she we they me him her us them my your his our their mine yours ours theirs]
      
      word_counts = Hash.new(0)
      
      messages.each do |content|
        words = content.downcase.scan(/\b[a-z]{4,}\b/) - stop_words
        words.each { |word| word_counts[word] += 1 }
      end

      word_counts.sort_by { |_, count| -count }
                 .take(limit)
                 .map { |word, count| { topic: word, mentions: count } }
    end
  end
end
