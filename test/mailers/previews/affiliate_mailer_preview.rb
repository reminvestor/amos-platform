# Preview all emails at http://localhost:3000/rails/mailers/affiliate_mailer
class AffiliateMailerPreview < ActionMailer::Preview
  # Preview: /rails/mailers/affiliate_mailer/application_received
  def application_received
    affiliate = Affiliate.first || create_sample_affiliate
    AffiliateMailer.application_received(affiliate)
  end

  # Preview: /rails/mailers/affiliate_mailer/application_approved
  def application_approved
    affiliate = Affiliate.active.first || create_sample_affiliate(status: :active)
    AffiliateMailer.application_approved(affiliate)
  end

  # Preview: /rails/mailers/affiliate_mailer/new_referral_signup
  def new_referral_signup
    affiliate = Affiliate.active.first || create_sample_affiliate(status: :active)
    referred_user = User.second || create_sample_user(email: 'referred@example.com')
    AffiliateMailer.new_referral_signup(affiliate, referred_user)
  end

  # Preview: /rails/mailers/affiliate_mailer/commission_earned
  def commission_earned
    commission = Commission.approved.first || create_sample_commission
    AffiliateMailer.commission_earned(commission.affiliate, commission)
  end

  # Preview: /rails/mailers/affiliate_mailer/payout_processed
  def payout_processed
    payout = Payout.completed.first || create_sample_payout
    AffiliateMailer.payout_processed(payout)
  end

  # Preview: /rails/mailers/affiliate_mailer/tier_upgraded
  def tier_upgraded
    affiliate = Affiliate.silver.first || create_sample_affiliate(status: :active, tier: :silver)
    AffiliateMailer.tier_upgraded(affiliate, 'gold')
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
      application_notes: 'I have a blog with 10,000 monthly visitors and want to promote AMOS to my audience.'
    )
  end

  def create_sample_user(email: 'affiliate@example.com')
    User.new(
      email: email,
      first_name: 'John',
      last_name: 'Doe',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  def create_sample_commission
    affiliate = Affiliate.active.first || create_sample_affiliate(status: :active)
    entity = Entity.first || Entity.new(name: 'Sample Company', slug: 'sample-company')
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
      amount: 245.50,
      currency: 'USD',
      status: :approved,
      earned_at: Time.current,
      approved_at: Time.current
    )
  end

  def create_sample_payout
    affiliate = Affiliate.active.first || create_sample_affiliate(status: :active)

    Payout.new(
      affiliate: affiliate,
      amount: 485.75,
      currency: 'USD',
      payment_method: 'paypal',
      payment_reference: 'PP-12345678',
      status: :completed,
      payout_date: Date.today
    )
  end
end
