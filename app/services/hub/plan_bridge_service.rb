# frozen_string_literal: true

module Hub
  # PlanBridgeService
  #
  # Integrates ExecutionPlans with the Hub for real-time collaboration.
  # Creates work_stream threads for plans and broadcasts updates.
  #
  class PlanBridgeService
    attr_reader :entity, :plan

    def initialize(plan:)
      @plan = plan
      @entity = plan.entity
    end

    # Create or get the Hub thread for this plan
    def ensure_hub_thread
      return plan.hub_thread if plan.respond_to?(:hub_thread) && plan.hub_thread.present?

      # Find existing thread for this plan
      existing = HubThread.find_by(
        entity: entity,
        thread_type: 'work_stream',
        agent_work_item_id: nil # We use metadata instead
      )&.where("metadata->>'plan_id' = ?", plan.id.to_s)&.first

      return existing if existing

      # Create new work_stream thread
      thread = HubThread.create!(
        entity: entity,
        thread_type: HubThread::WORK_STREAM,
        status: 'active',
        subject: "Plan: #{plan.title}",
        started_by: plan.user,
        metadata: {
          plan_id: plan.id,
          plan_title: plan.title,
          created_at: Time.current.iso8601
        }
      )

      # Add the user as a participant
      thread.hub_participants.create!(
        participant: plan.user,
        role: 'owner',
        notify_on_message: true
      )

      # Add Amos/Scout as a participant (if there's a system agent)
      # This allows the plan updates to appear as agent messages
      
      thread
    end

    # Broadcast a plan event to the Hub
    def broadcast_event(event_type, message, metadata = {})
      thread = ensure_hub_thread
      return unless thread

      # Create a Hub message for the event
      thread.hub_messages.create!(
        sender: nil, # System message
        content: build_event_message(event_type, message),
        message_type: 'system',
        metadata: {
          event_type: event_type,
          plan_id: plan.id,
          **metadata
        }
      )

      # Broadcast via ActionCable
      ActionCable.server.broadcast(
        "hub_thread_#{thread.id}",
        {
          type: 'plan_update',
          event: event_type,
          message: message,
          plan_id: plan.id,
          progress: plan.progress_percentage,
          status: plan.status,
          timestamp: Time.current.iso8601
        }
      )
    rescue => e
      Rails.logger.warn "[PlanBridge] Failed to broadcast event: #{e.message}"
    end

    # Called when plan starts execution
    def on_plan_started
      broadcast_event('plan_started', "🚀 Plan execution started: #{plan.title}")
    end

    # Called when a step starts
    def on_step_started(step)
      agent_name = step['agent']&.titleize&.gsub('_', ' ') || 'Scout'
      broadcast_event(
        'step_started',
        "▶️ Starting step: #{step['name']} (#{agent_name})",
        { step_id: step['id'], step_name: step['name'], agent: step['agent'] }
      )
    end

    # Called when a step completes
    def on_step_completed(step, result = nil)
      broadcast_event(
        'step_completed',
        "✅ Completed: #{step['name']}",
        { step_id: step['id'], step_name: step['name'], result_summary: result.to_s.truncate(200) }
      )
    end

    # Called when a step fails
    def on_step_failed(step, error)
      broadcast_event(
        'step_failed',
        "❌ Failed: #{step['name']} - #{error}",
        { step_id: step['id'], step_name: step['name'], error: error }
      )
    end

    # Called when a phase completes
    def on_phase_completed(phase)
      broadcast_event(
        'phase_completed',
        "🎯 Phase completed: #{phase['name']} (#{plan.progress_percentage}% overall)",
        { phase_name: phase['name'] }
      )
    end

    # Called when plan completes
    def on_plan_completed
      duration = plan.actual_duration_minutes || 0
      broadcast_event(
        'plan_completed',
        "🎉 Plan completed successfully! (#{duration} minutes)",
        { duration_minutes: duration, total_steps: plan.total_steps }
      )
    end

    # Called when plan fails
    def on_plan_failed(reason)
      broadcast_event(
        'plan_failed',
        "💥 Plan failed: #{reason}",
        { failure_reason: reason }
      )
    end

    # Called when plan is paused
    def on_plan_paused(reason = nil)
      broadcast_event(
        'plan_paused',
        "⏸️ Plan paused#{reason ? ": #{reason}" : ''}",
        { reason: reason }
      )
    end

    # Called when plan is resumed
    def on_plan_resumed
      broadcast_event(
        'plan_resumed',
        "▶️ Plan resumed - continuing execution",
        {}
      )
    end

    # Called when user input is needed
    def on_user_input_needed(step, question)
      thread = ensure_hub_thread
      return unless thread

      # Create a message that needs response
      message = thread.hub_messages.create!(
        sender: nil,
        content: "❓ **Input needed for step '#{step['name']}'**\n\n#{question}",
        message_type: HubMessage::QUESTION,
        needs_response: true,
        metadata: {
          plan_id: plan.id,
          step_id: step['id'],
          awaiting_input: true
        }
      )

      # Notify the user
      ActionCable.server.broadcast(
        "user_notifications_#{plan.user.id}",
        {
          type: 'plan_input_needed',
          plan_id: plan.id,
          step_id: step['id'],
          question: question,
          thread_id: thread.id,
          message_id: message.id
        }
      )

      message
    end

    private

    def build_event_message(event_type, message)
      progress_bar = build_progress_bar
      
      case event_type
      when 'plan_started', 'plan_completed', 'plan_failed'
        "#{message}\n\n#{progress_bar}"
      else
        message
      end
    end

    def build_progress_bar
      pct = plan.progress_percentage
      filled = (pct / 5).round
      empty = 20 - filled
      
      bar = "█" * filled + "░" * empty
      "[#{bar}] #{pct}% (#{plan.completed_steps}/#{plan.total_steps})"
    end
  end
end


