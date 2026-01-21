# frozen_string_literal: true

# AutomationTriggerJob - Background job to execute automations
#
# This job is enqueued when:
# - A record is created/updated in a module
# - A scheduled task fires
# - A webhook is received
# - A form is submitted on a web app
#
class AutomationTriggerJob < ApplicationJob
  queue_as :automations

  # Retry strategy for transient failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Don't retry these errors
  discard_on AutomationCode::InvalidTransition

  # Execute a specific automation
  def perform(automation_id, trigger_data, options = {})
    automation = AutomationCode.find_by(id: automation_id)
    
    unless automation
      Rails.logger.warn "[AutomationTriggerJob] Automation #{automation_id} not found"
      return
    end

    unless automation.active?
      Rails.logger.debug "[AutomationTriggerJob] Automation #{automation_id} is not active (#{automation.status})"
      return
    end

    # Execute the automation
    user = options[:user_id] ? User.find_by(id: options[:user_id]) : nil
    executor = AutomationCodeExecutor.new(automation, 
      user: user,
      trigger_source: options[:trigger_source] || 'job'
    )

    result = executor.execute!(trigger_data.with_indifferent_access)

    if result[:success]
      Rails.logger.info "[AutomationTriggerJob] Automation #{automation.name} completed successfully"
    else
      Rails.logger.warn "[AutomationTriggerJob] Automation #{automation.name} failed: #{result[:error]}"
    end

    result
  end

  # Class method to trigger all matching automations for a record event
  def self.trigger_for_record_event(app_module, event_type, record, changes = {}, user = nil)
    trigger_data = {
      record: record.is_a?(Hash) ? record : record.attributes,
      changes: changes,
      user_id: user&.id,
      timestamp: Time.current.iso8601,
      event_type: event_type
    }

    # Find all active automations that match
    automations = AutomationCode.for_record_event(app_module.id, event_type, trigger_data)
    
    automations.each do |automation|
      next unless automation.matches_trigger?(trigger_data)

      Rails.logger.info "[AutomationTriggerJob] Queueing #{automation.name} for #{event_type} on #{app_module.name}"
      
      AutomationTriggerJob.perform_later(
        automation.id,
        trigger_data,
        { user_id: user&.id, trigger_source: 'record' }
      )
    end

    automations.count
  end

  # Class method to trigger automations for a form submission
  def self.trigger_for_form_submit(web_app, form_data, user = nil)
    trigger_data = {
      form_data: form_data,
      user_id: user&.id,
      timestamp: Time.current.iso8601,
      event_type: 'form_submit'
    }

    automations = AutomationCode.for_web_app(web_app.id).for_trigger('form_submit').active

    automations.each do |automation|
      Rails.logger.info "[AutomationTriggerJob] Queueing #{automation.name} for form_submit on #{web_app.name}"
      
      AutomationTriggerJob.perform_later(
        automation.id,
        trigger_data,
        { user_id: user&.id, trigger_source: 'form' }
      )
    end

    automations.count
  end

  # Class method to trigger automations for a webhook
  def self.trigger_for_webhook(entity, webhook_slug, payload, headers = {})
    trigger_data = {
      payload: payload,
      headers: headers.slice('content-type', 'x-webhook-signature', 'user-agent'),
      timestamp: Time.current.iso8601,
      event_type: 'webhook',
      webhook_slug: webhook_slug
    }

    # Find automations matching this webhook
    automations = AutomationCode.for_entity(entity.id)
                                .for_trigger('webhook')
                                .active
                                .where("trigger_config->>'slug' = ?", webhook_slug)

    automations.each do |automation|
      Rails.logger.info "[AutomationTriggerJob] Queueing #{automation.name} for webhook #{webhook_slug}"
      
      AutomationTriggerJob.perform_later(
        automation.id,
        trigger_data,
        { trigger_source: 'webhook' }
      )
    end

    automations.count
  end
end

