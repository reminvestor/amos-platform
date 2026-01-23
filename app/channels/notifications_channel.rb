# frozen_string_literal: true

class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user && current_entity
    
    # Subscribe to entity-wide notifications and user-specific notifications
    stream_from "notifications_#{current_entity.id}_all"
    stream_from "notifications_#{current_entity.id}_#{current_user.id}"
    
    Rails.logger.debug "[NotificationsChannel] User #{current_user.id} subscribed to notifications"
  end

  def unsubscribed
    Rails.logger.debug "[NotificationsChannel] User #{current_user&.id} unsubscribed from notifications"
  end
  
  # Allow clients to mark notifications as read
  def mark_read(data)
    notification_ids = data['ids']
    return unless notification_ids.is_a?(Array)
    
    service = SystemNotificationService.new(entity: current_entity, user: current_user)
    service.mark_as_read(notification_ids)
    
    # Broadcast updated count
    broadcast_count_update
  end
  
  # Allow clients to mark all as read
  def mark_all_read
    service = SystemNotificationService.new(entity: current_entity, user: current_user)
    service.mark_all_read
    
    # Broadcast updated count (which will be 0)
    transmit({
      type: 'count_update',
      unread_count: 0
    })
  end
  
  private
  
  def broadcast_count_update
    service = SystemNotificationService.new(entity: current_entity, user: current_user)
    transmit({
      type: 'count_update',
      unread_count: service.unread_count
    })
  end
end

