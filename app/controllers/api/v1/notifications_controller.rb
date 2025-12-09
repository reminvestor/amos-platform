# frozen_string_literal: true

module Api
  module V1
    class NotificationsController < BaseController
      before_action :set_notification, only: [:show, :mark_read, :dismiss]

      def index
        @notifications = UserNotification.for_user(current_user)
                                         .active
                                         .recent
                                         .page(params[:page] || 1)
                                         .per(params[:per_page] || 20)

        if params[:unread_only] == 'true'
          @notifications = @notifications.unread
        end

        render json: {
          data: @notifications.map { |n| notification_json(n) },
          pagination: {
            current_page: @notifications.current_page,
            total_pages: @notifications.total_pages,
            total_count: @notifications.total_count,
            per_page: @notifications.limit_value
          },
          unread_count: UserNotification.unread_count_for(current_user)
        }
      end

      def show
        render json: notification_json(@notification)
      end

      def unread_count
        render json: {
          unread_count: UserNotification.unread_count_for(current_user),
          urgent_count: UserNotification.urgent_count_for(current_user)
        }
      end

      def mark_read
        @notification.mark_as_read!
        render json: notification_json(@notification)
      end

      def mark_all_read
        UserNotification.for_user(current_user).active.unread.update_all(
          read: true,
          read_at: Time.current
        )
        render json: { message: "All notifications marked as read" }
      end

      def dismiss
        @notification.dismiss!
        head :no_content
      end

      private

      def set_notification
        @notification = UserNotification.for_user(current_user).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { message: "Notification not found" }, status: :not_found
      end

      def notification_json(notification)
        {
          id: notification.id,
          notification_type: notification.notification_type,
          title: notification.title,
          body: notification.body,
          icon: notification.display_icon,
          priority: notification.priority,
          read: notification.read,
          read_at: notification.read_at,
          action_url: notification.action_url,
          action_type: notification.action_type,
          time_ago: notification.time_ago,
          color_class: notification.color_class,
          created_at: notification.created_at,
          updated_at: notification.updated_at
        }
      end
    end
  end
end
