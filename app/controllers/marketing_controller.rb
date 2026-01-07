class MarketingController < ApplicationController
  include AffiliateTracking

  skip_before_action :authenticate_user!
  skip_before_action :check_token_balance
  skip_before_action :check_onboarding_status
  layout "marketing"

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
    # Honeypot field - if filled, it's a bot
    if params[:website].present?
      Rails.logger.warn("[SECURITY] Bot detected via honeypot from IP: #{request.remote_ip}")
      redirect_to marketing_contact_path and return
    end

    # Rate limiting: max 3 submissions per minute per IP
    rate_limit_key = "contact_form:#{request.remote_ip}"
    submission_count = Rails.cache.read(rate_limit_key).to_i

    if submission_count >= 3
      Rails.logger.warn("[SECURITY] Rate limit exceeded for contact form from IP: #{request.remote_ip}")
      flash[:alert] = "Too many submissions. Please try again later."
      redirect_to marketing_contact_path and return
    end

    Rails.cache.write(rate_limit_key, submission_count + 1, expires_in: 1.minute)

    name = params[:name].to_s.strip
    email = params[:email].to_s.strip
    subject = params[:subject].to_s.strip
    message = params[:message].to_s.strip

    # Detect SQL injection and other attack patterns
    attack_patterns = [
      /\bSELECT\b.*\bFROM\b/i,
      /\bUNION\b.*\bSELECT\b/i,
      /\bINSERT\b.*\bINTO\b/i,
      /\bDELETE\b.*\bFROM\b/i,
      /\bDROP\b.*\bTABLE\b/i,
      /\bEXEC\b|\bEXECUTE\b/i,
      /CTXSYS\.DRITHSX/i,
      /\bDUAL\b/i,
      /\bsleep\s*\(/i,
      /\bwaitfor\b.*\bdelay\b/i,
      /\bCASE\b.*\bWHEN\b.*\bTHEN\b/i,
      /<script\b/i,
      /javascript:/i
    ]

    all_input = "#{name} #{email} #{subject} #{message}"
    if attack_patterns.any? { |pattern| all_input.match?(pattern) }
      Rails.logger.warn("[SECURITY] Attack detected in contact form from IP: #{request.remote_ip}")
      Rails.logger.warn("[SECURITY] Payload: #{all_input.truncate(500)}")
      # Silently reject - don't give attackers feedback
      flash[:notice] = "Thanks! Your message has been sent."
      redirect_to marketing_contact_path and return
    end

    if name.blank? || email.blank? || subject.blank? || message.blank?
      flash[:alert] = "Please fill in your name, email, subject, and message."
      redirect_to marketing_contact_path(name: name, email: email, subject: subject) and return
    end

    # Basic email validation
    unless email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      flash[:alert] = "Please enter a valid email address."
      redirect_to marketing_contact_path(name: name, subject: subject) and return
    end

    begin
      ContactMailer.with(name: name, email: email, subject: subject, message: message).contact_request.deliver_later
      flash[:notice] = "Thanks! Your message has been sent."
    rescue => e
      Rails.logger.error("Contact form mail failed: #{e.message}")
      flash[:alert] = "Sorry, something went wrong sending your message."
    end

    redirect_to marketing_contact_path
  end

  def help
  end
end
