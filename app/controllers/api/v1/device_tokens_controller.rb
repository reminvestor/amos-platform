# frozen_string_literal: true

module Api
  module V1
    class DeviceTokensController < BaseController
      skip_before_action :require_entity!

      # POST /api/v1/device_tokens
      # Register a device token for push notifications
      def create
        token = device_token_params[:token]
        platform = device_token_params[:platform]

        # Find existing token or create new one
        device_token = DeviceToken.find_by(token: token)

        if device_token
          # Token exists - update it (might be different user or reactivating)
          device_token.update!(
            user: current_user,
            platform: platform,
            active: true
          )
        else
          # New token
          device_token = current_user.device_tokens.create!(
            token: token,
            platform: platform
          )
        end

        # Register with SNS in background (creates endpoint_arn)
        RegisterDeviceTokenJob.perform_later(device_token.id)

        render json: {
          id: device_token.id,
          platform: device_token.platform,
          active: device_token.active,
          registered: device_token.endpoint_arn.present?
        }, status: :created
      end

      # DELETE /api/v1/device_tokens
      # Unregister a device token (e.g., on logout)
      def destroy
        token = params[:token]

        device_token = current_user.device_tokens.find_by(token: token)

        if device_token
          # Deactivate and remove from SNS in background
          device_token.deactivate!
          UnregisterDeviceTokenJob.perform_later(device_token.id)

          render json: { message: "Device token unregistered" }
        else
          render json: { message: "Device token not found" }, status: :not_found
        end
      end

      private

      def device_token_params
        params.require(:device_token).permit(:token, :platform)
      end
    end
  end
end
