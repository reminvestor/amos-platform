# frozen_string_literal: true

module Hub
  # NotificationQueueService
  #
  # Smart notification queue that prioritizes what the user needs to see.
  # Merges Hub messages, agent questions, and work items into a unified queue.
  #
  class NotificationQueueService
    # Priority weights for different notification types
    PRIORITY_WEIGHTS = {
      'decision_blocking' => 100,   # Agent can't continue without this
      'handoff_critical' => 90,     # Critical urgency handoff
      'handoff_high' => 80,         # High urgency handoff
      'approval_needed' => 70,      # Work ready for review
      'question' => 60,             # Agent question
      'mention' => 50,              # User was @mentioned
      'handoff_normal' => 40,       # Normal handoff
      'work_completed' => 30,       # Agent finished something
      'fyi' => 10                   # Informational
    }.freeze

    # Age decay: older items get boosted priority
    AGE_BOOST_PER_HOUR = 2
    MAX_AGE_BOOST = 20

    def initialize(entity:, user:)
      @entity = entity
      @user = user
    end

    # Get the unified notification queue
    def queue(limit: 20)
      items = []

      # Gather all notification sources
      items.concat(gather_pending_handoffs)
      items.concat(gather_pending_questions)
      items.concat(gather_hub_mentions)
      items.concat(gather_work_items)

      # Score and sort
      scored_items = items.map { |item| score_item(item) }
      sorted_items = scored_items.sort_by { |item| -item[:score] }

      sorted_items.take(limit)
    end

    # Get grouped queue (by category)
    def grouped_queue
      items = queue(limit: 50)

      {
        urgent: items.select { |i| i[:priority_level] == 'urgent' },
        needs_action: items.select { |i| i[:priority_level] == 'action_required' },
        fyi: items.select { |i| i[:priority_level] == 'fyi' },
        counts: {
          urgent: items.count { |i| i[:priority_level] == 'urgent' },
          action_required: items.count { |i| i[:priority_level] == 'action_required' },
          fyi: items.count { |i| i[:priority_level] == 'fyi' },
          total: items.size
        }
      }
    end

    # Get count by priority
    def counts
      {
        urgent: count_urgent,
        action_required: count_action_required,
        total: count_total
      }
    end

    # Mark an item as handled
    def dismiss(item_type:, item_id:)
      case item_type
      when 'handoff'
        # Handoff is handled through normal handoff flow
        { success: true }
      when 'question'
        request = AgentInputRequest.find_by(id: item_id)
        request&.skip!(reason: 'dismissed_from_queue')
        { success: true }
      when 'work_item'
        item = AgentWorkItem.find_by(id: item_id)
        item&.mark_as_read!
        { success: true }
      when 'hub_message'
        message = HubMessage.find_by(id: item_id)
        if message
          participant = message.hub_thread.hub_participants.find_by(participant: @user)
          participant&.mark_read!
        end
        { success: true }
      else
        { success: false, error: 'Unknown item type' }
      end
    end

    private

    def gather_pending_handoffs
      HubMessage.joins(:hub_thread)
               .joins("INNER JOIN hub_participants ON hub_participants.hub_thread_id = hub_threads.id")
               .where(hub_participants: { participant_type: 'User', participant_id: @user.id })
               .where(hub_threads: { entity: @entity })
               .where(is_handoff: true, handoff_status: 'pending')
               .includes(sender: [], hub_thread: [])
               .map do |msg|
        urgency = msg.metadata['urgency'] || 'normal'
        {
          type: 'handoff',
          id: msg.id,
          title: "#{msg.sender_name} needs your input",
          body: msg.content.truncate(150),
          agent_name: msg.sender_name,
          agent_id: msg.sender_id,
          urgency: urgency,
          priority_type: "handoff_#{urgency}",
          thread_id: msg.hub_thread_id,
          action_url: "/hub/thread/#{msg.hub_thread_id}",
          actions: ['approve', 'review', 'discuss'],
          created_at: msg.created_at,
          icon: '🔄'
        }
      end
    end

    def gather_pending_questions
      AgentInputRequest.pending
                       .joins(:agent_plugin_execution)
                       .where(agent_plugin_executions: { user_id: @user.id })
                       .includes(agent_plugin_execution: :agent_plugin)
                       .map do |req|
        execution = req.agent_plugin_execution
        is_blocking = execution&.status == 'waiting_for_input'
        
        {
          type: 'question',
          id: req.id,
          title: req.display_agent_name,
          body: req.question.truncate(150),
          agent_name: req.display_agent_name,
          agent_id: execution&.agent_plugin_id,
          urgency: is_blocking ? 'high' : 'normal',
          priority_type: is_blocking ? 'decision_blocking' : 'question',
          execution_id: execution&.id,
          action_url: "/scout?show_question=#{req.id}",
          actions: ['answer', 'skip'],
          created_at: req.created_at,
          icon: '❓'
        }
      end
    end

    def gather_hub_mentions
      # Find messages where user was mentioned but hasn't read
      @user.hub_participations
          .joins(:hub_thread)
          .where(hub_threads: { entity: @entity })
          .where('hub_participants.unread_count > 0')
          .includes(hub_thread: :hub_messages)
          .flat_map do |participant|
        participant.hub_thread.hub_messages
                   .where('created_at > ?', participant.last_read_at || Time.at(0))
                   .where("metadata->'mentions' @> ?", [@user.id].to_json)
                   .map do |msg|
          {
            type: 'mention',
            id: msg.id,
            title: "#{msg.sender_name} mentioned you",
            body: msg.content.truncate(150),
            sender_name: msg.sender_name,
            sender_id: msg.sender_id,
            sender_type: msg.sender_type,
            urgency: 'normal',
            priority_type: 'mention',
            thread_id: msg.hub_thread_id,
            action_url: "/hub/thread/#{msg.hub_thread_id}#message-#{msg.id}",
            actions: ['view', 'reply'],
            created_at: msg.created_at,
            icon: '@'
          }
        end
      end
    end

    def gather_work_items
      AgentWorkItem.for_entity(@entity)
                   .for_user(@user)
                   .not_archived
                   .unread
                   .requiring_action
                   .recent
                   .limit(20)
                   .includes(:agent_plugin)
                   .map do |item|
        urgency = item.priority == 'urgent' ? 'high' : 'normal'
        
        {
          type: 'work_item',
          id: item.id,
          title: item.title,
          body: item.summary&.truncate(150),
          agent_name: item.agent_name,
          agent_id: item.agent_plugin_id,
          urgency: urgency,
          priority_type: item.requires_action ? 'approval_needed' : 'work_completed',
          work_type: item.work_type,
          action_url: "/scout?view=inbox&item_id=#{item.id}",
          actions: item.requires_action ? ['view', 'acknowledge'] : ['view'],
          created_at: item.created_at,
          icon: item.icon
        }
      end
    end

    def score_item(item)
      base_score = PRIORITY_WEIGHTS[item[:priority_type]] || 10

      # Age boost: older items get priority boost
      age_hours = (Time.current - item[:created_at]) / 1.hour
      age_boost = [age_hours * AGE_BOOST_PER_HOUR, MAX_AGE_BOOST].min

      # Urgency multiplier
      urgency_multiplier = case item[:urgency]
                           when 'critical' then 2.0
                           when 'high' then 1.5
                           else 1.0
                           end

      score = (base_score + age_boost) * urgency_multiplier

      # Determine priority level for grouping
      priority_level = if score >= 80
                         'urgent'
                       elsif item[:priority_type].in?(%w[decision_blocking approval_needed question handoff_high handoff_critical])
                         'action_required'
                       else
                         'fyi'
                       end

      item.merge(
        score: score.round(2),
        priority_level: priority_level
      )
    end

    def count_urgent
      gather_pending_handoffs.count { |h| h[:urgency].in?(%w[critical high]) } +
        gather_pending_questions.count { |q| q[:priority_type] == 'decision_blocking' }
    end

    def count_action_required
      gather_pending_handoffs.size +
        gather_pending_questions.size +
        AgentWorkItem.for_entity(@entity).for_user(@user).not_archived.requiring_action.count
    end

    def count_total
      gather_pending_handoffs.size +
        gather_pending_questions.size +
        AgentWorkItem.for_entity(@entity).for_user(@user).not_archived.unread.count +
        @user.hub_participations.joins(:hub_thread).where(hub_threads: { entity: @entity }).sum(:unread_count)
    end
  end
end
