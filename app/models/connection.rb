class Connection < ApplicationRecord
  belongs_to :entity
  belongs_to :integration
  belongs_to :user, optional: true  # User who owns this connection (e.g., their Gmail, their Stripe)
  has_many :integration_credentials, dependent: :destroy
  has_many :integration_logs, dependent: :destroy
  has_many :webhook_subscriptions, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :status, presence: true

  # Enums
  enum :status, {
    disconnected: 0,
    connected: 1,
    limited: 2,    # Rate limited or degraded
    failing: 3      # Persistent errors
  }

  # Scopes
  scope :active, -> { where(status: [ :connected, :limited ]) }
  scope :with_active_credentials, -> { joins(:integration_credentials).where(integration_credentials: { status: :active }) }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  def active_credential
    integration_credentials.active.order(created_at: :desc).first
  end

  def can_execute?(operation_id, agent_role = nil)
    # Check if operation is allowed for this connection
    return false unless allowed_operations.blank? || allowed_operations.include?(operation_id)

    # Check policy rules
    PolicyEngine.check(self, operation_id, agent_role)
  end

  def within_rate_limit?
    # Simple rate limit check - can be enhanced with Redis
    recent_calls = integration_logs.where(created_at: 1.hour.ago..).count
    rate_limit = rate_limit_tier_config[:hourly_limit] || 1000
    recent_calls < rate_limit
  end

  def within_daily_budget?
    return true if daily_write_budget.nil? || daily_write_budget <= 0

    todays_writes = integration_logs
      .where(created_at: Time.current.beginning_of_day..)
      .where(http_method: %w[POST PUT PATCH DELETE])
      .count

    todays_writes < daily_write_budget
  end

  def rate_limit_tier_config
    case rate_limit_tier
    when "basic"
      { hourly_limit: 100, daily_limit: 1000 }
    when "standard"
      { hourly_limit: 1000, daily_limit: 10000 }
    when "premium"
      { hourly_limit: 10000, daily_limit: 100000 }
    else
      { hourly_limit: 1000, daily_limit: 10000 }
    end
  end

  def available_operations
    # Get operations that this connection is allowed to use (and are enabled)
    operation_ids = allowed_operations.presence || integration.integration_operations.pluck(:operation_id)
    integration.integration_operations.where(operation_id: operation_ids, is_enabled: true)
  end

  def update_health_status!
    # Check recent error rate - be more lenient to avoid confusing the AI
    recent_logs = integration_logs.where(created_at: 1.hour.ago..)
    error_count = recent_logs.where("response_status >= 400").count
    total_count = recent_logs.count

    # Only update status if we have enough samples (at least 20 requests)
    # This prevents single failures from marking the integration as "failing"
    if total_count >= 20
      error_rate = error_count.to_f / total_count

      # More lenient thresholds - only fail if >80% of requests are failing
      if error_rate > 0.8
        failing! unless failing?
        Rails.logger.warn "[Connection] #{name} marked as failing (#{(error_rate * 100).round}% error rate)"
      elsif error_rate > 0.3
        limited! unless limited?
        Rails.logger.info "[Connection] #{name} marked as limited (#{(error_rate * 100).round}% error rate)"
      else
        connected! unless connected?
      end
    elsif connected? == false && total_count < 5
      # If we have few requests and status is not connected, reset to connected
      # This gives the integration a fresh chance
      connected!
      Rails.logger.info "[Connection] #{name} reset to connected (insufficient data to determine status)"
    end

    update!(last_health_check: Time.current)
  end

  def test_connection!
    # Use the API service to test the connection
    api_service = IntegrationApiService.new(self)
    result = api_service.test_connection

    if result[:success]
      connected!
      update!(last_health_check: Time.current)
    else
      failing!
    end

    result
  rescue => e
    failing!
    { success: false, error: e.message }
  end

  private

  def set_defaults
    self.status ||= :disconnected
    self.settings ||= {}
    self.allowed_operations ||= []
    self.scopes_granted ||= []
    self.scopes_requested ||= []
    self.metadata ||= {}
    self.rate_limit_tier ||= "standard"
  end
end
