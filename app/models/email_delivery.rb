class EmailDelivery < ApplicationRecord
  belongs_to :campaign
  belongs_to :contact
  belongs_to :email_template, optional: true

  # Generate secure unsubscribe token before creation
  before_create :generate_unsubscribe_token

  # Status options
  STATUSES = %w[pending sent delivered opened clicked failed bounced].freeze

  # Validations
  validates :status, inclusion: { in: STATUSES }
  validates :unsubscribe_token, uniqueness: true, allow_nil: true

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :sent, -> { where(status: [ "sent", "delivered", "opened", "clicked" ]) }
  scope :opened, -> { where.not(opened_at: nil) }
  scope :clicked, -> { where.not(clicked_at: nil) }
  scope :failed, -> { where(status: [ "failed", "bounced" ]) }

  # Methods
  def opened?
    opened_at.present?
  end

  def clicked?
    clicked_at.present?
  end

  def mark_as_sent
    update(status: "sent", sent_at: Time.current)
  end

  def mark_as_opened
    update(status: "opened", opened_at: Time.current) unless opened?
  end

  def mark_as_clicked
    mark_as_opened unless opened?
    update(status: "clicked", clicked_at: Time.current) unless clicked?
  end

  def mark_as_failed(reason = nil)
    update(status: "failed", error_message: reason)
  end

  def mark_as_bounced(reason = nil)
    update(status: "bounced", error_message: reason)
  end

  private

  def generate_unsubscribe_token
    self.unsubscribe_token ||= SecureRandom.urlsafe_base64(32)
  end
end
