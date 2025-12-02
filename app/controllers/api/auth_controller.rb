# frozen_string_literal: true

module Api
  class AuthController < ApplicationController
    skip_before_action :authenticate_user!, only: [:login]
    skip_before_action :verify_authenticity_token

    before_action :authenticate_api_user!, only: [:me, :refresh_token]

    def login
      user = User.find_by(email: params[:email]&.downcase)

      if user&.valid_password?(params[:password])
        # Generate API key if not present
        if user.api_key.blank?
          user.update(api_key: SecureRandom.hex(32))
        end

        render json: {
          user: {
            id: user.id,
            email: user.email,
            first_name: user.first_name,
            last_name: user.last_name,
            name: "#{user.first_name} #{user.last_name}".strip,
            entity_id: user.entity_id,
            entity_name: user.entity&.name || 'My Business',
            role: user.role
          },
          api_key: user.api_key,
          token: user.api_key
        }, status: :ok
      else
        render json: { message: "Invalid email or password" }, status: :unauthorized
      end
    end

    def me
      render json: {
        user: {
          id: @current_user.id,
          email: @current_user.email,
          first_name: @current_user.first_name,
          last_name: @current_user.last_name,
          name: "#{@current_user.first_name} #{@current_user.last_name}".strip,
          entity_id: @current_user.entity_id,
          entity_name: @current_user.entity&.name || 'My Business',
          role: @current_user.role
        }
      }, status: :ok
    end

    def refresh_token
      render json: { token: @current_user.api_key }, status: :ok
    end

    private

    def authenticate_api_user!
      token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

      unless token.present?
        render json: { message: "Authorization token required" }, status: :unauthorized
        return
      end

      # Cache user lookup by API key for 5 minutes to reduce DB load
      @current_user = Rails.cache.fetch("api_user:#{token}", expires_in: 5.minutes) do
        User.includes(:entity).find_by(api_key: token)
      end

      unless @current_user
        render json: { message: "Invalid token" }, status: :unauthorized
        return
      end
    end
  end
end
