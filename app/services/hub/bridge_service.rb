# frozen_string_literal: true

module Hub
  # BridgeService
  #
  # Bridges existing agent systems to the Hub:
  # - AgentInputRequest → Hub messages with needs_response
  # - AgentPluginExecution → Hub presence/activity updates
  # - AgentWorkItem → Hub thread notifications
  # - AgentCollaborationRequest → Agent-to-agent visible in Hub
  #
  class BridgeService
    def initialize(entity:)
      @entity = entity
    end

    # ============================================
    # AGENT INPUT REQUEST → HUB
    # ============================================

    # When an agent asks a user a question via AskUserTool
    def handle_input_request(input_request)
      agent = input_request.agent_plugin_execution&.agent_plugin
      user = input_request.agent_plugin_execution&.user
      
      return unless agent && user

      # Find or create a DM thread between agent and user
      thread = find_or_create_agent_user_thread(agent, user)

      # Add the question as a Hub message
      message = thread.add_message(
        sender: agent,
        content: input_request.question,
        message_type: HubMessage::QUESTION,
        needs_response: true,
        agent_input_request: input_request,
        agent_plugin_execution: input_request.agent_plugin_execution,
        metadata: {
          variable_name: input_request.variable_name,
          context: input_request.context_data,
          priority: input_request.priority
        }
      )

      # Update agent presence to waiting
      update_agent_presence(agent, :waiting, "Waiting for your response")

      message
    end

    # When a user answers an input request
    def handle_input_response(input_request, response_content)
      return unless input_request.hub_message.present?

      message = input_request.hub_message
      user = input_request.agent_plugin_execution&.user

      # The response is handled by HubMessage#respond!
      message.respond!(response_content, by: user) if user
    end

    # ============================================
    # AGENT EXECUTION → HUB
    # ============================================

    # When an agent starts working
    def handle_execution_started(execution)
      agent = execution.agent_plugin
      user = execution.user
      return unless agent && user

      # Update presence
      update_agent_presence(
        agent, 
        :working,
        execution.input_context&.dig('task')&.truncate(100) || "Working on task",
        execution: execution
      )

      # If there's an associated thread, post a status update
      if execution.hub_thread.present?
        execution.hub_thread.add_message(
          sender: agent,
          content: "Started working on: #{execution.input_context&.dig('task')&.truncate(100)}",
          message_type: HubMessage::STATUS_UPDATE
        )
      end
    end

    # When an agent completes work
    def handle_execution_completed(execution)
      agent = execution.agent_plugin
      return unless agent

      # Update presence
      update_agent_presence(agent, :online)

      # Post completion to thread if exists
      if execution.hub_thread.present?
        execution.hub_thread.add_message(
          sender: agent,
          content: "Completed: #{execution.input_context&.dig('task')&.truncate(100)}",
          message_type: HubMessage::STATUS_UPDATE,
          metadata: {
            execution_id: execution.id,
            duration_ms: execution.duration_ms,
            status: execution.status
          }
        )
      end
    end

    # When an agent fails
    def handle_execution_failed(execution, error)
      agent = execution.agent_plugin
      return unless agent

      # Update presence
      update_agent_presence(agent, :online)

      # Post failure to thread if exists
      if execution.hub_thread.present?
        execution.hub_thread.add_message(
          sender: agent,
          content: "I ran into an issue: #{error.to_s.truncate(200)}",
          message_type: HubMessage::STATUS_UPDATE,
          metadata: {
            execution_id: execution.id,
            error: error.to_s
          }
        )
      end
    end

    # Progress update during execution
    def handle_execution_progress(execution, progress, activity = nil)
      agent = execution.agent_plugin
      return unless agent

      presence = HubPresence.for_participant(agent)
      presence.update_progress!(progress, activity: activity)
    end

    # ============================================
    # WORK ITEM → HUB
    # ============================================

    # When a work item is created (agent completed something)
    def handle_work_item_created(work_item)
      agent = work_item.agent_plugin
      user = work_item.user
      return unless user

      # Find the appropriate thread or create one
      thread = if work_item.agent_plugin_execution&.hub_thread.present?
                 work_item.agent_plugin_execution.hub_thread
               elsif agent
                 find_or_create_agent_user_thread(agent, user)
               else
                 nil
               end

      return unless thread

      # Create a message about the work item
      message_content = build_work_item_message(work_item)
      message_type = work_item.requires_action ? HubMessage::HANDOFF_REQUEST : HubMessage::STATUS_UPDATE

      thread.add_message(
        sender: agent || SystemSender.instance,
        content: message_content,
        message_type: message_type,
        needs_response: work_item.requires_action,
        metadata: {
          work_item_id: work_item.id,
          work_type: work_item.work_type,
          asset_type: work_item.asset_type,
          asset_id: work_item.asset_id
        },
        actions: work_item.requires_action ? [
          { id: 'view', label: 'View Details', style: 'primary' },
          { id: 'acknowledge', label: 'Got It', style: 'secondary' }
        ] : []
      )
    end

    # ============================================
    # AGENT COLLABORATION → HUB
    # ============================================

    # When one agent asks another for help
    def handle_collaboration_request(collab_request)
      requester = collab_request.requesting_agent
      helper = collab_request.helper_agent
      
      return unless requester && helper

      # Create a work stream thread for this collaboration
      thread = HubThread.create!(
        entity: @entity,
        started_by: requester,
        thread_type: HubThread::WORK_STREAM,
        subject: "Collaboration: #{collab_request.request_type.titleize}"
      )

      thread.add_participant(helper, role: 'member')

      # Post the request
      thread.add_message(
        sender: requester,
        content: build_collaboration_message(collab_request),
        message_type: HubMessage::TEXT,
        metadata: {
          collaboration_request_id: collab_request.id,
          request_type: collab_request.request_type,
          urgency: collab_request.urgency
        }
      )

      # Broadcast to entity activity feed
      HubChannel.broadcast_agent_activity(@entity.id, {
        type: 'agent_collaboration',
        requester: { id: requester.id, name: requester.name },
        helper: { id: helper.id, name: helper.name },
        request_type: collab_request.request_type,
        thread_id: thread.id
      })
    end

    # ============================================
    # HELPER METHODS
    # ============================================

    private

    def find_or_create_agent_user_thread(agent, user)
      HubThread.find_or_create_dm(
        entity: @entity,
        participants: [user, agent]
      )
    end

    def update_agent_presence(agent, status, activity = nil, execution: nil)
      presence = HubPresence.for_participant(agent)
      
      case status
      when :online
        presence.finish_work!
      when :working
        presence.start_working!(activity: activity, execution: execution)
      when :thinking
        presence.start_thinking!(activity: activity)
      when :waiting
        presence.waiting_for_human!(reason: activity)
      end
    end

    def build_work_item_message(work_item)
      case work_item.work_type
      when 'task_completed'
        "✅ I've completed: #{work_item.title}"
      when 'report_generated'
        "📊 Your report is ready: #{work_item.title}"
      when 'action_required'
        "⚠️ I need your input: #{work_item.title}\n\n#{work_item.summary}"
      when 'analysis_completed'
        "📈 Analysis complete: #{work_item.title}\n\n#{work_item.summary}"
      when 'email_drafted'
        "✉️ I've drafted an email: #{work_item.title}"
      else
        "#{work_item.icon} #{work_item.title}"
      end
    end

    def build_collaboration_message(collab_request)
      parts = []
      parts << "Hey #{collab_request.helper_agent.name}! I could use your help."
      parts << ""
      parts << "**Request type:** #{collab_request.request_type.titleize}"
      parts << "**Urgency:** #{collab_request.urgency.titleize}"
      parts << ""
      parts << "**Task:**"
      parts << collab_request.task_description
      
      if collab_request.context.present?
        parts << ""
        parts << "**Context:**"
        parts << collab_request.context.to_s.truncate(500)
      end
      
      parts.join("\n")
    end
  end

  # Singleton for system messages when no agent is available
  class SystemSender
    include Singleton

    def id
      0
    end

    def name
      'System'
    end

    def class
      # Trick for polymorphic association
      AgentPlugin
    end
  end
end
