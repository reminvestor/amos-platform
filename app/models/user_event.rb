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

  # Funnel analysis: conversion rate between two events (entity-scoped)
  def self.conversion_rate(from_event, to_event, entity:, period: 30.days)
    start_time = period.ago
    scope = where(entity_id: entity.id, created_at: start_time..)
    from_users = scope.where(event_name: from_event).distinct.count(:user_id)
    to_users = scope.where(event_name: to_event).distinct.count(:user_id)
    return 0.0 if from_users.zero?
    (to_users.to_f / from_users * 100).round(1)
  end

  # Cohort analysis (entity-scoped)
  def self.by_cohort(entity:, start_date:, end_date:)
    where(entity_id: entity.id, created_at: start_date..end_date)
  end
end
