class CampaignTrackingController < ApplicationController
  # Skip authentication for tracking endpoints
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token
  
  # Track email opens
  def open
    process_tracking_event('open')
    
    # Return a 1x1 transparent GIF
    send_data(Base64.decode64('R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=='), 
      type: 'image/gif', 
      disposition: 'inline')
  end
  
  # Track email clicks
  def click
    process_tracking_event('click')
    
    # Get target URL from params - fallback to a default if not present
    target_url = params[:url].presence || root_url
    
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
      
      # Check if it's a relative URL (starts with / or doesn't have a host)
      return url if url.start_with?('/') || uri.host.nil?
      
      # If absolute URL, check against allowlist of domains
      allowlisted_domains = [
        URI.parse(root_url).host,
        # Add other trusted domains here
      ]
      
      # Allow the URL if its domain is in our allowlist
      return url if allowlisted_domains.include?(uri.host)
      
      # Otherwise, fall back to the root URL
      root_url
    rescue URI::InvalidURIError
      # If URL is invalid, fall back to the root URL
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
    if event_type == 'open'
      delivery.mark_as_opened
    elsif event_type == 'click'
      delivery.mark_as_clicked
    end
  end
end
