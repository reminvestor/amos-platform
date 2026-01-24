# frozen_string_literal: true

# SystemNotificationService - Unified notification system for all platform events
#
# This service consolidates notifications for:
# - Failed jobs/tasks
# - Stuck executions (ExecutionGuard)
# - Agent school enrollments
# - Automation failures
# - Integration errors
# - Scheduled task failures
# - Unfulfilled AI intents
#
# Notifications are:
# 1. Stored in the database for history
# 2. Broadcast in real-time via ActionCable
# 3. Optionally sent via email/Slack (if configured)
#
class SystemNotificationService
  # Notification severity levels
  SEVERITY = {
    info: 0,
    warning: 1,
    error: 2,
    critical: 3
  }.freeze

  # Notification categories
  CATEGORIES = %w[
    job_failure
    job_stuck
    agent_school
    automation_failure
    integration_error
    scheduled_task_failure
    unfulfilled_intent
    execution_loop
    delegation_failure
    system_health
    user_action_required
  ].freeze

  attr_reader :entity, :user

  def initialize(entity:, user: nil)
    @entity = entity
    @user = user
  end

  # ═══════════════════════════════════════════════════════════════
  # NOTIFICATION CREATORS
  # ═══════════════════════════════════════════════════════════════

  # Job failure notification
  def notify_job_failure(job_id:, job_type:, error:, context: {})
    create_notification(
      category: 'job_failure',
      severity: :error,
      title: "Job Failed: #{job_type}",
      message: error.to_s.truncate(500),
      metadata: {
        job_id: job_id,
        job_type: job_type,
        context: context
      },
      actionable: true,
      action_label: 'View Details',
      action_path: "/admin/jobs/#{job_id}"
    )
  end

  # Stuck execution notification (from ExecutionGuard)
  def notify_stuck_execution(execution_id:, agent_name:, duration_seconds:, unfulfilled_intents: [])
    create_notification(
      category: 'job_stuck',
      severity: :warning,
      title: "Execution Stuck: #{agent_name}",
      message: "Agent execution ##{execution_id} has been running for #{duration_seconds}s without progress. " \
               "Unfulfilled intents: #{unfulfilled_intents.join(', ')}",
      metadata: {
        execution_id: execution_id,
        agent_name: agent_name,
        duration_seconds: duration_seconds,
        unfulfilled_intents: unfulfilled_intents
      },
      actionable: true,
      action_label: 'View Execution',
      action_path: "/admin/agent_executions/#{execution_id}"
    )
  end

  # Agent school enrollment notification
  def notify_agent_school_enrollment(agent:, enrollment:, reason:)
    create_notification(
      category: 'agent_school',
      severity: :warning,
      title: "Agent Enrolled in School: #{agent.name}",
      message: "Agent #{agent.name} has been enrolled in school. Reason: #{reason}",
      metadata: {
        agent_id: agent.id,
        agent_name: agent.name,
        enrollment_id: enrollment.id,
        reason: reason
      },
      actionable: true,
      action_label: 'View Agent',
      action_path: "/admin/agents/#{agent.id}"
    )
  end

  # Automation failure notification
  def notify_automation_failure(automation:, execution:, error:)
    create_notification(
      category: 'automation_failure',
      severity: :error,
      title: "Automation Failed: #{automation.name}",
      message: error.to_s.truncate(500),
      metadata: {
        automation_id: automation.id,
        automation_name: automation.name,
        execution_id: execution.id,
        trigger_type: automation.trigger_type
      },
      actionable: true,
      action_label: 'View Automation',
      action_path: "/admin/automations/#{automation.id}"
    )
  end

  # Integration error notification
  def notify_integration_error(integration:, operation:, error:, request_context: {})
    create_notification(
      category: 'integration_error',
      severity: :error,
      title: "Integration Error: #{integration.name}",
      message: "Operation '#{operation}' failed: #{error.to_s.truncate(300)}",
      metadata: {
        integration_id: integration.id,
        integration_name: integration.name,
        operation: operation,
        request_context: request_context.except(:credentials, :api_key, :token)
      },
      actionable: true,
      action_label: 'View Integration',
      action_path: "/admin/integrations/#{integration.id}"
    )
  end

  # Scheduled task failure notification
  def notify_scheduled_task_failure(task:, run:, error:, consecutive_failures:)
    severity = consecutive_failures >= 3 ? :critical : :error
    
    create_notification(
      category: 'scheduled_task_failure',
      severity: severity,
      title: consecutive_failures >= 3 ? 
        "Scheduled Task BLOCKED: #{task.name}" : 
        "Scheduled Task Failed: #{task.name}",
      message: consecutive_failures >= 3 ?
        "Task blocked after #{consecutive_failures} consecutive failures. Last error: #{error.to_s.truncate(300)}" :
        "Task failed: #{error.to_s.truncate(400)}",
      metadata: {
        task_id: task.id,
        task_name: task.name,
        run_id: run&.id,
        consecutive_failures: consecutive_failures,
        schedule_type: task.schedule_type
      },
      actionable: true,
      action_label: 'Manage Task',
      action_path: "/scheduled_tasks/#{task.id}"
    )
  end

  # Unfulfilled intent notification (from ExecutionGuard)
  def notify_unfulfilled_intent(intents:, response_preview:, context: {})
    create_notification(
      category: 'unfulfilled_intent',
      severity: :warning,
      title: "AI Intent Not Fulfilled",
      message: "AI stated intent to '#{intents.first(2).join(', ')}' but no tool was called. " \
               "Response: #{response_preview.truncate(200)}",
      metadata: {
        intents: intents,
        response_preview: response_preview.truncate(500),
        context: context
      },
      actionable: false
    )
  end

  # Execution loop notification
  def notify_execution_loop(pattern:, tool_name:, retry_count:, context: {})
    create_notification(
      category: 'execution_loop',
      severity: :warning,
      title: "Execution Loop Detected",
      message: "Tool '#{tool_name}' has been called #{retry_count} times in a loop pattern (#{pattern}). " \
               "Execution was terminated to prevent infinite loop.",
      metadata: {
        pattern: pattern,
        tool_name: tool_name,
        retry_count: retry_count,
        context: context
      },
      actionable: false
    )
  end

  # Delegation failure notification
  def notify_delegation_failure(from_agent:, to_agent:, task:, error:)
    create_notification(
      category: 'delegation_failure',
      severity: :error,
      title: "Delegation Failed",
      message: "Delegation from #{from_agent} to #{to_agent} failed: #{error.to_s.truncate(300)}. Task: #{task.truncate(200)}",
      metadata: {
        from_agent: from_agent,
        to_agent: to_agent,
        task: task.truncate(500),
        error: error.to_s
      },
      actionable: false
    )
  end

  # User action required notification
  def notify_user_action_required(title:, message:, action_label:, action_path:, context: {})
    create_notification(
      category: 'user_action_required',
      severity: :info,
      title: title,
      message: message,
      metadata: context,
      actionable: true,
      action_label: action_label,
      action_path: action_path
    )
  end

  # ═══════════════════════════════════════════════════════════════
  # QUERIES
  # ═══════════════════════════════════════════════════════════════

  # Get unread notifications for user
  def unread_notifications(limit: 20)
    SystemNotification.where(entity: entity, user: user)
                     .where(read_at: nil)
                     .order(created_at: :desc)
                     .limit(limit)
  end

  # Get unread count for badge
  def unread_count
    SystemNotification.where(entity: entity, user: user)
                     .where(read_at: nil)
                     .count
  end

  # Get recent notifications
  def recent_notifications(limit: 50, category: nil)
    scope = SystemNotification.where(entity: entity)
    scope = scope.where(user: user) if user
    scope = scope.where(category: category) if category
    scope.order(created_at: :desc).limit(limit)
  end

  # Get notification stats for dashboard
  def stats(since: 24.hours.ago)
    base_scope = SystemNotification.where(entity: entity).where('created_at > ?', since)
    
    {
      total: base_scope.count,
      unread: base_scope.where(read_at: nil).count,
      by_severity: {
        critical: base_scope.where(severity: :critical).count,
        error: base_scope.where(severity: :error).count,
        warning: base_scope.where(severity: :warning).count,
        info: base_scope.where(severity: :info).count
      },
      by_category: base_scope.group(:category).count
    }
  end

  # Mark notifications as read
  def mark_as_read(notification_ids)
    SystemNotification.where(id: notification_ids, entity: entity)
                     .update_all(read_at: Time.current)
  end

  # Mark all as read
  def mark_all_read
    scope = SystemNotification.where(entity: entity, read_at: nil)
    scope = scope.where(user: user) if user
    scope.update_all(read_at: Time.current)
  end

  private

  def create_notification(category:, severity:, title:, message:, metadata: {}, actionable: false, action_label: nil, action_path: nil)
    notification = SystemNotification.create!(
      entity: entity,
      user: user,
      category: category,
      severity: severity,
      title: title,
      message: message,
      metadata: metadata,
      actionable: actionable,
      action_label: action_label,
      action_path: action_path
    )

    # Broadcast to user's channel
    broadcast_notification(notification)

    # Check if we should send external notification (email/Slack)
    send_external_notification_if_needed(notification)

    # Log for analytics
    log_notification(notification)

    notification
  rescue => e
    Rails.logger.error "[SystemNotificationService] Failed to create notification: #{e.message}"
    nil
  end

  def broadcast_notification(notification)
    ActionCable.server.broadcast(
      "notifications_#{entity.id}_#{user&.id || 'all'}",
      {
        type: 'new_notification',
        notification: {
          id: notification.id,
          category: notification.category,
          severity: notification.severity,
          title: notification.title,
          message: notification.message.truncate(200),
          actionable: notification.actionable,
          action_label: notification.action_label,
          action_path: notification.action_path,
          created_at: notification.created_at.iso8601
        },
        unread_count: unread_count
      }
    )
  rescue => e
    Rails.logger.debug "[SystemNotificationService] Broadcast failed: #{e.message}"
  end

  def send_external_notification_if_needed(notification)
    return unless notification.severity.to_s.in?(%w[critical error])
    
    # Check entity settings for external notifications (using new settings system)
    # Slack notifications are OFF by default
    if entity.slack_notifications_enabled? && entity.slack_webhook_url.present?
      send_slack_notification(notification, entity.slack_webhook_url)
    end
    
    # Email notifications are ON by default
    if entity.email_notifications_enabled? && user&.email.present?
      NotificationMailer.system_notification(user, notification).deliver_later
    end
  rescue => e
    Rails.logger.debug "[SystemNotificationService] External notification failed: #{e.message}"
  end

  def send_slack_notification(notification, webhook_url)
    color = case notification.severity.to_s
            when 'critical' then 'danger'
            when 'error' then 'danger'
            when 'warning' then 'warning'
            else 'good'
            end

    payload = {
      attachments: [{
        color: color,
        title: notification.title,
        text: notification.message,
        footer: "AMOS Platform | #{notification.category.titleize}",
        ts: notification.created_at.to_i
      }]
    }

    HTTParty.post(webhook_url, body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
  rescue => e
    Rails.logger.warn "[SystemNotificationService] Slack notification failed: #{e.message}"
  end

  def log_notification(notification)
    Rails.logger.info "[SystemNotification] #{notification.severity.upcase}: #{notification.category} - #{notification.title}"
  end
end

