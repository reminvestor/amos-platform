class SubscriptionController < ApplicationController
  # Skip authentication for subscription management
  skip_before_action :authenticate_user!
  
  def unsubscribe
    # Get the token from params
    token = params[:token]
    
    if token.present?
      # Find the email delivery associated with this token
      @email_delivery = EmailDelivery.find_by(id: token)
      
      if @email_delivery&.contact
        # Mark the contact as unsubscribed
        @contact = @email_delivery.contact
        @contact.update(opted_out: true, opted_out_at: Time.current)
        
        # Message to display
        @message = "You have been successfully unsubscribed. You will no longer receive emails from us."
      else
        # Invalid token
        @message = "Invalid unsubscribe link. Please contact us if you wish to unsubscribe."
      end
    else
      # No token provided
      @message = "No unsubscribe token provided. Please use the link in the email you received."
    end
    
    render :unsubscribe
  end
end 