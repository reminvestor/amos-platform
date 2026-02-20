# frozen_string_literal: true

# UserEvent - Tracks user actions and behaviors for analytics
#
# Created by EventTrackable concern when controllers track user interactions.
# Used for:
# - User journey analytics (onboarding flow, feature discovery)
# - Conversion funnels (signup → activation → engagement)
# - Cohort analysis
# - Feature usage tracking
#
# Schema (to be created):
# - user_id: Which user performed the action
# - entity_id: Which organization/tenant
# - event_name: Name of the event (e.g., "button_click", "feature_viewed")
# - event_category: Category (onboarding, navigation, feature, conversion, billing)
# - properties: JSONB with event-specific data
# - session_id: User's session ID
# - referrer: HTTP referrer
# - user_agent: Browser/device info
# - occurred_at: When the event happened
# - created_at: When the record was created
class UserEvent < ApplicationRecord
  # Associations
  belongs_to :user, optional: true  # Optional for anonymous events
  belongs_to :entity, optional: true

  # Validations
  validates :event_name, presence: true
  validates :event_category, presence: true,
                             inclusion: { in: %w[onboarding navigation feature conversion billing] }

  # Scopes
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :by_category, ->(category) { where(event_category: category) }
  scope :by_name, ->(name) { where(event_name: name) }
  scope :recent, -> { order(occurred_at: :desc) }
  scope :this_week, -> { where('occurred_at >= ?', 1.week.ago) }
  scope :in_period, ->(start_date, end_date) { where(occurred_at: start_date..end_date) }

  # Class Methods

  # Get event counts by name
  def self.counts_by_name
    group(:event_name).count
  end

  # Get event counts by category
  def self.counts_by_category
    group(:event_category).count
  end

  # Funnel analysis - calculate conversion rate through a series of events
  #
  # @param steps [Array<String>] Event names in funnel order
  # @return [Hash] Conversion stats for each step
  #
  # @example
  #   UserEvent.for_entity(entity.id).funnel_analysis(['signup_started', 'email_confirmed', 'profile_completed'])
  #   # => {
  #   #   'signup_started' => { count: 100, conversion: 100.0 },
  #   #   'email_confirmed' => { count: 80, conversion: 80.0 },
  #   #   'profile_completed' => { count: 60, conversion: 60.0 }
  #   # }
  def self.funnel_analysis(steps)
    first_step_count = where(event_name: steps.first).distinct.count(:user_id).to_f

    steps.each_with_object({}) do |step, result|
      count = where(event_name: step).distinct.count(:user_id)
      conversion = first_step_count > 0 ? (count / first_step_count * 100).round(1) : 0.0

      result[step] = {
        count: count,
        conversion: conversion
      }
    end
  end

  # Cohort analysis - group users by a time period and track their behavior
  # Should be called on an entity-scoped relation: UserEvent.for_entity(id).cohort_analysis
  #
  # @param period [Symbol] :day, :week, or :month
  # @return [Hash] Users grouped by cohort with event counts
  def self.cohort_analysis(period: :week)
    group_sql = case period
                when :day
                  "DATE_TRUNC('day', occurred_at)"
                when :week
                  "DATE_TRUNC('week', occurred_at)"
                when :month
                  "DATE_TRUNC('month', occurred_at)"
                else
                  raise ArgumentError, "Invalid period: #{period}"
                end

    group(Arel.sql(group_sql)).count
  end
end
