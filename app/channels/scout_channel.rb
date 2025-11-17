class ScoutChannel < ApplicationCable::Channel
  def subscribed
    # Stream for a specific Scout session
    if params[:session_id].present?
      stream_from "scout_channel_#{params[:session_id]}"
      Rails.logger.info "ScoutChannel: Subscribed to scout_channel_#{params[:session_id]}"
    else
      reject
    end
  end

  def unsubscribed
    # Cleanup when channel is unsubscribed
    Rails.logger.info "ScoutChannel: Unsubscribed from scout_channel_#{params[:session_id]}"
  end
  
  # Static method to broadcast to a session
  def self.broadcast_to(session_id, data)
    # Use the built-in ActionCable broadcast
    ActionCable.server.broadcast("scout_channel_#{session_id}", data)
    Rails.logger.info "ScoutChannel: Broadcasting to scout_channel_#{session_id}: #{data[:type]}"
  end
end
