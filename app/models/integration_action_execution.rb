# frozen_string_literal: true

# IntegrationActionExecution - Audit trail for action executions
#
# Tracks every execution of an IntegrationAction, including:
# - What inputs were provided
# - What parameters were sent to the API (after mapping)
# - What response came back
# - Success/failure status
# - Timing information
#
class IntegrationActionExecution < ApplicationRecord
  belongs_to :integration_action
  belongs_to :connection
  belongs_to :user, optional: true
  belongs_to :entity, optional: true

  # Status enum
  enum :status, {
    pending: 0,
    success: 1,
    failed: 2,
    rate_limited: 3
  }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :successful, -> { where(status: :success) }
  scope :failed_executions, -> { where(status: [:failed, :rate_limited]) }

  # ============================================
  # STATUS MANAGEMENT
  # ============================================

  def complete!
    update!(
      status: :success,
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def fail!(message)
    update!(
      status: :failed,
      error_message: message,
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def rate_limit!
    update!(
      status: :rate_limited,
      error_message: 'Rate limit exceeded',
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  # ============================================
  # HELPERS
  # ============================================

  def duration_seconds
    return nil unless duration_ms
    (duration_ms / 1000.0).round(2)
  end

  def action_name
    integration_action&.action_name
  end

  def integration_name
    integration_action&.integration&.name
  end

  private

  def calculate_duration
    return nil unless started_at
    ((Time.current - started_at) * 1000).round(0)
  end
end

