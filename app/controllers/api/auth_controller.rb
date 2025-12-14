# frozen_string_literal: true

module Api
  class AuthController < ApplicationController
    skip_before_action :authenticate_user!, only: [:login, :register]
    skip_before_action :verify_authenticity_token

    before_action :authenticate_api_user!, only: [:me, :refresh_token, :logout]

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
            role: "owner"
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
