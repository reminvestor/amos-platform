# frozen_string_literal: true

module Hub
  # AgentContextService
  #
  # Provides conversation context to agents while enforcing privacy rules.
  # Agents can ONLY access threads where they are participants.
  # This mirrors how human employees can't see DMs between other employees.
  #
  class AgentContextService
    def initialize(agent:, entity:)
      @agent = agent
      @entity = entity
    end

    # ============================================
    # THREAD ACCESS
    # ============================================

    # Get all threads this agent can access
    def accessible_threads
      HubThread.joins(:hub_participants)
               .where(hub_participants: { 
                 participant_type: 'AgentPlugin',
                 participant_id: @agent.id,
                 left_at: nil
               })
               .where(entity: @entity)
    end

    # Check if agent can access a specific thread
    def can_access_thread?(thread_id)
      accessible_threads.exists?(id: thread_id)
    end

    # Get messages from a thread (respecting join time)
    def thread_context(thread_id, limit: 50)
      return nil unless can_access_thread?(thread_id)

      participant = HubParticipant.find_by(
        hub_thread_id: thread_id,
        participant_type: 'AgentPlugin',
        participant_id: @agent.id
      )

      return nil unless participant

      messages = HubMessage.where(hub_thread_id: thread_id)
                           .where('created_at >= ?', participant.context_access_from || participant.joined_at)
                           .where(deleted: false)
                           .order(created_at: :desc)
                           .limit(limit)
                           .includes(:sender)

      format_messages_for_context(messages.reverse)
    end

    # ============================================
    # CONTEXT BUILDING
    # ============================================

    # Build full context for agent processing
    def build_context(thread_id:, include_participants: true, include_recent_activity: true)
      return nil unless can_access_thread?(thread_id)

      thread = HubThread.find(thread_id)
      participant = thread.hub_participants.find_by(participant: @agent)

      context = {
        thread_id: thread_id,
        thread_type: thread.thread_type,
        subject: thread.subject,
        messages: thread_context(thread_id),
        my_role: participant.role,
        joined_at: participant.joined_at.iso8601
      }

      if include_participants
        context[:participants] = thread.hub_participants.active.map do |hp|
          {
            id: hp.participant_id,
            type: hp.participant_type,
            name: hp.participant.respond_to?(:name) ? hp.participant.name : 'Unknown',
            role: hp.role,
            is_me: hp.participant == @agent
          }
        end
      end

      if include_recent_activity
        context[:recent_activity] = recent_thread_activity(thread)
      end

      context
    end

    # Get context for responding to a specific message
    def context_for_response(message_id:)
      message = HubMessage.find_by(id: message_id)
      return nil unless message

      thread_id = message.hub_thread_id
      return nil unless can_access_thread?(thread_id)

      {
        responding_to: {
          id: message.id,
          sender_name: message.sender_name,
          content: message.content,
          message_type: message.message_type,
          needs_response: message.needs_response
        },
        thread_context: build_context(thread_id: thread_id)
      }
    end

    # ============================================
    # SEARCH & DISCOVERY
    # ============================================

    # Search across accessible threads
    def search_context(query, limit: 10)
      accessible_thread_ids = accessible_threads.pluck(:id)
      return [] if accessible_thread_ids.empty?

      HubMessage.where(hub_thread_id: accessible_thread_ids)
                .where(deleted: false)
                .where('content ILIKE ?', "%#{query}%")
                .order(created_at: :desc)
                .limit(limit)
                .map { |m| m.as_context_json.merge(thread_id: m.hub_thread_id) }
    end

    # Find threads where a specific topic was discussed
    def threads_about(topic)
      accessible_thread_ids = accessible_threads.pluck(:id)
      
      HubMessage.where(hub_thread_id: accessible_thread_ids)
                .where(deleted: false)
                .where('content ILIKE ?', "%#{topic}%")
                .select(:hub_thread_id)
                .distinct
                .pluck(:hub_thread_id)
    end

    # Get threads with pending responses needed
    def threads_needing_response
      accessible_threads
        .joins(:hub_messages)
        .where(hub_messages: { needs_response: true, sender_type: 'User' })
        .distinct
    end

    # ============================================
    # AGENT COMMUNICATION
    # ============================================

    # Send a message to a thread (if agent is participant)
    def send_message(thread_id:, content:, message_type: 'text', **options)
      return { error: 'Not authorized' } unless can_access_thread?(thread_id)

      thread = HubThread.find(thread_id)
      
      message = thread.add_message(
        sender: @agent,
        content: content,
        message_type: message_type,
        **options
      )

      { success: true, message_id: message.id }
    rescue => e
      { error: e.message }
    end

    # Start a new thread with a user
    def start_thread_with(user, subject: nil, initial_message: nil, thread_type: HubThread::DM)
      thread = if thread_type == HubThread::DM
                 HubThread.find_or_create_dm(
                   entity: @entity,
                   participants: [user, @agent]
                 )
               else
                 HubThread.create!(
                   entity: @entity,
                   started_by: @agent,
                   thread_type: thread_type,
                   subject: subject
                 ).tap do |t|
                   t.add_participant(user, role: 'member')
                 end
               end

      if initial_message.present?
        send_message(thread_id: thread.id, content: initial_message)
      end

      thread
    end

    # Request handoff to human
    def request_handoff(thread_id:, to_user:, summary:, completed_items: [], needed_items: [], next_steps: [])
      return { error: 'Not authorized' } unless can_access_thread?(thread_id)

      thread = HubThread.find(thread_id)
      
      # Make sure the user is a participant
      thread.add_participant(to_user, role: 'member') unless thread.participant?(to_user)

      message = thread.create_handoff_request(
        from_agent: @agent,
        to_user: to_user,
        summary: summary,
        completed_items: completed_items,
        needed_items: needed_items,
        next_steps: next_steps
      )

      # Notify the user
      HubChannel.broadcast_handoff(to_user.id, message)

      { success: true, message_id: message.id }
    end

    private

    def format_messages_for_context(messages)
      messages.map do |msg|
        {
          id: msg.id,
          role: msg.from_agent? ? 'assistant' : 'user',
          sender_type: msg.sender_type,
          sender_name: msg.sender_name,
          sender_id: msg.sender_id,
          content: msg.content,
          message_type: msg.message_type,
          created_at: msg.created_at.iso8601,
          needs_response: msg.needs_response,
          is_handoff: msg.is_handoff,
          metadata: msg.metadata
        }
      end
    end

    def recent_thread_activity(thread)
      {
        last_activity: thread.last_activity_at&.iso8601,
        message_count: thread.message_count,
        pending_responses: thread.hub_messages.pending_responses.count,
        active_handoffs: thread.hub_messages.handoffs.where(handoff_status: 'pending').count
      }
    end
  end
end
