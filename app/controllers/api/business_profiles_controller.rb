# frozen_string_literal: true

module Api
  class BusinessProfilesController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :verify_authenticity_token

    before_action :authenticate_api_user!
    before_action :set_business_profile

    # GET /api/business_profile
    def show
      render json: profile_json(@business_profile)
    end

    # PATCH /api/business_profile
    def update
      # Handle style guidelines separately if present
      process_style_guidelines if style_params_present?

      if @business_profile.update(business_profile_params)
        render json: {
          success: true,
          message: "Business profile updated successfully",
          profile: profile_json(@business_profile)
        }
      else
        render json: {
          success: false,
          errors: @business_profile.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    private

    def authenticate_api_user!
      token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

      unless token.present?
        render json: { message: "Authorization token required" }, status: :unauthorized
        return
      end

      @current_user = Rails.cache.fetch("api_user:#{token}", expires_in: 5.minutes) do
        User.includes(:entity).find_by(api_key: token)
      end

      unless @current_user
        render json: { message: "Invalid token" }, status: :unauthorized
        return
      end
    end

    def set_business_profile
      @business_profile = @current_user.ensure_business_profile
    end

    def business_profile_params
      params.require(:business_profile).permit(
        :name, :industry, :description, :founded_year,
        :website, :values, :target_audience, :tone_of_voice
      )
    end

    def style_params_present?
      bp = params[:business_profile]
      bp && (bp[:style_colors].present? || bp[:style_typography].present? ||
             bp[:style_aesthetic].present? || bp[:style_logo_url].present?)
    end

    def process_style_guidelines
      bp = params[:business_profile]

      style_guidelines = @business_profile.style_guidelines || {}

      # Process colors (split by newlines)
      if bp[:style_colors].present?
        colors_array = bp[:style_colors].split("\n").map(&:strip).select { |c| c.start_with?('#') }
        style_guidelines['colors'] = colors_array
      end

      style_guidelines['typography'] = bp[:style_typography] if bp[:style_typography].present?
      style_guidelines['aesthetic'] = bp[:style_aesthetic] if bp[:style_aesthetic].present?
      style_guidelines['logo_url'] = bp[:style_logo_url] if bp[:style_logo_url].present?

      @business_profile.style_guidelines = style_guidelines
    end

    def profile_json(profile)
      {
        id: profile.id,
        name: profile.name,
        industry: profile.industry,
        description: profile.description,
        founded_year: profile.founded_year,
        website: profile.website,
        values: profile.values,
        target_audience: profile.target_audience,
        tone_of_voice: profile.tone_of_voice,
        style_guidelines: profile.style_guidelines,
        entity_name: profile.entity&.name
      }
    end
  end
end
