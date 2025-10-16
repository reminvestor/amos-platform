class SequenceStep < ApplicationRecord
  belongs_to :email_sequence
  belongs_to :email_template, optional: true

  # JSONB metadata handling - Rails 8.0 compatible
  attribute :metadata, :json

  # Validations
  validates :step_number, presence: true, numericality: { greater_than_or_equal_to: 1 }
  validates :delay_hours, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :step_number, uniqueness: { scope: :email_sequence_id }

  # At least one of email_template or subject+body must be present
  validate :has_content

  # Scopes
  scope :ordered, -> { order(step_number: :asc) }
  scope :by_sequence, ->(sequence_id) { where(email_sequence_id: sequence_id) }

  # Methods
  def delay_in_days
    (delay_hours.to_f / 24).round(2)
  end

  def effective_subject
    subject.presence || email_template&.subject
  end

  def effective_body
    body.presence || email_template&.body
  end

  def has_template?
    email_template_id.present?
  end

  def increment_sent!
    increment!(:sent_count)
  end

  def increment_opened!
    increment!(:opened_count)
  end

  def increment_clicked!
    increment!(:clicked_count)
  end

  def open_rate
    return 0 if sent_count.zero?
    (opened_count.to_f / sent_count * 100).round(2)
  end

  def click_rate
    return 0 if sent_count.zero?
    (clicked_count.to_f / sent_count * 100).round(2)
  end

  private

  def has_content
    unless email_template_id.present? || (subject.present? && body.present?)
      errors.add(:base, 'Must have either an email template or both subject and body')
    end
  end
end
