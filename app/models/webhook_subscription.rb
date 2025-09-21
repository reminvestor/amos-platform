class WebhookSubscription < ApplicationRecord
  belongs_to :connection
  has_many :webhook_events, dependent: :destroy
  
  # Validations
  validates :endpoint_url, presence: true, format: { with: URI.regexp(%w[http https]) }
  validates :events, presence: true
  validates :status, presence: true
  
  # Enums
  enum :status, {
    active: 0,
    paused: 1,
    failed: 2,
    disabled: 3
  }
  
  # Scopes
  scope :active, -> { where(status: :active) }
  scope :for_event, ->(event_type) { where('events @> ?', [event_type].to_json) }
  
  # Default values
  after_initialize :set_defaults, if: :new_record?
  
  def matches_event?(event_type, payload = {})
    return false unless active?
    return false unless events.include?(event_type) || events.include?('*')
    
    # Check filters if present
    if filters.present? && payload.present?
      filters.all? do |key, value|
        payload.dig(*key.split('.')).to_s == value.to_s
      end
    else
      true
    end
  end
  
  def trigger!(event_type, payload)
    return unless matches_event?(event_type, payload)
    
    # Queue webhook delivery job
    DeliverWebhookJob.perform_later(self, event_type, payload)
    
    update!(last_triggered_at: Time.current)
  end
  
  def mark_failed!
    increment!(:retry_count)
    
    if retry_count >= 5
      failed!
    end
  end
  
  def reset_retry_count!
    update!(retry_count: 0)
  end
  
  def verify_signature(payload, signature)
    return true if signing_secret.blank?
    
    expected = generate_signature(payload)
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end
  
  def generate_signature(payload)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, payload)}"
  end
  
  private
  
  def set_defaults
    self.status ||= :active
    self.events ||= []
    self.filters ||= {}
    self.metadata ||= {}
    self.retry_count ||= 0
  end
end