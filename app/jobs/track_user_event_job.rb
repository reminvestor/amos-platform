class TrackUserEventJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordInvalid

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
  end
end
