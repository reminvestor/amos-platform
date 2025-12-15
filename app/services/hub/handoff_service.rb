# frozen_string_literal: true

module Hub
  # HandoffService
  #
  # Manages the formal handoff protocol between agents and humans.
  # This is the structured way agents transfer work/decisions to humans
  # and receive work back.
  #
  class HandoffService
    def initialize(entity:)
      @entity = entity
    end

    # ============================================
    # AGENT → HUMAN HANDOFFS
    # ============================================

    # Agent requests human to take action
    def request_handoff(
      from_agent:,
      to_user:,
      summary:,
      completed_items: [],
      needed_items: [],
      next_steps: [],
      urgency: 'normal',
      thread: nil,
      execution: nil
    )
      # Find or create thread for this handoff
      thread ||= find_or_create_handoff_thread(from_agent, to_user, execution)

      # Create the handoff message
      message = thread.add_message(
        sender: from_agent,
        content: build_handoff_content(summary, completed_items, needed_items, next_steps),
        message_type: HubMessage::HANDOFF_REQUEST,
        is_handoff: true,
        handoff_status: 'pending',
        needs_response: true,
        agent_plugin_execution: execution,
        metadata: {
          completed_items: completed_items,
          needed_items: needed_items,
          next_steps: next_steps,
          urgency: urgency,
          requested_at: Time.current.iso8601
        },
        actions: handoff_actions(urgency)
      )

      # Update agent presence
      update_agent_presence(from_agent, 'waiting', "Waiting for #{to_user.name}'s response")

      # Create notification
      create_handoff_notification(to_user, from_agent, message, urgency)

      # Broadcast to user
      HubChannel.broadcast_handoff(to_user.id, message)

      {
        success: true,
        message_id: message.id,
        thread_id: thread.id
      }
    end

    # Agent asks a question (simpler handoff)
    def ask_question(
      from_agent:,
      to_user:,
      question:,
      context: {},
      thread: nil,
      execution: nil
    )
      thread ||= find_or_create_handoff_thread(from_agent, to_user, execution)

      message = thread.add_message(
        sender: from_agent,
        content: question,
        message_type: HubMessage::QUESTION,
        needs_response: true,
        agent_plugin_execution: execution,
        metadata: { context: context },
        actions: [
          { id: 'respond', label: 'Respond', style: 'primary' },
          { id: 'skip', label: 'Skip', style: 'secondary' }
        ]
      )

      update_agent_presence(from_agent, 'waiting', "Waiting for your answer")

      {
        success: true,
        message_id: message.id,
        thread_id: thread.id
      }
    end

    # ============================================
    # HUMAN → AGENT HANDOFFS
    # ============================================

    # Human accepts a handoff and provides response
    def accept_handoff(message_id:, by_user:, response: nil)
      message = HubMessage.find(message_id)
      
      return { error: 'Not a handoff message' } unless message.is_handoff?
      return { error: 'Handoff already processed' } unless message.handoff_status == 'pending'

      message.accept_handoff!(by_user)

      if response.present?
        # Add response message
        message.hub_thread.add_message(
          sender: by_user,
          content: response,
          message_type: HubMessage::TEXT,
          reply_to: message
        )
      end

      # Update agent presence - they can continue now
      agent = message.sender
      update_agent_presence(agent, 'online') if agent.is_a?(AgentPlugin)

      # Resume agent execution if linked
      if message.agent_input_request.present?
        message.agent_input_request.answer!(response || "Handoff accepted")
      end

      { success: true, status: 'accepted' }
    end

    # Human completes a handoff (after reviewing/approving work)
    def complete_handoff(message_id:, by_user:, feedback: nil, rating: nil)
      message = HubMessage.find(message_id)
      
      return { error: 'Not a handoff message' } unless message.is_handoff?
      return { error: 'Handoff not accepted yet' } unless message.handoff_status == 'accepted'

      message.complete_handoff!(by_user, feedback: feedback)

      # Record feedback for agent learning
      if rating.present?
        agent = message.sender
        record_handoff_feedback(agent, message, rating, feedback) if agent.is_a?(AgentPlugin)
      end

      # Post completion message
      message.hub_thread.add_message(
        sender: by_user,
        content: feedback.present? ? "✅ Completed with feedback: #{feedback}" : "✅ Handoff completed",
        message_type: HubMessage::HANDOFF_COMPLETE,
        metadata: { rating: rating }
      )

      { success: true, status: 'completed' }
    end

    # Human delegates work to an agent
    def delegate_to_agent(
      from_user:,
      to_agent:,
      task_description:,
      context: {},
      priority: 'normal',
      thread: nil
    )
      thread ||= find_or_create_handoff_thread(to_agent, from_user, nil)

      # Create message from user
      message = thread.add_message(
        sender: from_user,
        content: task_description,
        message_type: HubMessage::TEXT,
        metadata: { 
          is_delegation: true,
          priority: priority,
          context: context 
        }
      )

      # Create agent execution
      execution = AgentPluginExecution.create!(
        agent_plugin: to_agent,
        user: from_user,
        entity: @entity,
        status: 'pending',
        input_context: {
          task: task_description,
          context: context,
          priority: priority,
          hub_thread_id: thread.id,
          hub_message_id: message.id
        }
      )

      # Link thread to execution
      thread.update!(agent_plugin_execution: execution)

      # Queue the execution
      AgentPluginExecutionJob.perform_later(
        execution.id,
        task_description,
        {
          entity_id: @entity.id,
          user_id: from_user.id,
          hub_thread_id: thread.id,
          context: context
        }
      )

      # Update agent presence
      update_agent_presence(to_agent, 'working', "Working on: #{task_description.truncate(50)}", execution: execution)

      # Agent acknowledges
      thread.add_message(
        sender: to_agent,
        content: "Got it! I'm starting work on this now. I'll update you on my progress.",
        message_type: HubMessage::STATUS_UPDATE
      )

      { success: true, execution_id: execution.id, thread_id: thread.id }
    end

    # ============================================
    # HANDOFF STATUS QUERIES
    # ============================================

    # Get pending handoffs for a user
    def pending_handoffs_for(user)
      HubMessage.joins(:hub_thread)
                .joins("INNER JOIN hub_participants ON hub_participants.hub_thread_id = hub_threads.id")
                .where(hub_participants: { participant_type: 'User', participant_id: user.id })
                .where(hub_threads: { entity: @entity })
                .where(is_handoff: true, handoff_status: 'pending')
                .order(created_at: :desc)
    end

    # Get pending questions for a user
    def pending_questions_for(user)
      HubMessage.joins(:hub_thread)
                .joins("INNER JOIN hub_participants ON hub_participants.hub_thread_id = hub_threads.id")
                .where(hub_participants: { participant_type: 'User', participant_id: user.id })
                .where(hub_threads: { entity: @entity })
                .where(needs_response: true, message_type: HubMessage::QUESTION)
                .order(created_at: :desc)
    end

    # Get active agent work for a user (what agents are doing on their behalf)
    def active_agent_work_for(user)
      AgentPluginExecution.joins(:hub_thread)
                          .joins("INNER JOIN hub_participants ON hub_participants.hub_thread_id = hub_threads.id")
                          .where(hub_participants: { participant_type: 'User', participant_id: user.id })
                          .where(status: ['pending', 'running'])
                          .includes(:agent_plugin, :hub_thread)
                          .order(started_at: :desc)
    end

    private

    def find_or_create_handoff_thread(agent, user, execution)
      # Check if there's an existing thread for this execution
      if execution&.hub_thread.present?
        return execution.hub_thread
      end

      # Create a new handoff thread
      thread = HubThread.create!(
        entity: @entity,
        started_by: agent,
        thread_type: HubThread::AGENT_HANDOFF,
        subject: "Handoff from #{agent.name}",
        agent_plugin_execution: execution
      )

      thread.add_participant(user, role: 'member')
      
      thread
    end

    def build_handoff_content(summary, completed_items, needed_items, next_steps)
      parts = [summary]
      
      if completed_items.any?
        parts << ""
        parts << "**✅ Completed:**"
        completed_items.each { |item| parts << "• #{item}" }
      end

      if needed_items.any?
        parts << ""
        parts << "**❓ Need from you:**"
        needed_items.each { |item| parts << "• #{item}" }
      end

      if next_steps.any?
        parts << ""
        parts << "**⏭️ Next steps (after your input):**"
        next_steps.each { |item| parts << "• #{item}" }
      end

      parts.join("\n")
    end

    def handoff_actions(urgency)
      actions = [
        { id: 'approve', label: 'Approve All', style: 'primary' },
        { id: 'review', label: 'Review Details', style: 'secondary' },
        { id: 'discuss', label: 'Discuss', style: 'secondary' }
      ]

      if urgency == 'critical'
        actions.unshift({ id: 'urgent_approve', label: '🚨 Approve Now', style: 'danger' })
      end

      actions
    end

    def update_agent_presence(agent, status, activity = nil, execution: nil)
      presence = HubPresence.for_participant(agent)
      
      case status
      when 'online'
        presence.finish_work!
      when 'working'
        presence.start_working!(activity: activity, execution: execution)
      when 'waiting'
        presence.waiting_for_human!(reason: activity)
      end
    end

    def create_handoff_notification(user, agent, message, urgency)
      priority = case urgency
                 when 'critical' then 'urgent'
                 when 'high' then 'high'
                 else 'normal'
                 end

      UserNotification.create!(
        entity: @entity,
        user: user,
        notification_type: 'handoff_request',
        title: "#{agent.name} needs your input",
        body: message.content.truncate(200),
        icon: '🔄',
        channel: 'in_app',
        priority: priority,
        action_url: "/hub/thread/#{message.hub_thread_id}",
        action_type: 'respond',
        metadata: {
          message_id: message.id,
          agent_id: agent.id,
          urgency: urgency
        }
      )
    end

    def record_handoff_feedback(agent, message, rating, feedback)
      # Record for agent learning system
      if agent.respond_to?(:energy_state) && agent.energy_state.present?
        # Use existing energy/reward system
        reward = case rating
                 when 5 then 10
                 when 4 then 5
                 when 3 then 0
                 when 2 then -5
                 when 1 then -10
                 else 0
                 end

        agent.energy_state.earn!(reward, reason: 'handoff_feedback', request: nil) if reward != 0
      end

      # Store feedback for analytics
      message.update!(
        metadata: message.metadata.merge(
          feedback_rating: rating,
          feedback_text: feedback,
          feedback_at: Time.current.iso8601
        )
      )
    end
  end
end
