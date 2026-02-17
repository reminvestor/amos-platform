# frozen_string_literal: true

# TrackUserEventJob - Background job for tracking user events
#
# Persists user events to the database for analytics and observability.
# Called by EventTrackable concern when controllers track user actions.
#
# Usage:
#   TrackUserEventJob.perform_later(
#     user_id: current_user.id,
#     entity_id: current_entity.id,
#     event_name: "campaign_created",
#     event_category: "feature",
#     properties: { campaign_id: 123 }
#   )
class TrackUserEventJob < ApplicationJob
  queue_as :default

  # Track a user event by persisting it to the database
  #
  # @param user_id [Integer] ID of the user who triggered the event (nil for anonymous)
  # @param entity_id [Integer] ID of the entity context
  # @param event_name [String] Name of the event (e.g., "button_click", "campaign_created")
  # @param event_category [String] Category (onboarding, navigation, feature, conversion, billing)
  # @param properties [Hash] Optional event properties/metadata
  # @param session_id [String] User's session ID
  # @param referrer [String] HTTP referrer
  # @param user_agent [String] User's browser/device info
  def perform(user_id:, entity_id:, event_name:, event_category:, properties: {}, session_id: nil, referrer: nil, user_agent: nil)
    # Create the user event record
    UserEvent.create!(
      user_id: user_id,
      entity_id: entity_id,
      event_name: event_name,
      event_category: event_category,
      properties: properties,
      session_id: session_id,
      referrer: referrer,
      user_agent: user_agent,
      occurred_at: Time.current
    )

    Rails.logger.info(
      "[UserEvent] Tracked: #{event_name} (category: #{event_category}, user: #{user_id}, entity: #{entity_id})"
    )
  rescue ActiveRecord::RecordInvalid => e
    # Log validation errors but don't fail the job
    Rails.logger.warn(
      "[UserEvent] Failed to track event: #{e.message} (event: #{event_name}, user: #{user_id})"
    )
  rescue => e
    # Log unexpected errors
    Rails.logger.error(
      "[UserEvent] Unexpected error tracking event: #{e.message} (event: #{event_name}, user: #{user_id})"
    )
    # Re-raise to retry the job
    raise e
  end
end
