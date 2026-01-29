# frozen_string_literal: true

module Api
  module V1
    # DeviceTokensController handles mobile device registration for push notifications.
    #
    # Endpoints:
    # - POST /api/v1/device_tokens - Register a device
    # - DELETE /api/v1/device_tokens - Unregister current device
    # - DELETE /api/v1/device_tokens/logout_all - Unregister all devices for user
    # - GET /api/v1/device_tokens - List user's registered devices
    # - PATCH /api/v1/device_tokens/:id/preferences - Update notification preferences
    #
    class DeviceTokensController < Api::V1::BaseController
      # Authentication inherited from BaseController (authenticate_api_user!)
      before_action :set_device_token, only: [:destroy, :update_preferences]

      # POST /api/v1/device_tokens
      # Register a new device or update existing registration
      def create
        device_token = DeviceToken.register(
          user: current_user,
          entity: current_entity,
          token: device_params[:token],
          platform: device_params[:platform],
          device_info: device_info_params
        )

        if device_token.persisted?
          render json: {
            success: true,
            device_token: device_token_json(device_token),
            message: "Device registered successfully"
          }, status: :created
        else
          render json: {
            success: false,
            errors: device_token.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/device_tokens
      # Unregister the current device (by token)
      def destroy_by_token
        device_token = DeviceToken.find_by(token: params[:token], user_id: current_user.id)

        if device_token
          device_token.deactivate!('user_logout')
          render json: { success: true, message: "Device unregistered" }
        else
          render json: { success: false, error: "Device not found" }, status: :not_found
        end
      end

      # DELETE /api/v1/device_tokens/:id
      # Unregister a specific device by ID
      def destroy
        @device_token.deactivate!('user_logout')
        render json: { success: true, message: "Device unregistered" }
      end

      # DELETE /api/v1/device_tokens/logout_all
      # Unregister all devices for the current user
      def logout_all
        count = DeviceToken.active.for_user(current_user.id).count
        DeviceToken.deactivate_all_for_user(current_user)

        render json: {
          success: true,
          message: "Logged out from #{count} device(s)"
        }
      end

      # GET /api/v1/device_tokens
      # List all registered devices for the current user
      def index
        devices = DeviceToken.where(user_id: current_user.id)
                             .order(last_used_at: :desc)

        render json: {
          success: true,
          devices: devices.map { |d| device_token_json(d) }
        }
      end

      # PATCH /api/v1/device_tokens/:id/preferences
      # Update notification preferences for a specific device
      def update_preferences
        preferences = params.permit(preferences: {}).to_h[:preferences] || {}

        @device_token.notification_preferences.merge!(preferences)
        @device_token.save!

        render json: {
          success: true,
          device_token: device_token_json(@device_token)
        }
      end

      private

      def set_device_token
        @device_token = DeviceToken.find_by(id: params[:id], user_id: current_user.id)
        unless @device_token
          render json: { success: false, error: "Device not found" }, status: :not_found
        end
      end

      def device_params
        params.require(:device_token).permit(:token, :platform)
      end

      def device_info_params
        params.fetch(:device_token, {}).permit(
          :device_id,
          :device_name,
          :device_model,
          :os_version,
          :app_version
        ).to_h.symbolize_keys
      end

      def device_token_json(device)
        {
          id: device.id,
          platform: device.platform,
          device_name: device.device_name,
          device_model: device.device_model,
          os_version: device.os_version,
          app_version: device.app_version,
          active: device.active,
          last_used_at: device.last_used_at&.iso8601,
          notification_preferences: device.notification_preferences,
          created_at: device.created_at.iso8601
        }
      end
end
