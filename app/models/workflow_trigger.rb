# frozen_string_literal: true

# WorkflowTrigger - Connects triggerable entities to workflows
#
# This creates a unified triggering system where:
# - LandingPage form submissions can trigger workflows
# - Website page events can trigger workflows
# - AppModule record changes can trigger workflows
# - Webhooks can trigger workflows
# - Schedules can trigger workflows
# - Manual invocations can trigger workflows
#
# The trigger is the entry point, and when fired, it creates a WorkflowExecution
# that runs through the compiled workflow steps.
#
class WorkflowTrigger < ApplicationRecord
  # ═══════════════════════════════════════════════════════════════
  # ASSOCIATIONS
  # ═══════════════════════════════════════════════════════════════

  belongs_to :entity
  belongs_to :automation_code

  # Polymorphic - what triggers this workflow
  # Can be: LandingPage, WebsitePage, AppModule, ModuleWebhook, etc.
  belongs_to :triggerable, polymorphic: true, optional: true

  # ═══════════════════════════════════════════════════════════════
  # CONSTANTS
  # ═══════════════════════════════════════════════════════════════

  TRIGGER_TYPES = %w[
    form
    webhook
    schedule
    record_created
    record_updated
    record_deleted
    field_changed
    status_changed
    manual
    integration_event
  ].freeze

  STATUSES = %w[active paused disabled].freeze

  # ═══════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ═══════════════════════════════════════════════════════════════

  validates :trigger_type, presence: true, inclusion: { in: TRIGGER_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :webhook_path, uniqueness: true, allow_nil: true,
            format: { with: /\A[a-z0-9\-_]+\z/, message: 'only lowercase letters, numbers, hyphens, underscores' }

  validate :validate_trigger_config
  validate :validate_triggerable_matches_type

  # ═══════════════════════════════════════════════════════════════
  # CALLBACKS
  # ═══════════════════════════════════════════════════════════════

  before_create :generate_webhook_path, if: -> { trigger_type == 'webhook' && webhook_path.blank? }
  before_create :generate_webhook_secret, if: -> { trigger_type == 'webhook' && webhook_secret.blank? }
  before_save :calculate_next_trigger, if: -> { trigger_type == 'schedule' && cron_expression_changed? }

  # ═══════════════════════════════════════════════════════════════
  # SCOPES
  # ═══════════════════════════════════════════════════════════════

  scope :active, -> { where(status: 'active', enabled: true) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :by_type, ->(type) { where(trigger_type: type) }
  scope :for_triggerable, ->(triggerable) { where(triggerable: triggerable) }
  scope :webhooks, -> { where(trigger_type: 'webhook') }
  scope :scheduled, -> { where(trigger_type: 'schedule') }
  scope :due_to_run, -> { where('next_trigger_at <= ?', Time.current) }

  # ═══════════════════════════════════════════════════════════════
  # STATUS HELPERS
  # ═══════════════════════════════════════════════════════════════

  def active?
    status == 'active' && enabled?
  end

  def paused?
    status == 'paused'
  end

  def disabled?
    status == 'disabled' || !enabled?
  end

  def pause!
    update!(status: 'paused')
  end

  def resume!
    update!(status: 'active')
  end

  def disable!
    update!(status: 'disabled', enabled: false)
  end

  # ═══════════════════════════════════════════════════════════════
  # FIRING THE TRIGGER
  # ═══════════════════════════════════════════════════════════════

  # Fire this trigger with the given context
  # Returns a WorkflowExecution (or AutomationExecution for legacy)
  def fire!(context = {})
    return { success: false, error: 'Trigger is not active' } unless active?
    return { success: false, error: 'Workflow is not compiled' } unless automation_code.is_compiled?

    # Validate the context against expected inputs
    validation = validate_trigger_context(context)
    return { success: false, errors: validation[:errors] } unless validation[:valid]

    # Create the execution
    execution = create_execution(context)

    # Queue for execution
    Workflows::ExecutorJob.perform_later(execution.id)

    # Update metrics
    record_trigger!

    {
      success: true,
      execution_id: execution.id,
      execution: execution
    }
  rescue => e
    record_error!(e.message)
    { success: false, error: e.message }
  end

  # Fire synchronously (blocking) - for testing or simple workflows
  def fire_sync!(context = {})
    return { success: false, error: 'Trigger is not active' } unless active?
    return { success: false, error: 'Workflow is not compiled' } unless automation_code.is_compiled?

    execution = create_execution(context)
    
    executor = Workflows::ExecutorService.new(execution)
    result = executor.execute!

    record_trigger!
    result[:success] ? record_success! : record_error!(result[:error])

    result.merge(execution: execution)
  rescue => e
    record_error!(e.message)
    { success: false, error: e.message }
  end

  # ═══════════════════════════════════════════════════════════════
  # WEBHOOK HANDLING
  # ═══════════════════════════════════════════════════════════════

  def webhook_url
    return nil unless trigger_type == 'webhook' && webhook_path.present?
    
    host = Rails.application.routes.default_url_options[:host] || 'localhost:3000'
    protocol = Rails.env.production? ? 'https' : 'http'
    "#{protocol}://#{host}/webhooks/workflow/#{webhook_path}"
  end

  def verify_webhook_signature(payload, signature)
    return true if webhook_secret.blank?  # No secret = no verification required
    
    expected = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, payload)
    ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
  end

  # ═══════════════════════════════════════════════════════════════
  # SCHEDULE HANDLING
  # ═══════════════════════════════════════════════════════════════

  def calculate_next_trigger_time
    return nil unless trigger_type == 'schedule' && cron_expression.present?

    require 'fugit'
    cron = Fugit::Cron.parse(cron_expression)
    cron.next_time.to_t
  rescue => e
    Rails.logger.error "[WorkflowTrigger] Failed to parse cron: #{e.message}"
    nil
  end

  def update_next_trigger!
    next_time = calculate_next_trigger_time
    update_columns(next_trigger_at: next_time, last_triggered_at: Time.current) if next_time
  end

  # ═══════════════════════════════════════════════════════════════
  # RECORD EVENT HANDLING
  # ═══════════════════════════════════════════════════════════════

  # Check if this trigger should fire for a given record event
  def matches_record_event?(event_type, record, changes = {})
    return false unless trigger_type.start_with?('record_', 'field_', 'status_')
    return false unless triggerable_id == record.class.try(:app_module_id) || 
                        triggerable == record.class.try(:app_module)

    case trigger_type
    when 'record_created'
      event_type == 'created'
    when 'record_updated'
      event_type == 'updated'
    when 'record_deleted'
      event_type == 'deleted'
    when 'field_changed'
      field = trigger_config['field']
      changes.key?(field) || changes.key?(field.to_sym)
    when 'status_changed'
      return false unless changes.key?('status') || changes.key?(:status)
      
      from = trigger_config['from']
      to = trigger_config['to']
      old_val, new_val = changes['status'] || changes[:status]
      
      (from.blank? || from == old_val) && (to.blank? || to == new_val)
    else
      false
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # METRICS
  # ═══════════════════════════════════════════════════════════════

  def record_trigger!
    update_columns(
      trigger_count: trigger_count + 1,
      last_triggered_at: Time.current
    )
  end

  def record_success!
    update_columns(success_count: success_count + 1)
  end

  def record_error!(message = nil)
    update_columns(error_count: error_count + 1)
    Rails.logger.error "[WorkflowTrigger:#{id}] Error: #{message}" if message
  end

  def success_rate
    return 0.0 if trigger_count.zero?
    success_count.to_f / trigger_count
  end

  # ═══════════════════════════════════════════════════════════════
  # SERIALIZATION
  # ═══════════════════════════════════════════════════════════════

  def to_summary
    {
      id: id,
      trigger_type: trigger_type,
      triggerable_type: triggerable_type,
      triggerable_name: triggerable.try(:name) || triggerable.try(:title),
      webhook_url: webhook_url,
      cron_expression: cron_expression,
      status: status,
      enabled: enabled,
      trigger_count: trigger_count,
      success_rate: (success_rate * 100).round(1),
      last_triggered_at: last_triggered_at,
      next_trigger_at: next_trigger_at
    }
  end

  private

  def create_execution(context)
    AutomationExecution.create!(
      automation_code: automation_code,
      entity: entity,
      triggered_by: context[:user],
      trigger_source: trigger_type,
      status: 'pending',
      input_data: context,
      metadata: {
        workflow_trigger_id: id,
        triggerable_type: triggerable_type,
        triggerable_id: triggerable_id,
        triggered_at: Time.current.iso8601
      }
    )
  end

  def validate_trigger_context(context)
    # Get the trigger node from the workflow definition
    trigger_node = automation_code.workflow_definition.dig('nodes')&.find { |n| n['type'].to_s.start_with?('trigger-') }
    return { valid: true } unless trigger_node

    node_type = Workflows::NodeRegistry.instance.get(trigger_node['type'])
    return { valid: true } unless node_type

    # For now, basic validation - can be extended
    { valid: true }
  end

  def generate_webhook_path
    self.webhook_path = "#{automation_code.slug}-#{SecureRandom.hex(8)}"
  end

  def generate_webhook_secret
    self.webhook_secret = SecureRandom.hex(32)
  end

  def calculate_next_trigger
    self.next_trigger_at = calculate_next_trigger_time
  end

  def validate_trigger_config
    case trigger_type
    when 'schedule'
      if cron_expression.blank? && trigger_config['interval_minutes'].blank?
        errors.add(:trigger_config, 'must have cron_expression or interval_minutes for schedule trigger')
      end
    when 'field_changed'
      if trigger_config['field'].blank?
        errors.add(:trigger_config, 'must specify field for field_changed trigger')
      end
    when 'status_changed'
      if trigger_config['from'].blank? && trigger_config['to'].blank?
        errors.add(:trigger_config, 'must specify from and/or to for status_changed trigger')
      end
    end
  end

  def validate_triggerable_matches_type
    return if triggerable.blank?

    valid_types = case trigger_type
    when 'form'
      %w[LandingPage WebsitePage]
    when 'record_created', 'record_updated', 'record_deleted', 'field_changed', 'status_changed'
      %w[AppModule]
    when 'integration_event'
      %w[Integration ModuleIntegration]
    else
      nil  # Any or none
    end

    if valid_types && !valid_types.include?(triggerable_type)
      errors.add(:triggerable, "must be one of: #{valid_types.join(', ')} for #{trigger_type} trigger")
    end
  end
end
