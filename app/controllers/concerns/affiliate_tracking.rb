# frozen_string_literal: true

# Affiliate tracking concern for cookie-based referral tracking
# Tracks affiliate clicks and sets secure cookies for attribution
module AffiliateTracking
  extend ActiveSupport::Concern

  included do
    before_action :track_affiliate_referral, if: :affiliate_ref_param?
  end

  private

  def affiliate_ref_param?
    params[:ref].present?
  end

  def track_affiliate_referral
    # Find active affiliate by code
    affiliate = Affiliate.find_by(affiliate_code: params[:ref], status: :active)
    return unless affiliate

    # Rate limiting: Max 100 clicks per IP per hour
    recent_clicks_count = AffiliateClick.where(
      ip_address: request.remote_ip,
      landed_at: 1.hour.ago..Time.current
    ).count

    if recent_clicks_count >= 100
      Rails.logger.warn "Rate limit exceeded for IP: #{request.remote_ip}"
      return
    end

    # Set secure cookie for 60 days
    cookies.signed[:affiliate_ref] = {
      value: params[:ref],
      expires: 60.days.from_now,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }

    # Log the click asynchronously to avoid blocking the request
    begin
      AffiliateClick.create!(
        affiliate: affiliate,
        referral_code: params[:ref],
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        referrer: request.referrer,
        session_id: session.id.to_s,
        landed_at: Time.current,
        metadata: extract_utm_parameters
      )
    rescue => e
      # Don't block the request if click logging fails
      Rails.logger.error "Failed to log affiliate click: #{e.message}"
    end
  end

  # Get the affiliate referral code from cookie
  def affiliate_referral_code
    cookies.signed[:affiliate_ref]
  end

  # Extract UTM parameters from request
  def extract_utm_parameters
    {
      utm_source: params[:utm_source],
      utm_medium: params[:utm_medium],
      utm_campaign: params[:utm_campaign],
      utm_term: params[:utm_term],
      utm_content: params[:utm_content],
      landing_page: request.fullpath
    }.compact
  end
end
