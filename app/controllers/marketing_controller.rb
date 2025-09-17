class MarketingController < ApplicationController
  skip_before_action :authenticate_user!
  layout 'marketing'
  
  def index
  end
  
  def features
  end
  
  def pricing
  end
  
  def about
  end
  
  def contact
  end

  def contact_submit
    name = params[:name].to_s.strip
    email = params[:email].to_s.strip
    subject = params[:subject].to_s.strip
    message = params[:message].to_s.strip

    if name.blank? || email.blank? || subject.blank? || message.blank?
      flash[:alert] = 'Please fill in your name, email, subject, and message.'
      redirect_to marketing_contact_path(name: name, email: email, subject: subject) and return
    end

    begin
      ContactMailer.with(name: name, email: email, subject: subject, message: message).contact_request.deliver_later
      flash[:notice] = 'Thanks! Your message has been sent.'
    rescue => e
      Rails.logger.error("Contact form mail failed: #{e.message}")
      flash[:alert] = 'Sorry, something went wrong sending your message.'
    end

    redirect_to marketing_contact_path
  end

  def help
  end
end
