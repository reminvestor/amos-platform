class SubscriptionController < ApplicationController
  # Skip authentication for subscription management
  skip_before_action :authenticate_user!

  # Skip using the application layout
  layout false

  def unsubscribe
    # Get the token from params
    token = params[:token]

    if token.blank?
      @message = "No unsubscribe token provided. Please use the link in the email you received."
      render :unsubscribe and return
    end

    # Find the email delivery using secure token (not ID!)
    @email_delivery = EmailDelivery.find_by(unsubscribe_token: token)

    if @email_delivery&.contact
      # Mark the contact as unsubscribed
      @contact = @email_delivery.contact

      # Only unsubscribe if not already opted out
      if @contact.opted_out?
        @message = "You are already unsubscribed from our emails."
      else
        @contact.update(opted_out: true, opted_out_at: Time.current)
        @message = "You have been successfully unsubscribed. You will no longer receive emails from us."

        Rails.logger.info("Contact #{@contact.id} unsubscribed via token #{token[0..8]}...")
      end
    else
      # Invalid or expired token
      @message = "Invalid or expired unsubscribe link. Please contact us if you wish to unsubscribe."
      Rails.logger.warn("Invalid unsubscribe token attempt: #{token[0..8]}...")
    end

    render :unsubscribe
  end
end
