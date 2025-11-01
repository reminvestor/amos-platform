# app/jobs/pipeline_timeout_monitor_job.rb
#
# Monitors active pipeline executions for stuck states and automatic timeouts.
# Runs every 5 minutes via recurring jobs.
#
# Timeout Rules:
# - Clarifying/Planning: 15 minutes
# - Implementing: 30 minutes
# - Review: 10 minutes
# - Testing/Dev/Staging: 20 minutes
# - Awaiting Prod Approval: 4 hours
# - Blocked (human interaction): 2 hours
#
# Actions Taken:
# - Logs warning for stuck pipelines
# - Creates timeout event in audit trail
# - Marks pipeline as failed with reason
# - Sends notification to admins

class PipelineTimeoutMonitorJob < ApplicationJob
  queue_as :maintenance

  def perform
    Rails.logger.info "🕐 Running Pipeline Timeout Monitor"

    Entity.find_each do |entity|
      check_entity_pipelines(entity)
    end

    Rails.logger.info "✅ Pipeline Timeout Monitor complete"
  end

  private

  def check_entity_pipelines(entity)
    # Get all active (non-terminal) pipelines for this entity
    active_pipelines = entity.pipeline_executions.active

    Rails.logger.debug "Checking #{active_pipelines.count} active pipelines for entity #{entity.name}"

    active_pipelines.each do |pipeline|
      check_pipeline_timeout(pipeline)
      check_agent_timeout(pipeline)
      check_interaction_timeout(pipeline)
    end
  end

  def check_pipeline_timeout(pipeline)
    return unless pipeline.stuck?

    reason = "Pipeline stuck in '#{pipeline.status}' state for > #{pipeline.stuck_timeout_for_state(pipeline.status)} minutes"

    Rails.logger.warn "⚠️  Pipeline #{pipeline.id} (#{pipeline.ticket_id}): #{reason}"

    # Cancel the stuck pipeline
    pipeline.cancel_stuck!(reason)

    # Send notification
    notify_timeout(pipeline, reason)
  end

  def check_agent_timeout(pipeline)
    return unless pipeline.agent_stuck?

    agent = pipeline.running_agent_execution
    reason = "Agent '#{agent.agent_id}' stuck running for > 15 minutes"

    Rails.logger.warn "⚠️  Pipeline #{pipeline.id} (#{pipeline.ticket_id}): #{reason}"

    # Mark agent as failed
    agent.update!(
      status: :failed,
      completed_at: Time.current,
      error_message: "Timeout: Agent exceeded 15 minute execution limit"
    )

    # Cancel the pipeline
    pipeline.cancel_stuck!(reason)

    # Send notification
    notify_timeout(pipeline, reason)
  end

  def check_interaction_timeout(pipeline)
    # Check if any interactions have timed out
    timed_out_interactions = pipeline.pipeline_interactions
                                     .where(status: :pending)
                                     .where('timeout_at < ?', Time.current)

    return if timed_out_interactions.none?

    Rails.logger.warn "⚠️  Pipeline #{pipeline.id} (#{pipeline.ticket_id}): #{timed_out_interactions.count} interactions timed out"

    timed_out_interactions.each do |interaction|
      interaction.update!(status: :timeout, answered_at: Time.current)

      # Create event
      pipeline.pipeline_events.create!(
        event_type: 'interaction.timeout',
        source: 'system',
        payload: {
          interaction_type: interaction.interaction_type,
          timeout_at: interaction.timeout_at,
          question: interaction.question
        }
      )
    end

    # Cancel the pipeline
    reason = "Human interaction timeout (#{timed_out_interactions.first.interaction_type})"
    pipeline.cancel_stuck!(reason)

    # Send notification
    notify_timeout(pipeline, reason)
  end

  def notify_timeout(pipeline, reason)
    # Send notification via configured channels
    begin
      if ENV['SLACK_API_TOKEN'].present?
        notifier = AiAgents::Notifiers::SlackNotifier.new
        notifier.send_timeout_notification(pipeline, reason)
      end

      if ENV['MAILGUN_API_KEY'].present?
        notifier = AiAgents::Notifiers::EmailNotifier.new
        notifier.send_timeout_notification(pipeline, reason)
      end
    rescue => e
      Rails.logger.error "Failed to send timeout notification: #{e.message}"
    end
  end
end
