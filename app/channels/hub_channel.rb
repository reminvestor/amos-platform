# frozen_string_literal: true

# HubChannel
#
# ActionCable channel for the Collaborative Intelligence Hub.
# Handles real-time messaging, presence, and agent activity updates.
#
class HubChannel < ApplicationCable::Channel
  def subscribed
    if params[:thread_id].present?
      # Subscribe to a specific thread
      subscribe_to_thread(params[:thread_id])
    elsif params[:entity_id].present?
      # Subscribe to entity-wide updates (presence, activity)
      subscribe_to_entity(params[:entity_id])
    else
      reject
    end
  end

  def unsubscribed
    # Mark user as offline when they disconnect
    if current_user && @entity_id
      update_presence('offline')
    end
  end

  # ============================================
  # CLIENT ACTIONS
  # ============================================

  # Send a message to a thread
  def send_message(data)
    thread = HubThread.find(data['thread_id'])
    
    # Verify user is participant
    unless thread.participant?(current_user)
      transmit({ error: 'Not a participant in this thread' })
      return
    end

    message = thread.add_message(
      sender: current_user,
      content: data['content'],
      message_type: data['message_type'] || 'text',
      reply_to_id: data['reply_to_id'],
      attachments: data['attachments'] || []
    )

    transmit({ success: true, message_id: message.id })
  end

  # Mark messages as read
  def mark_read(data)
    thread = HubThread.find(data['thread_id'])
    participant = thread.hub_participants.find_by(participant: current_user)
    
    if data['message_id']
      message = thread.hub_messages.find(data['message_id'])
      participant&.mark_read_up_to!(message)
    else
      participant&.mark_read!
    end

    transmit({ success: true, unread_count: participant&.unread_count || 0 })
  end

  # Update user presence
  def update_presence(data)
    status = data.is_a?(Hash) ? data['status'] : data
    presence = HubPresence.for_participant(current_user)
    
    case status
    when 'online'
      presence.go_online!(
        custom_status: data['status_message'],
        emoji: data['emoji']
      )
    when 'away'
      presence.go_away!
    when 'busy'
      presence.update!(status: 'busy')
    when 'offline'
      presence.go_offline!
    end
  end

  # Heartbeat to maintain presence
  def heartbeat(_data = nil)
    presence = HubPresence.for_participant(current_user)
    presence.heartbeat!
  end

  # Add reaction to a message
  def add_reaction(data)
    message = HubMessage.find(data['message_id'])
    message.add_reaction(current_user, data['emoji'])
  end

  # Remove reaction from a message
  def remove_reaction(data)
    message = HubMessage.find(data['message_id'])
    message.remove_reaction(current_user, data['emoji'])
  end

  # Start typing indicator
  def typing(data)
    thread_id = data['thread_id']
    
    ActionCable.server.broadcast(
      "hub_thread_#{thread_id}",
      {
        type: 'typing',
        user_id: current_user.id,
        user_name: current_user.name,
        thread_id: thread_id
      }
    )
  end

  # Stop typing indicator
  def stop_typing(data)
    thread_id = data['thread_id']
    
    ActionCable.server.broadcast(
      "hub_thread_#{thread_id}",
      {
        type: 'stop_typing',
        user_id: current_user.id,
        thread_id: thread_id
      }
    )
  end

  # ============================================
  # CLASS METHODS FOR BROADCASTING
  # ============================================

  class << self
    # Broadcast a message to a thread
    def broadcast_to_thread(thread_id, data)
      ActionCable.server.broadcast("hub_thread_#{thread_id}", data)
    end

    # Broadcast presence update to entity
    def broadcast_presence(entity_id, data)
      ActionCable.server.broadcast(
        "hub_entity_#{entity_id}",
        { type: 'presence_update', **data }
      )
    end

    # Broadcast agent activity to entity
    def broadcast_agent_activity(entity_id, data)
      ActionCable.server.broadcast(
        "hub_entity_#{entity_id}",
        { type: 'agent_activity', **data }
      )
    end

    # Broadcast to a specific user
    def broadcast_to_user(user_id, data)
      ActionCable.server.broadcast("hub_user_#{user_id}", data)
    end

    # Notify about new thread
    def broadcast_new_thread(entity_id, thread)
      ActionCable.server.broadcast(
        "hub_entity_#{entity_id}",
        {
          type: 'new_thread',
          thread: {
            id: thread.id,
            thread_type: thread.thread_type,
            subject: thread.subject,
            channel_id: thread.team_channel_id,
            started_by: {
              id: thread.started_by_id,
              type: thread.started_by_type,
              name: thread.started_by.respond_to?(:name) ? thread.started_by.name : nil
            }
          }
        }
      )
    end

    # Notify about handoff request
    def broadcast_handoff(user_id, message)
      ActionCable.server.broadcast(
        "hub_user_#{user_id}",
        {
          type: 'handoff_request',
          thread_id: message.hub_thread_id,
          message: message.as_broadcast_json
        }
      )
    end
  end

  private

  def subscribe_to_thread(thread_id)
    thread = HubThread.find_by(id: thread_id)
    
    unless thread&.participant?(current_user)
      reject
      return
    end

    @thread_id = thread_id
    stream_from "hub_thread_#{thread_id}"
    
    # Also stream user-specific notifications
    stream_from "hub_user_#{current_user.id}"
    
    Rails.logger.info "HubChannel: User #{current_user.id} subscribed to thread #{thread_id}"
  end

  def subscribe_to_entity(entity_id)
    # Verify user belongs to this entity
    unless current_user.entities.exists?(id: entity_id)
      reject
      return
    end

    @entity_id = entity_id
    stream_from "hub_entity_#{entity_id}"
    stream_from "hub_user_#{current_user.id}"
    
    # Mark user as online
    update_presence('online')
    
    Rails.logger.info "HubChannel: User #{current_user.id} subscribed to entity #{entity_id}"
  end
end
