# frozen_string_literal: true

class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user && current_user.entity

    entity = current_user.entity

    stream_from "notifications_#{entity.id}_all"
    stream_from "notifications_#{entity.id}_#{current_user.id}"

    Rails.logger.info "📡 User #{current_user.id} subscribed to notifications"
  end

  def unsubscribed
    Rails.logger.debug "[NotificationsChannel] User #{current_user&.id} unsubscribed from notifications"
  end

  def mark_read(data)
    notification_ids = data['ids']
    return unless notification_ids.is_a?(Array)

    service = SystemNotificationService.new(entity: current_user.entity, user: current_user)
    service.mark_as_read(notification_ids)

    broadcast_count_update
  end

  def mark_all_read
    service = SystemNotificationService.new(entity: current_user.entity, user: current_user)
    service.mark_all_read

    transmit({
      type: 'count_update',
      unread_count: 0
    })
  end

  private

  def broadcast_count_update
    service = SystemNotificationService.new(entity: current_user.entity, user: current_user)
    transmit({
      type: 'count_update',
      unread_count: service.unread_count
    })
  end
end

