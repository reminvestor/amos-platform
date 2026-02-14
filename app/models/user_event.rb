class UserEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :entity, optional: true

  validates :event_name, presence: true
  validates :event_category, presence: true, inclusion: {
    in: %w[onboarding navigation feature conversion billing]
  }

  scope :for_category, ->(cat) { where(event_category: cat) }
  scope :for_event, ->(name) { where(event_name: name) }
  scope :recent, -> { order(created_at: :desc) }
  scope :in_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Funnel analysis: conversion rate between two events
  def self.conversion_rate(from_event, to_event, period: 30.days)
    start_time = period.ago
    from_users = where(event_name: from_event, created_at: start_time..).distinct.count(:user_id)
    to_users = where(event_name: to_event, created_at: start_time..).distinct.count(:user_id)
    return 0.0 if from_users.zero?
    (to_users.to_f / from_users * 100).round(1)
  end

  # Cohort analysis
  def self.by_cohort(start_date, end_date)
    where(created_at: start_date..end_date)
  end

  # Track an event (class method for convenience)
  def self.track(user, event_name, category:, properties: {}, session_id: nil, request: nil)
    create!(
      user: user,
      entity: user&.entity,
      event_name: event_name,
      event_category: category,
      properties: properties,
      session_id: session_id,
      referrer: request&.referer,
      user_agent: request&.user_agent
    )
  rescue => e
    Rails.logger.error "[UserEvent] Failed to track #{event_name}: #{e.message}"
    nil
  end
end
