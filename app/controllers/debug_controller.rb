class DebugController < ApplicationController
  # Skip all authentication and redirect checks for debugging
  skip_before_action :authenticate_user!, only: [:status]
  skip_before_action :check_onboarding_status, only: [:status]
  
  def status
    if user_signed_in?
      render json: {
        success: true,
        user_id: current_user.id,
        user_email: current_user.email,
        onboarded: current_user.onboarded?,
        entities_count: current_user.entities.count,
        entity_names: current_user.entities.pluck(:name),
        current_entity_id: session[:entity_id],
        current_entity_name: current_entity&.name,
        has_business_profile: current_user.business_profile.present?,
        subdomain: request.subdomain,
        domain: request.domain,
        path: request.path,
        referer: request.referer,
        timestamp: Time.current.iso8601
      }
    else
      render json: {
        success: false,
        message: "User not signed in",
        subdomain: request.subdomain,
        domain: request.domain,
        path: request.path,
        timestamp: Time.current.iso8601
      }
    end
  end
  
  private
  
  def current_entity
    @current_entity ||= current_user&.entity_users&.first&.entity
  end
end 