class SequenceEnrollment < ApplicationRecord
  belongs_to :email_sequence
  belongs_to :contact
  belongs_to :entity

  # Status options
  STATUSES = %w[pending active completed paused cancelled].freeze

  attribute :status, :string, default: "pending"
  attribute :current_step_number, :integer, default: 0

  # Callbacks to keep sequence counts in sync
  after_save :update_sequence_counts, if: :saved_change_to_status?

  # Validations
  validates :status, inclusion: { in: STATUSES }
  validates :contact_id, uniqueness: { scope: :email_sequence_id, message: 'is already enrolled in this sequence' }
  validates :current_step_number, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :active, -> { where(status: 'active') }
  scope :completed, -> { where(status: 'completed') }
  scope :paused, -> { where(status: 'paused') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :ready_to_send, -> { where(status: ['pending', 'active']).where('next_send_at <= ?', Time.current) }
  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :by_sequence, ->(sequence_id) { where(email_sequence_id: sequence_id) }

  # Methods
  def start!
    return false unless status == 'pending'

    update!(
      status: 'active',
      started_at: Time.current,
      next_send_at: Time.current
    )
  end

  def complete!
    update!(
      status: 'completed',
      completed_at: Time.current,
      next_send_at: nil
    )
  end

  def pause!
    update!(status: 'paused')
  end

  def resume!
    return false unless status == 'paused'
    update!(status: 'active')
  end

  def cancel!
    update!(
      status: 'cancelled',
      next_send_at: nil
    )
  end

  def advance_to_next_step!
    next_step = email_sequence.sequence_steps.find_by(step_number: current_step_number + 1)

    if next_step
      # Move to next step
      update!(
        current_step_number: next_step.step_number,
        next_send_at: Time.current + next_step.delay_hours.hours,
        last_email_sent_at: Time.current
      )
    else
      # No more steps - complete the enrollment
      complete!
    end
  end

  def current_step
    email_sequence.sequence_steps.find_by(step_number: current_step_number)
  end

  def next_step
    email_sequence.sequence_steps.find_by(step_number: current_step_number + 1)
  end

  def progress_percentage
    total_steps = email_sequence.step_count
    return 0 if total_steps.zero?

    (current_step_number.to_f / total_steps * 100).round(2)
  end

  def days_in_sequence
    return 0 unless started_at
    ((Time.current - started_at) / 1.day).round(2)
  end

  private

  def update_sequence_counts
    email_sequence.update_enrollment_counts if email_sequence.present?
  rescue => e
    Rails.logger.warn "[SequenceEnrollment] Failed to update sequence counts: #{e.message}"
  end
end
