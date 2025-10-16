class WebhookEvent < ApplicationRecord
  belongs_to :webhook_subscription

  # Validations
  validates :event_type, presence: true
  validates :payload, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :delivered, -> { where.not(delivered_at: nil) }
  scope :failed, -> { where(delivered_at: nil).where.not(error_message: nil) }
  scope :pending, -> { where(delivered_at: nil, error_message: nil) }

  def delivered?
    delivered_at.present?
  end

  def failed?
    delivered_at.nil? && error_message.present?
  end

  def pending?
    delivered_at.nil? && error_message.nil?
  end

  def mark_delivered!(response)
    update!(
      delivered_at: Time.current,
      response_status: response.code,
      response_body: response.body.truncate(10_000),
      error_message: nil
    )
  end

  def mark_failed!(error)
    update!(
      error_message: error.to_s.truncate(1000),
      response_status: nil,
      response_body: nil
    )
  end
end
