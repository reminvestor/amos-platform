# frozen_string_literal: true

# AutomationCode - Deterministic automation using AI-generated Ruby code
#
# The key insight: AI writes the code ONCE during setup, then it runs
# WITHOUT AI - fast, predictable, and cheap.
#
# This follows the same pattern as TransformCodeExecutor in the ETL pipeline.
#
class AutomationCode < ApplicationRecord
  # ============================================
  # ASSOCIATIONS
  # ============================================

  belongs_to :entity
  belongs_to :web_app, optional: true
  belongs_to :app_module, optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :automation_executions, dependent: :destroy

  # ============================================
  # CONSTANTS
  # ============================================

  TRIGGER_TYPES = %w[
    record_created
    record_updated
    status_changed
    field_changed
    schedule
    webhook
    form_submit
    manual
  ].freeze

  STATUSES = %w[draft testing active paused failed].freeze

  # ============================================
  # VALIDATIONS
  # ============================================

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :entity_id }
  validates :trigger_type, presence: true, inclusion: { in: TRIGGER_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :code, presence: true

  validate :validate_code_syntax
  validate :validate_trigger_config

  # ============================================
  # CALLBACKS
  # ============================================

  before_validation :generate_slug, on: :create
  before_save :increment_version, if: :code_changed?

  # ============================================
  # SCOPES
  # ============================================

  scope :active, -> { where(status: 'active') }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :for_trigger, ->(type) { where(trigger_type: type) }
  scope :for_web_app, ->(web_app_id) { where(web_app_id: web_app_id) }
  scope :for_module, ->(app_module_id) { where(app_module_id: app_module_id) }
  scope :tested, -> { where(is_tested: true) }

  # Find automations that should fire for a record event
  scope :for_record_event, ->(app_module_id, event_type, record_data = {}) {
    where(app_module_id: app_module_id, status: 'active')
      .where(trigger_type: event_type)
      .or(where(app_module_id: app_module_id, status: 'active', trigger_type: 'status_changed'))
      .or(where(app_module_id: app_module_id, status: 'active', trigger_type: 'field_changed'))
  }

  # ============================================
  # STATUS HELPERS
  # ============================================

  def draft?; status == 'draft'; end
  def testing?; status == 'testing'; end
  def active?; status == 'active'; end
  def paused?; status == 'paused'; end
  def failed?; status == 'failed'; end

  def can_activate?
    is_tested? && (draft? || testing? || paused?)
  end

  def activate!
    raise InvalidTransition, "Cannot activate: not tested" unless is_tested?
    raise InvalidTransition, "Cannot activate from #{status}" unless can_activate?
    update!(status: 'active')
  end

  def pause!
    raise InvalidTransition, "Can only pause active automations" unless active?
    update!(status: 'paused')
  end

  def mark_failed!(error_message)
    update!(
      status: 'failed',
      last_error_at: Time.current,
      last_error_message: error_message
    )
  end

  # ============================================
  # EXECUTION TRACKING
  # ============================================

  def record_execution!(result, duration_ms: nil)
    update_columns(
      execution_count: execution_count + 1,
      success_count: result[:success] ? success_count + 1 : success_count,
      error_count: result[:success] ? error_count : error_count + 1,
      last_executed_at: Time.current,
      last_error_at: result[:success] ? last_error_at : Time.current,
      last_error_message: result[:success] ? last_error_message : result[:error],
      avg_execution_time_ms: calculate_avg_time(duration_ms)
    )
  end

  def record_error!(error)
    update_columns(
      execution_count: execution_count + 1,
      error_count: error_count + 1,
      last_executed_at: Time.current,
      last_error_at: Time.current,
      last_error_message: error.message
    )

    # Auto-pause if too many errors
    if error_rate > 0.5 && execution_count >= 10
      update_column(:status, 'paused')
      Rails.logger.warn "[AutomationCode:#{id}] Auto-paused due to high error rate: #{(error_rate * 100).round}%"
    end
  end

  def error_rate
    return 0.0 if execution_count.zero?
    error_count.to_f / execution_count
  end

  def success_rate
    return 0.0 if execution_count.zero?
    success_count.to_f / execution_count
  end

  # ============================================
  # TESTING
  # ============================================

  def test!(sample_data = nil)
    input = sample_data || sample_input || default_sample_input
    
    executor = AutomationCodeExecutor.new(self)
    start_time = Time.current
    result = executor.execute!(input)
    duration = ((Time.current - start_time) * 1000).round(2)

    update!(
      is_tested: result[:success],
      last_tested_at: Time.current,
      sample_input: input,
      sample_output: result[:success] ? result[:data] : { error: result[:error] },
      status: result[:success] ? 'testing' : 'draft'
    )

    result.merge(duration_ms: duration)
  end

  # ============================================
  # TRIGGER MATCHING
  # ============================================

  def matches_trigger?(event_data)
    case trigger_type
    when 'status_changed'
      matches_status_change?(event_data)
    when 'field_changed'
      matches_field_change?(event_data)
    when 'record_created', 'record_updated', 'form_submit', 'webhook'
      true  # These always match if the trigger type matches
    else
      false
    end
  end

  # ============================================
  # SERIALIZATION
  # ============================================

  def to_preview
    {
      id: id,
      name: name,
      slug: slug,
      trigger_type: trigger_type,
      trigger_description: trigger_description,
      status: status,
      is_tested: is_tested,
      execution_count: execution_count,
      success_rate: (success_rate * 100).round(1),
      last_executed_at: last_executed_at,
      code_preview: code&.truncate(200)
    }
  end

  def trigger_description
    case trigger_type
    when 'record_created'
      "When a new #{module_name} is created"
    when 'record_updated'
      "When a #{module_name} is updated"
    when 'status_changed'
      from = trigger_config['from'] || 'any'
      to = trigger_config['to'] || 'any'
      "When #{module_name} status changes from '#{from}' to '#{to}'"
    when 'field_changed'
      field = trigger_config['field'] || 'any field'
      "When #{field} changes on #{module_name}"
    when 'schedule'
      trigger_config['schedule'] || 'On schedule'
    when 'webhook'
      "When webhook is called"
    when 'form_submit'
      "When form is submitted"
    when 'manual'
      "Manual trigger"
    else
      trigger_type.humanize
    end
  end

  # ============================================
  # EXCEPTION CLASS
  # ============================================

  class InvalidTransition < StandardError; end

  private

  def generate_slug
    return if slug.present?
    base_slug = name.to_s.parameterize
    self.slug = base_slug
    
    counter = 1
    while AutomationCode.exists?(entity_id: entity_id, slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def increment_version
    self.code_version = (code_version || 0) + 1
    self.code_generated_at = Time.current
  end

  def validate_code_syntax
    return if code.blank?

    begin
      # Try to parse the code to check for syntax errors
      RubyVM::InstructionSequence.compile(code)
    rescue SyntaxError => e
      errors.add(:code, "has syntax error: #{e.message}")
    end
  end

  def validate_trigger_config
    case trigger_type
    when 'status_changed'
      unless trigger_config['to'].present? || trigger_config['from'].present?
        errors.add(:trigger_config, "must specify 'from' and/or 'to' status for status_changed trigger")
      end
    when 'field_changed'
      unless trigger_config['field'].present?
        errors.add(:trigger_config, "must specify 'field' for field_changed trigger")
      end
    when 'schedule'
      unless trigger_config['schedule'].present? || trigger_config['cron'].present?
        errors.add(:trigger_config, "must specify 'schedule' or 'cron' for schedule trigger")
      end
    end
  end

  def matches_status_change?(event_data)
    return false unless event_data[:changes].is_a?(Hash)
    return false unless event_data[:changes]['status'].present?

    old_status, new_status = event_data[:changes]['status']
    
    from_matches = trigger_config['from'].blank? || trigger_config['from'] == old_status
    to_matches = trigger_config['to'].blank? || trigger_config['to'] == new_status
    
    from_matches && to_matches
  end

  def matches_field_change?(event_data)
    return false unless event_data[:changes].is_a?(Hash)
    
    field = trigger_config['field']
    return false unless field.present?
    
    event_data[:changes].key?(field) || event_data[:changes].key?(field.to_sym)
  end

  def module_name
    app_module&.name || 'record'
  end

  def default_sample_input
    {
      record: { id: 1, name: 'Test Record', status: 'active' },
      changes: {},
      user_id: created_by_id,
      timestamp: Time.current.iso8601
    }
  end

  def calculate_avg_time(new_duration)
    return new_duration if avg_execution_time_ms.nil? || execution_count <= 1
    return avg_execution_time_ms if new_duration.nil?

    # Exponential moving average
    alpha = 0.2
    (alpha * new_duration) + ((1 - alpha) * avg_execution_time_ms)
  end
end

