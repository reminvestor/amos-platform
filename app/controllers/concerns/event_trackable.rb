module EventTrackable
  extend ActiveSupport::Concern

  private

  def track_event(event_name, category:, properties: {})
    TrackUserEventJob.perform_later(
      user_id: current_user&.id,
      entity_id: current_entity&.id || current_user&.entity_id,
      event_name: event_name,
      event_category: category,
      properties: properties,
      session_id: (session.id.to_s if respond_to?(:session, true) && session&.id),
      referrer: request.referer,
      user_agent: request.user_agent
    )
  end
end
