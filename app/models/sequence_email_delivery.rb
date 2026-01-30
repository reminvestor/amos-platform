# frozen_string_literal: true

# SequenceEmailDelivery
#
# Tracks individual email sends within email sequences.
# Similar to EmailDelivery for campaigns, this tracks delivery status,
# opens, clicks, bounces for each sequence step sent to each contact.
#
class SequenceEmailDelivery < ApplicationRecord
  belongs_to :email_sequence
  belongs_to :sequence_step
  belongs_to :sequence_enrollment
  belongs_to :contact
  belongs_to :entity

  # Status options (same as EmailDelivery for consistency)
  STATUSES = %w[pending sent delivered opened clicked failed bounced].freeze

  # Validations
  validates :status, inclusion: { in: STATUSES }
  validates :ses_message_id, uniqueness: true, allow_nil: true

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :sent, -> { where(status: %w[sent delivered opened clicked]) }
  scope :delivered, -> { where(status: %w[delivered opened clicked]) }
  scope :opened, -> { where.not(opened_at: nil) }
  scope :clicked, -> { where.not(clicked_at: nil) }
  scope :failed, -> { where(status: %w[failed bounced]) }
  scope :by_sequence, ->(sequence_id) { where(email_sequence_id: sequence_id) }
  scope :by_step, ->(step_id) { where(sequence_step_id: step_id) }
  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) }

  # Methods
  def opened?
    opened_at.present?
  end

  def clicked?
    clicked_at.present?
  end

  def mark_as_sent(message_id = nil)
    update(
      status: "sent",
      sent_at: Time.current,
      ses_message_id: message_id
    )
  end

  def mark_as_delivered
    update(status: "delivered", delivered_at: Time.current)
  end

  def mark_as_opened
    return if opened?
    
    update(status: "opened", opened_at: Time.current)
    
    # Update step metrics
    sequence_step&.increment_opened!
    
    # Update contact engagement
    contact&.update(last_engagement_at: Time.current) if contact&.respond_to?(:last_engagement_at)
  end

  def mark_as_clicked
    mark_as_opened unless opened?
    return if clicked?
    
    update(status: "clicked", clicked_at: Time.current)
    
    # Update step metrics
    sequence_step&.increment_clicked!
  end

  def mark_as_failed(reason = nil)
    update(status: "failed", error_message: reason)
  end

  def mark_as_bounced(reason = nil)
    update(status: "bounced", error_message: reason)
    
    # Cancel the enrollment
    sequence_enrollment&.cancel!
    
    # Mark contact as bounced
    contact&.update(
      status: 'bounced',
      opted_out: true,
      opted_out_at: Time.current
    )
  end

  def mark_as_complaint
    # Mark contact as opted out due to spam complaint
    contact&.update(
      opted_out: true,
      opted_out_at: Time.current
    )
    
    # Cancel the enrollment
    sequence_enrollment&.cancel!
    
    update(status: "failed", error_message: "Spam complaint")
  end
end
