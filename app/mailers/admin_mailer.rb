class AdminMailer < ApplicationMailer
  def error_notification(error_message, job_class, job_id, arguments)
    @error_message = error_message
    @job_class = job_class
    @job_id = job_id
    @arguments = arguments
    @timestamp = Time.current

    mail(
      to: ENV["ADMIN_EMAIL"] || ENV["MAILGUN_FROM"],
      subject: "Error in #{job_class}: #{error_message.to_s.truncate(50)}"
    )
  end

  # Send notification to admins when new affiliate application is submitted
  #
  # @param affiliate [Affiliate] The new affiliate application
  def new_affiliate_application(affiliate)
    @affiliate = affiliate
    @user = affiliate.user
    @application_notes = affiliate.application_notes
    @payment_email = affiliate.payment_email
    @review_url = admin_affiliate_url(affiliate)

    admin_emails = get_admin_emails

    mail(
      to: admin_emails,
      subject: "New Affiliate Application from #{@user.full_name}"
    )
  end

  # Send notification to admins when high-value commission needs review
  #
  # @param commission [Commission] The commission requiring review
  def high_value_commission_review(commission)
    @commission = commission
    @affiliate = commission.affiliate
    @user = @affiliate.user
    @amount = commission.amount
    @entity = commission.entity
    @commission_type = commission.commission_type.humanize
    @review_url = admin_commission_url(commission)

    admin_emails = get_admin_emails

    mail(
      to: admin_emails,
      subject: "High-Value Commission Review Required ($#{@amount.round(2)})"
    )
  end

  # Send notification to admins when suspicious activity is detected
  #
  # @param affiliate [Affiliate] The affiliate with suspicious activity
  # @param flags [Array<String>] Array of fraud flags/descriptions
  def suspicious_activity_detected(affiliate, flags)
    @affiliate = affiliate
    @user = affiliate.user
    @flags = flags
    @recent_referrals_count = affiliate.referrals.where('created_at > ?', 7.days.ago).count
    @recent_clicks_count = affiliate.affiliate_clicks.where('landed_at > ?', 7.days.ago).count
    @conversion_rate = affiliate.conversion_rate
    @review_url = admin_affiliate_url(affiliate)

    admin_emails = get_admin_emails

    mail(
      to: admin_emails,
      subject: "Suspicious Affiliate Activity Detected - #{@user.full_name}"
    )
  end

  private

  # Get list of admin email addresses
  def get_admin_emails
    # Try to get from AdminUser model if it exists
    if defined?(AdminUser)
      emails = AdminUser.where(role: [:admin, :super_admin]).pluck(:email).compact
      return emails if emails.any?
    end

    # Fallback to environment variable
    ENV['ADMIN_EMAIL'] || ENV['MAILGUN_FROM']
  end

  # Helper method for admin URLs
  def admin_affiliate_url(affiliate)
    Rails.application.routes.url_helpers.admin_affiliate_url(affiliate)
  end

  def admin_commission_url(commission)
    Rails.application.routes.url_helpers.admin_commissions_url(anchor: "commission-#{commission.id}")
  end
end
