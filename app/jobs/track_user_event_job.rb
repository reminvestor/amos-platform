class TrackUserEventJob < ApplicationJob
  queue_as :default

  def perform(user_id:, entity_id:, event_name:, event_category:, properties: {}, session_id: nil, referrer: nil, user_agent: nil)
    UserEvent.create!(
      user_id: user_id,
      entity_id: entity_id,
      event_name: event_name,
      event_category: event_category,
      properties: properties,
      session_id: session_id,
      referrer: referrer,
      user_agent: user_agent
    )
  rescue => e
    Rails.logger.error "[TrackUserEventJob] Failed to track #{event_name}: #{e.message}"
  end
end
