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
    
    # Redirect to the target URL
    redirect_to params[:url] || root_url
  end
  
  private
  
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
