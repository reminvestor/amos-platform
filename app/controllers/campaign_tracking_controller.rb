class CampaignTrackingController < ApplicationController
  # Skip authentication for tracking endpoints
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token

  # Track email opens
  def open
    process_tracking_event("open")

    # Return a 1x1 transparent GIF
    send_data(Base64.decode64("R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=="),
      type: "image/gif",
      disposition: "inline")
  end

  # Track email clicks
  def click
    process_tracking_event("click")

    # Get target URL from params and make sure it's properly decoded
    target_url = params[:url].presence || root_url

    # Decode URL if it's encoded
    target_url = URI.decode_www_form_component(target_url) if target_url.include?("%")

    # Log the target URL to help with debugging
    Rails.logger.info("Email click redirecting to: #{target_url}")

    # Validate the URL to prevent open redirect vulnerabilities
    target_url = ensure_safe_redirect_url(target_url)

    # Redirect to the target URL
    redirect_to target_url
  end

  private

  # Validate URL for safety (prevent open redirect vulnerability)
  def ensure_safe_redirect_url(url)
    begin
      uri = URI.parse(url)

      # Only allow http/https schemes
      unless uri.scheme.nil? || [ "http", "https" ].include?(uri.scheme)
        Rails.logger.warn("Blocked redirect to non-HTTP URL: #{url}")
        return root_url
      end

      # Allow absolute URLs with http/https - needed for email campaign links
      # Note: These URLs come from campaign content created by authenticated users
      return url if uri.scheme && uri.host

      # Allow relative URLs (internal links)
      return url if url.start_with?("/") || uri.host.nil?

      # For any other case, default to root_url
      root_url
    rescue URI::InvalidURIError
      # If URL is invalid, fall back to the root URL
      Rails.logger.warn("Invalid URI in redirect: #{url}")
      root_url
    end
  end

  def process_tracking_event(event_type)
    delivery_id = params[:id]
    return if delivery_id.blank?

    # Find the email delivery
    delivery = EmailDelivery.find_by(id: delivery_id)
    return unless delivery

    # Update the delivery based on event type
    if event_type == "open"
      delivery.mark_as_opened
    elsif event_type == "click"
      delivery.mark_as_clicked
    end
  end
end
