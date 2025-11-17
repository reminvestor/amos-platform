class AgentLightningWebhook < ApplicationRecord
  belongs_to :entity
  has_many :agent_lightning_webhook_logs, dependent: :destroy

  validates :event_type, presence: true, inclusion: {
    in: %w[training_completed training_failed success_rate_improved success_rate_degraded
            cost_reduced cost_increased token_limit_exceeded error_rate_high]
  }
  validates :url, presence: true, uniqueness: { scope: :entity_id }

  scope :active, -> { where(active: true) }
  scope :by_event, ->(event) { where(event_type: event) }
  scope :recent, -> { order(created_at: :desc) }

  def test_webhook
    service = AgentLightningWebhookService.new(entity)
    service.test_webhook(url)
  end

  def recent_logs(limit = 10)
    agent_lightning_webhook_logs.recent.limit(limit)
  end

  def success_rate
    total = agent_lightning_webhook_logs.count
    return 0 if total.zero?
    (agent_lightning_webhook_logs.where(status: 'success').count.to_f / total * 100).round(1)
  end
end
