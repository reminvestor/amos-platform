# frozen_string_literal: true

# Mailer for affiliate-related notifications
# Sends emails to affiliates about applications, commissions, payouts, and tier upgrades
class AffiliateMailer < ApplicationMailer
  # Send confirmation email when affiliate application is received
  #
  # @param affiliate [Affiliate] The affiliate who submitted the application
  def application_received(affiliate)
    @affiliate = affiliate
    @user = affiliate.user

    mail(
      to: @user.email,
      subject: 'Affiliate Application Received - AMOS'
    )
  end

  # Send approval notification when affiliate application is approved
  #
  # @param affiliate [Affiliate] The newly approved affiliate
  def application_approved(affiliate)
    @affiliate = affiliate
    @user = affiliate.user
    @referral_link = "#{root_url}?ref=#{@affiliate.affiliate_code}"
    @dashboard_url = affiliate_dashboard_url
    @resources_url = affiliate_resources_url

    mail(
      to: @user.email,
      subject: 'Welcome to the AMOS Affiliate Program!'
    )
  end

  # Send notification when someone signs up using affiliate's link
  #
  # @param affiliate [Affiliate] The affiliate who referred the user
  # @param referred_user [User] The user who signed up
  def new_referral_signup(affiliate, referred_user)
    @affiliate = affiliate
    @user = affiliate.user
    @referred_user = referred_user
    @dashboard_url = affiliate_dashboard_url

    mail(
      to: @user.email,
      subject: 'New Referral Signup - AMOS'
    )
  end

  # Send notification when affiliate earns a commission
  #
  # @param affiliate [Affiliate] The affiliate who earned the commission
  # @param commission [Commission] The commission that was earned
  def commission_earned(affiliate, commission)
    @affiliate = affiliate
    @user = affiliate.user
    @commission = commission
    @amount = commission.amount
    @commission_type = commission.commission_type.humanize
    @customer_name = commission.entity.name
    @dashboard_url = affiliate_dashboard_url

    mail(
      to: @user.email,
      subject: "You've Earned $#{@amount.round(2)}! - AMOS Affiliate"
    )
  end

  # Send notification when payout is processed
  #
  # @param payout [Payout] The payout that was completed
  def payout_processed(payout)
    @payout = payout
    @affiliate = payout.affiliate
    @user = @affiliate.user
    @amount = payout.amount
    @payment_method = payout.payment_method.humanize
    @payment_reference = payout.payment_reference
    @payouts_url = affiliate_payouts_url

    mail(
      to: @user.email,
      subject: "Payout of $#{@amount.round(2)} Processed - AMOS Affiliate"
    )
  end

  # Send notification when affiliate is upgraded to a new tier
  #
  # @param affiliate [Affiliate] The affiliate being upgraded
  # @param new_tier [String] The new tier (silver, gold, etc.)
  def tier_upgraded(affiliate, new_tier)
    @affiliate = affiliate
    @user = affiliate.user
    @new_tier = new_tier.to_s.capitalize
    @old_tier = affiliate.tier_before_last_save&.capitalize || 'Bronze'
    @new_commission_rate = (affiliate.commission_rate * 100).round(2)
    @dashboard_url = affiliate_dashboard_url

    mail(
      to: @user.email,
      subject: "Congratulations! You've Reached #{@new_tier} Tier - AMOS Affiliate"
    )
  end

  private

  # Helper method to get root URL
  def root_url
    Rails.application.routes.url_helpers.root_url
  end

  # Helper method to get dashboard URL
  def affiliate_dashboard_url
    Rails.application.routes.url_helpers.affiliate_dashboard_url
  end

  # Helper method to get resources URL
  def affiliate_resources_url
    Rails.application.routes.url_helpers.affiliate_resources_url
  end

  # Helper method to get payouts URL
  def affiliate_payouts_url
    Rails.application.routes.url_helpers.affiliate_payouts_url
  end
end
