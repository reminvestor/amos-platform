class AffiliateAnalyticsService
  def initialize(date_range = '30days')
    @date_range = date_range
    @start_date = calculate_start_date
    @end_date = Date.current
  end

  def generate_report
    {
      summary: summary_metrics,
      top_affiliates: top_affiliates(10),
      conversion_funnel: conversion_funnel,
      monthly_trends: monthly_trends,
      tier_distribution: tier_distribution
    }
  end

  private

  def calculate_start_date
    case @date_range
    when '7days'
      7.days.ago.to_date
    when '30days'
      30.days.ago.to_date
    when '90days'
      90.days.ago.to_date
    when 'year'
      1.year.ago.to_date
    when 'all'
      Affiliate.minimum(:created_at)&.to_date || Date.current
    else
      30.days.ago.to_date
    end
  end

  def summary_metrics
    {
      total_affiliates: Affiliate.count,
      active_affiliates: Affiliate.active.count,
      pending_affiliates: Affiliate.pending.count,
      total_clicks: AffiliateClick.where(landed_at: @start_date..@end_date).count,
      total_conversions: Referral.converted.where(converted_at: @start_date..@end_date).count,
      total_commissions_earned: Commission.where(earned_at: @start_date..@end_date).sum(:amount),
      total_commissions_pending: Commission.pending.sum(:amount),
      total_commissions_approved: Commission.approved.sum(:amount),
      total_payouts_processed: Payout.completed.where(created_at: @start_date..@end_date).sum(:amount),
      average_commission: Commission.where(earned_at: @start_date..@end_date).average(:amount)&.round(2) || 0
    }
  end

  def top_affiliates(limit)
    Affiliate.active
             .joins(:commissions)
             .where(commissions: { earned_at: @start_date..@end_date })
             .group('affiliates.id')
             .select('affiliates.*, SUM(commissions.amount) as total_earnings')
             .order('total_earnings DESC')
             .limit(limit)
             .includes(:user)
  end

  def conversion_funnel
    clicks = AffiliateClick.where(landed_at: @start_date..@end_date).count
    signups = Referral.where(created_at: @start_date..@end_date).count
    conversions = Referral.converted.where(converted_at: @start_date..@end_date).count

    {
      clicks: clicks,
      signups: signups,
      conversions: conversions,
      click_to_signup_rate: clicks > 0 ? ((signups.to_f / clicks) * 100).round(2) : 0,
      signup_to_conversion_rate: signups > 0 ? ((conversions.to_f / signups) * 100).round(2) : 0,
      overall_conversion_rate: clicks > 0 ? ((conversions.to_f / clicks) * 100).round(2) : 0
    }
  end

  def monthly_trends
    months = []
    current_month = @end_date.beginning_of_month

    6.times do
      months.unshift(current_month)
      current_month = current_month - 1.month
    end

    {
      labels: months.map { |m| m.strftime('%b %Y') },
      affiliates: months.map { |m| Affiliate.where(created_at: m.beginning_of_month..m.end_of_month).count },
      commissions: months.map { |m| Commission.where(earned_at: m.beginning_of_month..m.end_of_month).sum(:amount).to_f },
      payouts: months.map { |m| Payout.completed.where(created_at: m.beginning_of_month..m.end_of_month).sum(:amount).to_f }
    }
  end

  def tier_distribution
    {
      bronze: Affiliate.bronze.count,
      silver: Affiliate.silver.count,
      gold: Affiliate.gold.count
    }
  end
end
