class SubscriptionEvent < ApplicationRecord
  belongs_to :entity

  # Event types
  EVENT_TYPES = %w[
    subscription_created
    subscription_updated
    subscription_cancelled
    subscription_reactivated
    plan_changed
    trial_started
    trial_ended
    payment_succeeded
    payment_failed
  ].freeze

  # Validations
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :stripe_event_id, uniqueness: true, allow_nil: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_event_type, ->(type) { where(event_type: type) }
  scope :by_stripe_event, ->(event_id) { where(stripe_event_id: event_id) }

  # Class method to log subscription events
  def self.log_event(entity:, event_type:, previous_status: nil, new_status: nil,
                     previous_plan: nil, new_plan: nil, stripe_event_id: nil,
                     metadata: {}, triggered_by: 'stripe_webhook')
    create!(
      entity: entity,
      event_type: event_type,
      previous_status: previous_status,
      new_status: new_status,
      previous_plan: previous_plan,
      new_plan: new_plan,
      stripe_event_id: stripe_event_id,
      metadata: metadata,
      triggered_by: triggered_by
    )
  rescue ActiveRecord::RecordNotUnique
    # Ignore duplicate Stripe events (webhook retries)
    Rails.logger.info "Duplicate subscription event ignored: #{stripe_event_id}"
    nil
  end

  # Helper methods
  def status_changed?
    previous_status != new_status
  end

  def plan_changed?
    previous_plan != new_plan
  end

  def subscription_started?
    event_type == 'subscription_created' || event_type == 'trial_started'
  end

  def subscription_ended?
    event_type == 'subscription_cancelled' || new_status == 'cancelled'
  end
end
