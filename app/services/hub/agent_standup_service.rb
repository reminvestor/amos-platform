# frozen_string_literal: true

module Hub
  # AgentStandupService
  #
  # Generates daily standup summaries of agent activity.
  # "Good morning! Here's what happened while you were away..."
  #
  class AgentStandupService
    def initialize(entity:, user:)
      @entity = entity
      @user = user
    end

    # Generate a standup summary
    def generate_standup(since: nil)
      since ||= @user.last_standup_at || 24.hours.ago

      {
        generated_at: Time.current.iso8601,
        period: {
          from: since.iso8601,
          to: Time.current.iso8601
        },
        summary: build_summary(since),
        completed_work: completed_work(since),
        pending_items: pending_items,
        agent_activity: agent_activity_summary(since),
        highlights: build_highlights(since),
        action_items: action_items
      }
    end

    # Get a quick overview (for notifications)
    def quick_overview
      pending_count = pending_items.sum { |i| i[:count] }
      completed_count = completed_work_count(24.hours.ago)

      if pending_count.positive?
        "#{pending_count} items need your attention. #{completed_count} tasks completed by agents."
      elsif completed_count.positive?
        "#{completed_count} tasks completed by agents since yesterday."
      else
        "All caught up! Your agents are standing by."
      end
    end

    # Format standup as a message for the Hub
    def as_hub_message
      standup = generate_standup
      
      parts = []
      parts << "## 🌅 Good #{time_of_day}! Here's your standup:\n"
      
      # Highlights
      if standup[:highlights].any?
        parts << "### ✨ Highlights"
        standup[:highlights].each { |h| parts << "• #{h}" }
        parts << ""
      end

      # Pending items
      if standup[:pending_items].any? { |i| i[:count].positive? }
        parts << "### ⚠️ Needs Your Attention"
        standup[:pending_items].each do |item|
          next if item[:count].zero?
          parts << "• **#{item[:count]}** #{item[:label]}"
        end
        parts << ""
      end

      # Completed work
      if standup[:completed_work].any?
        parts << "### ✅ Completed by Agents"
        standup[:completed_work].take(5).each do |work|
          parts << "• #{work[:agent_name]}: #{work[:title]}"
        end
        if standup[:completed_work].size > 5
          parts << "_...and #{standup[:completed_work].size - 5} more_"
        end
        parts << ""
      end

      # Agent status
      active_agents = standup[:agent_activity][:currently_working]
      if active_agents.any?
        parts << "### 🤖 Agents Currently Working"
        active_agents.each do |agent|
          parts << "• **#{agent[:name]}**: #{agent[:activity] || 'Working...'}"
        end
        parts << ""
      end

      # Action items
      if standup[:action_items].any?
        parts << "### 📋 Action Items"
        standup[:action_items].take(5).each do |item|
          parts << "• #{item[:title]} — _#{item[:agent_name]}_"
        end
      end

      parts.join("\n")
    end

    private

    def build_summary(since)
      work_items = AgentWorkItem.for_entity(@entity)
                                .where('created_at > ?', since)
      
      {
        total_work_items: work_items.count,
        requiring_action: work_items.requiring_action.count,
        agents_active: HubPresence.for_entity(@entity).agents.online.count,
        hub_messages: HubMessage.joins(:hub_thread)
                                .where(hub_threads: { entity: @entity })
                                .where('hub_messages.created_at > ?', since)
                                .count
      }
    end

    def completed_work(since)
      AgentWorkItem.for_entity(@entity)
                   .for_user(@user)
                   .where('created_at > ?', since)
                   .where.not(work_type: 'action_required')
                   .order(created_at: :desc)
                   .limit(20)
                   .map do |item|
        {
          id: item.id,
          title: item.title,
          summary: item.summary,
          work_type: item.work_type,
          agent_name: item.agent_name,
          icon: item.icon,
          created_at: item.created_at.iso8601
        }
      end
    end

    def completed_work_count(since)
      AgentWorkItem.for_entity(@entity)
                   .for_user(@user)
                   .where('created_at > ?', since)
                   .where.not(work_type: 'action_required')
                   .count
    end

    def pending_items
      [
        {
          type: 'handoffs',
          label: 'handoffs waiting for you',
          count: HubMessage.joins(:hub_thread)
                          .joins("INNER JOIN hub_participants ON hub_participants.hub_thread_id = hub_threads.id")
                          .where(hub_participants: { participant_type: 'User', participant_id: @user.id })
                          .where(hub_threads: { entity: @entity })
                          .where(is_handoff: true, handoff_status: 'pending')
                          .count
        },
        {
          type: 'questions',
          label: 'questions from agents',
          count: AgentInputRequest.pending
                                  .joins(:agent_plugin_execution)
                                  .where(agent_plugin_executions: { user_id: @user.id })
                                  .count
        },
        {
          type: 'work_items',
          label: 'work items requiring action',
          count: AgentWorkItem.for_entity(@entity)
                             .for_user(@user)
                             .requiring_action
                             .not_archived
                             .count
        },
        {
          type: 'unread_messages',
          label: 'unread Hub messages',
          count: @user.hub_participations
                     .joins(:hub_thread)
                     .where(hub_threads: { entity: @entity })
                     .sum(:unread_count)
        }
      ]
    end

    def agent_activity_summary(since)
      presences = HubPresence.for_entity(@entity).agents.includes(:participant)

      {
        total_agents: AgentPlugin.active.for_entity(@entity).count,
        currently_online: presences.online.count,
        currently_working: presences.working.map do |p|
          {
            id: p.participant_id,
            name: p.participant.name,
            status: p.status,
            activity: p.current_activity,
            progress: p.activity_progress
          }
        end,
        waiting_on_human: presences.waiting_on_human.map do |p|
          {
            id: p.participant_id,
            name: p.participant.name,
            reason: p.current_activity
          }
        end,
        executions_since: AgentPluginExecution.joins(:agent_plugin)
                                              .where(agent_plugins: { entity_id: @entity.id })
                                              .where('started_at > ?', since)
                                              .count
      }
    end

    def build_highlights(since)
      highlights = []

      # High-value completions
      high_value = AgentWorkItem.for_entity(@entity)
                                .for_user(@user)
                                .where('created_at > ?', since)
                                .where(priority: ['high', 'urgent'])
                                .limit(3)

      high_value.each do |item|
        highlights << "#{item.icon} #{item.agent_name} completed: #{item.title}"
      end

      # Significant collaborations
      collabs = AgentCollaborationRequest.where(entity: @entity)
                                         .completed
                                         .where('completed_at > ?', since)
                                         .limit(2)

      collabs.each do |collab|
        highlights << "🤝 #{collab.requesting_agent&.name} collaborated with #{collab.helper_agent&.name}"
      end

      highlights.take(5)
    end

    def action_items
      items = []

      # Pending handoffs
      HubMessage.joins(:hub_thread)
               .joins("INNER JOIN hub_participants ON hub_participants.hub_thread_id = hub_threads.id")
               .where(hub_participants: { participant_type: 'User', participant_id: @user.id })
               .where(hub_threads: { entity: @entity })
               .where(is_handoff: true, handoff_status: 'pending')
               .order(created_at: :asc)
               .limit(5)
               .each do |msg|
        items << {
          type: 'handoff',
          title: msg.content.truncate(80),
          agent_name: msg.sender_name,
          thread_id: msg.hub_thread_id,
          created_at: msg.created_at.iso8601
        }
      end

      # Pending questions
      AgentInputRequest.pending
                       .joins(:agent_plugin_execution)
                       .where(agent_plugin_executions: { user_id: @user.id })
                       .order(created_at: :asc)
                       .limit(5)
                       .each do |req|
        items << {
          type: 'question',
          title: req.question.truncate(80),
          agent_name: req.display_agent_name,
          request_id: req.id,
          created_at: req.created_at.iso8601
        }
      end

      items.take(10)
    end

    def time_of_day
      hour = Time.current.hour
      case hour
      when 5..11 then 'morning'
      when 12..16 then 'afternoon'
      when 17..20 then 'evening'
      else 'day'
      end
    end
  end
end
