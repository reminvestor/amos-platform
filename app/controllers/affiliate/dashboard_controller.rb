class Affiliate::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_affiliate
  skip_before_action :check_subscription_status
  skip_before_action :check_onboarding_status

  def show
    @affiliate = current_user.affiliate
    @stats = calculate_stats
    @recent_clicks = @affiliate.affiliate_clicks.order(landed_at: :desc).limit(10)
    @recent_referrals = @affiliate.referrals.includes(:referred_user, :referred_entity).order(created_at: :desc).limit(10)
    @chart_data = chart_data
  end

  private

  def ensure_affiliate
    unless current_user.affiliate.present?
      redirect_to affiliate_apply_path, alert: "Please apply to become an affiliate first."
    end
  end

  def calculate_stats
    affiliate = current_user.affiliate

    {
      total_clicks: affiliate.affiliate_clicks.count,
      clicks_this_month: affiliate.affiliate_clicks.where('landed_at >= ?', 1.month.ago).count,
      total_referrals: affiliate.referrals.count,
      converted_referrals: affiliate.referrals.converted.count,
      pending_commissions: affiliate.commissions.where(status: [:pending, :approved]).sum(:amount),
      paid_commissions: affiliate.commissions.paid.sum(:amount),
      total_earnings: affiliate.commissions.sum(:amount),
      status: affiliate.status,
      tier: affiliate.tier,
      commission_rate: (affiliate.commission_rate * 100).round(2)
    }
  end

  def chart_data
    affiliate = current_user.affiliate

    # Last 30 days of clicks
    clicks_by_day = affiliate.affiliate_clicks
      .where('landed_at >= ?', 30.days.ago)
      .group("DATE(landed_at)")
      .order("DATE(landed_at)")
      .count

    # Format the dates
    formatted_clicks = clicks_by_day.transform_keys { |date| date.strftime("%b %d") }

    {
      clicks_labels: formatted_clicks.keys,
      clicks_data: formatted_clicks.values
    }
  end
end
