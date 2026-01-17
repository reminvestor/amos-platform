# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification_service

  # GET /notifications
  def index
    @notifications = @notification_service.recent_notifications(limit: 50)
    @unread_count = @notification_service.unread_count
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          notifications: @notifications.map { |n| notification_json(n) },
          unread_count: @unread_count
        }
      end
    end
  end

  # GET /notifications/unread_count
  def unread_count
    count = @notification_service.unread_count
    render json: { count: count }
  end

  # POST /notifications/mark_read
  def mark_read
    ids = params[:ids] || []
    @notification_service.mark_as_read(ids)
    
    render json: { 
      success: true, 
      unread_count: @notification_service.unread_count 
    }
  end

  # POST /notifications/mark_all_read
  def mark_all_read
    @notification_service.mark_all_read
    
    render json: { 
      success: true, 
      unread_count: 0 
    }
  end

  # POST /notifications/dismiss
  def dismiss
    notification = SystemNotification.find_by(id: params[:id], entity: current_entity)
    
    if notification
      notification.dismiss!(by: current_user.email)
      render json: { success: true }
    else
      render json: { success: false, error: 'Notification not found' }, status: :not_found
    end
  end

  # GET /notifications/stats
  def stats
    stats = @notification_service.stats(since: params[:since]&.to_i&.hours&.ago || 24.hours.ago)
    render json: stats
  end

  private

  def set_notification_service
    @notification_service = SystemNotificationService.new(
      entity: current_entity,
      user: current_user
    )
  end

  def notification_json(notification)
    {
      id: notification.id,
      category: notification.category,
      severity: notification.severity,
      title: notification.title,
      message: notification.message,
      read: notification.read?,
      actionable: notification.actionable,
      action_label: notification.action_label,
      action_path: notification.action_path,
      created_at: notification.created_at.iso8601,
      age_in_words: notification.age_in_words
    }
  end
end

