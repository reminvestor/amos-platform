# frozen_string_literal: true

module Api
  class AuthController < ApplicationController
    skip_before_action :authenticate_user!, only: [:login, :register, :verify_mfa]
    skip_before_action :verify_authenticity_token

    before_action :authenticate_api_user!, only: [:me, :refresh_token, :logout, :regenerate_api_key]

    def register
      # Validate required fields
      unless params[:email].present? && params[:password].present?
        render json: { message: "Email and password are required" }, status: :unprocessable_entity
        return
      end

      # Check if email already exists
      if User.exists?(email: params[:email]&.downcase)
        render json: { message: "Email already registered" }, status: :unprocessable_entity
        return
      end

      # Parse name
      full_name = params[:name].to_s.strip
      name_parts = full_name.split(/\s+/)
      first_name = name_parts.first.presence || "User"
      last_name = name_parts.length >= 2 ? name_parts[1..].join(" ") : ""

      # Create entity for the user
      business_name = params[:business_name].presence || "#{first_name} #{last_name} Business".strip
      entity = create_entity_for_registration(business_name)

      unless entity
        render json: { message: "Failed to create account. Please try again." }, status: :unprocessable_entity
        return
      end

      # Create user
      user = User.new(
        email: params[:email].downcase,
        password: params[:password],
        password_confirmation: params[:password],
        first_name: first_name,
        last_name: last_name,
        entity_id: entity.id,
        api_key: SecureRandom.hex(32)
      )

      if user.save
        # Create EntityUser association
        EntityUser.create!(
          entity_id: entity.id,
          user: user,
          role: "owner"
        )

        Rails.logger.info "✅ Mobile registration: #{user.email} with entity #{entity.id}"

        render json: {
          user: {
            id: user.id,
            email: user.email,
            first_name: user.first_name,
            last_name: user.last_name,
            name: "#{user.first_name} #{user.last_name}".strip,
            entity_id: user.entity_id,
            entity_name: entity.name,
            role: "owner",
            mfa_enabled: user.otp_required_for_login
          },
          api_key: user.api_key,
          token: user.api_key
        }, status: :created
      else
        # Clean up entity if user creation failed
        entity.destroy
        render json: { message: user.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    def logout
      # Clear the cached user
      Rails.cache.delete("api_user:#{@current_user.api_key}")

      # Optionally regenerate API key to invalidate the token
      @current_user.update(api_key: SecureRandom.hex(32))

      render json: { message: "Logged out successfully" }, status: :ok
    end

    def login
      user = User.find_by(email: params[:email]&.downcase)

      if user&.valid_password?(params[:password])
        # Check if MFA is required (skip in development for easier testing)
        if user.mfa_enabled? && !Rails.env.development?
          # Generate a temporary MFA session token (stored in cache)
          mfa_session_token = SecureRandom.hex(32)
          Rails.cache.write("mfa_session:#{mfa_session_token}", user.id, expires_in: 10.minutes)

          render json: {
            mfa_required: true,
            mfa_session_token: mfa_session_token,
            message: "Two-factor authentication required"
          }, status: :ok
          return
        end

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
            role: user.role,
            mfa_enabled: user.otp_required_for_login
          },
          api_key: user.api_key,
          token: user.api_key
        }, status: :ok
      else
        render json: { message: "Invalid email or password" }, status: :unauthorized
      end
    end

    def verify_mfa
      mfa_session_token = params[:mfa_session_token]
      code = params[:code]&.gsub(/\s/, "")

      unless mfa_session_token.present? && code.present?
        render json: { message: "MFA session token and code are required" }, status: :unprocessable_entity
        return
      end

      # Retrieve user ID from cache
      user_id = Rails.cache.read("mfa_session:#{mfa_session_token}")
      unless user_id
        render json: { message: "MFA session expired. Please login again." }, status: :unauthorized
        return
      end

      user = User.find_by(id: user_id)
      unless user
        render json: { message: "User not found" }, status: :unauthorized
        return
      end

      # Check if account is locked
      if user.otp_locked?
        render json: { message: "Too many failed attempts. Please try again later." }, status: :too_many_requests
        return
      end

      # Verify the OTP code (supports TOTP and backup codes)
      # Allow bypass code in development mode for mobile app testing
      dev_bypass = Rails.env.development? && code == "000000"
      if dev_bypass || user.verify_otp(code, method: "totp")
        # Delete the MFA session token
        Rails.cache.delete("mfa_session:#{mfa_session_token}")

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
            role: user.role,
            mfa_enabled: user.otp_required_for_login
          },
          api_key: user.api_key,
          token: user.api_key
        }, status: :ok
      else
        remaining = User::OTP_MAX_FAILED_ATTEMPTS - user.otp_failed_attempts
        render json: {
          message: "Invalid verification code",
          remaining_attempts: remaining > 0 ? remaining : 0
        }, status: :unauthorized
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
          role: @current_user.role,
          mfa_enabled: @current_user.otp_required_for_login
        }
      }, status: :ok
    end

    def refresh_token
      render json: { token: @current_user.api_key }, status: :ok
    end

    def regenerate_api_key
      new_key = SecureRandom.hex(32)

      # Clear old cache
      Rails.cache.delete("api_user:#{@current_user.api_key}")

      if @current_user.update(api_key: new_key)
        render json: {
          api_key: new_key,
          message: "API key regenerated successfully"
        }, status: :ok
      else
        render json: { message: "Failed to regenerate API key" }, status: :unprocessable_entity
      end
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

    def create_entity_for_registration(business_name)
      # Generate unique subdomain
      base_subdomain = business_name.parameterize
      subdomain = base_subdomain
      counter = 1

      while Entity.where(subdomain: subdomain).exists?
        subdomain = "#{base_subdomain}-#{counter}"
        counter += 1
      end

      Entity.create!(
        name: business_name,
        subdomain: subdomain,
        status: "active"
      )
    rescue => e
      Rails.logger.error "❌ Failed to create entity for registration: #{e.message}"
      nil
    end
  end
end
