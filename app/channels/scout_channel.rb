class ScoutChannel < ApplicationCable::Channel
  def subscribed
    # Stream for a specific Scout session
    if params[:session_id].present?
      stream_from "scout_channel_#{params[:session_id]}"
      Rails.logger.info "ScoutChannel: Subscribed to scout_channel_#{params[:session_id]}"
      
      # Also stream for user-specific broadcasts (memory hints, notifications)
      if current_user&.id
        stream_from "scout_user_#{current_user.id}"
        Rails.logger.info "ScoutChannel: Also subscribed to scout_user_#{current_user.id}"
      end
    else
      reject
    end
  end

  def unsubscribed
    # Cleanup when channel is unsubscribed
    Rails.logger.info "ScoutChannel: Unsubscribed from scout_channel_#{params[:session_id]}"
  end
  
  # Handle memory hint acknowledgment from client
  def acknowledge_memory_hint(data)
    Rails.logger.info "ScoutChannel: Memory hint acknowledged: #{data['hint_id']}"
  end
  
  # Static method to broadcast to a session
  def self.broadcast_to(session_id, data)
    channel_name = "scout_channel_#{session_id}"
    
    # Log the broadcast attempt with adapter info
    begin
      pubsub = ActionCable.server.pubsub
      adapter_class = pubsub.class.name
      
      Rails.logger.info "[ActionCable] Broadcasting to #{channel_name}"
      Rails.logger.info "[ActionCable] Adapter: #{adapter_class}"
      Rails.logger.info "[ActionCable] Message type: #{data[:type]}"
      
      # Use the built-in ActionCable broadcast
      ActionCable.server.broadcast(channel_name, data)
      
      Rails.logger.info "ScoutChannel: ✅ Broadcast sent to #{channel_name}: #{data[:type]}"
    rescue => e
      Rails.logger.error "[ActionCable] ❌ Broadcast failed: #{e.message}"
      Rails.logger.error "[ActionCable] Backtrace: #{e.backtrace.first(3).join("\n")}"
      raise
    end
  end
end
