class AgentLightningWebhookLog < ApplicationRecord
  belongs_to :agent_lightning_webhook

  validates :event_type, presence: true
  validates :payload, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending success failed] }

  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_event, ->(event) { where(event_type: event) }
  scope :successful, -> { where(status: 'success') }
  scope :failed, -> { where(status: 'failed') }

  def success?
    status == 'success'
  end

  def failed?
    status == 'failed'
  end

  def mark_success
    update!(status: 'success', completed_at: Time.current)
  end

  def mark_failed(error_msg = nil)
    update!(
      status: 'failed',
      completed_at: Time.current,
      error_message: error_msg
    )
  end
end
