# frozen_string_literal: true

# AutomationCodeExecutor - Executes automation code safely
#
# This is the main entry point for running automations.
# It handles:
# - Validation that the automation can run
# - Creating execution records for auditing
# - Running the code in the sandbox
# - Updating execution statistics
#
class AutomationCodeExecutor
  attr_reader :automation, :options

  def initialize(automation, options = {})
    @automation = automation
    @options = options
    @user = options[:user]
    @dry_run = options[:dry_run] || false
    @trigger_source = options[:trigger_source] || 'manual'
  end

  # Execute the automation with the given trigger data
  def execute!(trigger_data)
    # Validate automation is runnable
    unless can_execute?
      return error_result("Automation cannot execute: #{@execution_error}")
    end

    # Create execution record
    execution = create_execution_record(trigger_data)

    # Run in sandbox
    start_time = Time.current
    result = run_in_sandbox(trigger_data)
    duration_ms = ((Time.current - start_time) * 1000).round(2)

    # Update execution record
    execution.complete!(result)

    # Update automation statistics (unless dry run)
    unless @dry_run
      automation.record_execution!(result, duration_ms: duration_ms)
    end

    # Return the result
    result.merge(
      execution_id: execution.id,
      automation_id: automation.id,
      automation_name: automation.name
    )
  rescue => e
    Rails.logger.error "[AutomationCodeExecutor] Unhandled error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    
    # Record the error
    automation.record_error!(e) unless @dry_run

    error_result(e.message)
  end

  # Test an automation without recording stats
  def test!(sample_data = nil)
    @dry_run = true
    @trigger_source = 'test'
    
    data = sample_data || automation.sample_input || default_sample_data
    execute!(data)
  end

  # Check if this automation should fire for given event data
  def should_fire?(event_type, event_data)
    return false unless automation.active?
    return false unless automation.trigger_type == event_type || compatible_trigger?(event_type)
    return false unless automation.matches_trigger?(event_data)
    
    true
  end

  private

  def can_execute?
    if automation.nil?
      @execution_error = "Automation not found"
      return false
    end

    unless automation.active? || @dry_run
      @execution_error = "Automation is not active (status: #{automation.status})"
      return false
    end

    if automation.code.blank?
      @execution_error = "No code defined"
      return false
    end

    true
  end

  def create_execution_record(trigger_data)
    AutomationExecution.create!(
      automation_code: automation,
      entity: automation.entity,
      triggered_by: @user,
      trigger_source: @trigger_source,
      trigger_data: sanitize_trigger_data(trigger_data),
      status: 'running',
      started_at: Time.current
    )
  end

  def run_in_sandbox(trigger_data)
    sandbox = AutomationSandbox.new(
      automation: automation,
      trigger_data: trigger_data,
      user: @user
    )

    sandbox.execute
  end

  def error_result(message)
    {
      success: false,
      error: message,
      data: nil
    }
  end

  def sanitize_trigger_data(data)
    # Remove sensitive fields from trigger data before logging
    sensitive_keys = %w[password token secret key api_key access_token]
    
    data.deep_transform_values do |value|
      if value.is_a?(Hash)
        value.except(*sensitive_keys)
      else
        value
      end
    end
  rescue
    data
  end

  def compatible_trigger?(event_type)
    # status_changed and field_changed are compatible with record_updated
    return true if event_type == 'record_updated' && 
                   %w[status_changed field_changed].include?(automation.trigger_type)
    false
  end

  def default_sample_data
    {
      record: { id: 1, name: 'Test Record', status: 'active' },
      changes: { status: ['draft', 'active'] },
      user_id: @user&.id,
      timestamp: Time.current.iso8601
    }
  end
end

