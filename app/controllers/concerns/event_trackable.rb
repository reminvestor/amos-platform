# frozen_string_literal: true

# EventTrackable - Controller concern for tracking user events
#
# Usage:
#   class MyController < ApplicationController
#     include EventTrackable
#
#     def create
#       # ... your logic ...
#       track_event("campaign_created", category: "feature", properties: { campaign_id: @campaign.id })
#     end
#   end
#
# Valid categories: onboarding, navigation, feature, conversion, billing
module EventTrackable
  extend ActiveSupport::Concern

  private

  # Track a user event by enqueueing a background job
  #
  # @param event_name [String] Name of the event (e.g., "button_click", "campaign_created")
  # @param category [String] Event category (onboarding, navigation, feature, conversion, billing)
  # @param properties [Hash] Optional event properties/metadata
  def track_event(event_name, category:, properties: {})
    # Determine entity_id - prefer current_entity, fall back to user's entity
    entity_id = if respond_to?(:current_entity) && current_entity
                  current_entity.id
                elsif respond_to?(:current_user) && current_user&.entity_id
                  current_user.entity_id
                else
                  nil
                end

    # Enqueue background job to persist the event
    TrackUserEventJob.perform_later(
      user_id: current_user&.id,
      entity_id: entity_id,
      event_name: event_name,
      event_category: category,
      properties: properties,
      session_id: session&.id&.to_s,
      referrer: request&.referer,
      user_agent: request&.user_agent
    )
  end
end
