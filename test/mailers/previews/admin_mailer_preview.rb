# Preview all admin emails at http://localhost:3000/rails/mailers/admin_mailer
class AdminMailerPreview < ActionMailer::Preview
  # Preview: /rails/mailers/admin_mailer/new_affiliate_application
  def new_affiliate_application
    affiliate = Affiliate.pending.first || create_sample_affiliate
    AdminMailer.new_affiliate_application(affiliate)
  end

  # Preview: /rails/mailers/admin_mailer/high_value_commission_review
  def high_value_commission_review
    commission = create_sample_high_value_commission
    AdminMailer.high_value_commission_review(commission)
  end

  # Preview: /rails/mailers/admin_mailer/suspicious_activity_detected
  def suspicious_activity_detected
    affiliate = Affiliate.active.first || create_sample_affiliate(status: :active)
    flags = [
      'Multiple signups from same IP (5 signups from 192.168.1.1)',
      'Unusually high conversion rate (75.0%)',
      'Abnormally high click volume (150 clicks in one hour)'
    ]
    AdminMailer.suspicious_activity_detected(affiliate, flags)
  end

  # Preview: /rails/mailers/admin_mailer/error_notification
  def error_notification
    AdminMailer.error_notification(
      'ActiveRecord::RecordNotFound: Couldn\'t find User with \'id\'=12345',
      'SomeBackgroundJob',
      'abc123def456',
      { user_id: 12345, action: 'process_payment' }
    )
  end

  private

  def create_sample_affiliate(status: :pending, tier: :bronze)
    user = User.first || create_sample_user
    Affiliate.new(
      user: user,
      affiliate_code: 'SAMPLE123',
      status: status,
      tier: tier,
      commission_rate: 0.20,
      payment_email: 'payments@example.com',
      application_notes: 'I have a popular marketing blog with 50,000 monthly visitors and an email list of 10,000 subscribers. I regularly write about SaaS tools and marketing automation. I believe AMOS would be a great fit for my audience.'
    )
  end

  def create_sample_user(email: 'affiliate@example.com')
    User.new(
      email: email,
      first_name: 'Jane',
      last_name: 'Smith',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  def create_sample_high_value_commission
    affiliate = Affiliate.active.first || create_sample_affiliate(status: :active)
    entity = Entity.first || Entity.new(name: 'Big Enterprise Corp', slug: 'big-enterprise')
    referral = Referral.new(
      affiliate: affiliate,
      referred_entity: entity,
      referral_code_used: affiliate.affiliate_code,
      status: :converted
    )

    Commission.new(
      affiliate: affiliate,
      referral: referral,
      entity: entity,
      commission_type: 'first_payment',
      amount: 1250.00,
      currency: 'USD',
      status: :pending,
      earned_at: Time.current
    )
  end
end
