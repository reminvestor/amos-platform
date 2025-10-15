# frozen_string_literal: true

# Service to calculate affiliate statistics for dashboard
# Provides metrics on clicks, conversions, commissions, and earnings
class AffiliateStatsService
  attr_reader :affiliate

  def initialize(affiliate)
    @affiliate = affiliate
  end

  # Calculate all stats for affiliate dashboard
  #
  # @return [Hash] Hash of statistics
  def calculate
    {
      # Click metrics
      clicks_this_month: clicks_this_month,
      clicks_all_time: clicks_all_time,

      # Conversion metrics
      total_conversions: total_conversions,
      pending_referrals: pending_referrals,
      conversion_rate: conversion_rate,

      # Commission metrics
      pending_commissions: pending_commissions_total,
      pending_commissions_count: pending_commissions_count,
      approved_commissions: approved_commissions_total,
      approved_commissions_count: approved_commissions_count,
      paid_commissions: paid_commissions_total,
      paid_commissions_count: paid_commissions_count,

      # Totals
      total_earned: total_earned,
      total_paid: total_paid_out,

      # Performance
      average_commission: average_commission_amount,
      current_tier: affiliate.tier,

      # Balance
      balance: approved_commissions_total
    }
  end

  # Calculate detailed stats (for admin view)
  #
  # @return [Hash] Hash of detailed statistics
  def detailed_stats
    calculate.merge(
      # Time-based metrics
      clicks_last_7_days: clicks_last_n_days(7),
      clicks_last_30_days: clicks_last_n_days(30),
      conversions_this_month: conversions_this_month,
      commissions_this_month: commissions_this_month_total,

      # Additional metrics
      average_time_to_conversion: average_time_to_conversion,
      best_performing_month: best_performing_month,
      referral_retention_rate: referral_retention_rate,

      # Recent activity
      recent_referrals: recent_referrals,
      recent_commissions: recent_commissions,
      recent_payouts: recent_payouts
    )
  end

  # Generate chart data for clicks over time
  #
  # @param period [Integer] Number of days to include
  # @return [Hash] Chart data with labels and values
  def chart_data(period = 30)
    end_date = Date.current
    start_date = end_date - period.days

    dates = (start_date..end_date).to_a
    clicks_by_date = @affiliate.affiliate_clicks
                               .where(landed_at: start_date.beginning_of_day..end_date.end_of_day)
                               .group_by { |c| c.landed_at.to_date }

    {
      labels: dates.map { |d| d.strftime('%m/%d') },
      clicks: dates.map { |d| clicks_by_date[d]&.count || 0 }
    }
  end

  private

  # Click tracking metrics
  def clicks_this_month
    affiliate.affiliate_clicks
            .where('landed_at >= ?', Time.current.beginning_of_month)
            .count
  end

  def clicks_all_time
    affiliate.affiliate_clicks.count
  end

  def clicks_last_n_days(days)
    affiliate.affiliate_clicks
            .where('landed_at >= ?', days.days.ago)
            .count
  end

  # Referral/conversion metrics
  def total_conversions
    affiliate.referrals.where(status: :converted).count
  end

  def pending_referrals
    affiliate.referrals.where(status: :pending).count
  end

  def conversions_this_month
    affiliate.referrals
            .where(status: :converted)
            .where('converted_at >= ?', Time.current.beginning_of_month)
            .count
  end

  def conversion_rate
    total_clicks = clicks_all_time
    return 0.0 if total_clicks.zero?

    (total_conversions.to_f / total_clicks * 100).round(2)
  end

  # Commission metrics
  def pending_commissions_total
    affiliate.commissions.where(status: :pending).sum(:amount).to_f
  end

  def pending_commissions_count
    affiliate.commissions.where(status: :pending).count
  end

  def approved_commissions_total
    affiliate.commissions.where(status: :approved).sum(:amount).to_f
  end

  def approved_commissions_count
    affiliate.commissions.where(status: :approved).count
  end

  def paid_commissions_total
    affiliate.commissions.where(status: :paid).sum(:amount).to_f
  end

  def paid_commissions_count
    affiliate.commissions.where(status: :paid).count
  end

  def commissions_this_month_total
    affiliate.commissions
            .where('earned_at >= ?', Time.current.beginning_of_month)
            .sum(:amount).to_f
  end

  # Total earnings
  def total_earned
    affiliate.commissions.sum(:amount).to_f
  end

  def total_paid_out
    affiliate.payouts.where(status: :completed).sum(:amount).to_f
  end

  def average_commission_amount
    count = affiliate.commissions.count
    return 0.0 if count.zero?

    (total_earned / count).round(2)
  end

  # Advanced metrics
  def average_time_to_conversion
    converted_referrals = affiliate.referrals
                                  .where(status: :converted)
                                  .where.not(converted_at: nil)

    return 0 if converted_referrals.empty?

    total_days = converted_referrals.sum do |referral|
      (referral.converted_at - referral.created_at) / 1.day
    end

    (total_days / converted_referrals.count).round(1)
  end

  def best_performing_month
    # Find month with highest commission earnings
    commissions_by_month = affiliate.commissions
                                   .group("DATE_TRUNC('month', earned_at)")
                                   .sum(:amount)

    return nil if commissions_by_month.empty?

    best_month = commissions_by_month.max_by { |_month, amount| amount }
    {
      month: best_month[0]&.strftime('%B %Y'),
      amount: best_month[1].to_f
    }
  end

  def referral_retention_rate
    # Calculate % of referrals still active after 3 months
    three_months_ago = 3.months.ago
    old_referrals = affiliate.referrals
                            .where('created_at <= ?', three_months_ago)

    return 0.0 if old_referrals.empty?

    # Count referrals with active subscriptions
    active_count = old_referrals.joins(:referred_entity)
                                 .where(entities: { subscription_status: 'active' })
                                 .count

    (active_count.to_f / old_referrals.count * 100).round(2)
  rescue => e
    Rails.logger.error "Error calculating retention rate: #{e.message}"
    0.0
  end

  # Recent activity
  def recent_referrals
    affiliate.referrals.order(created_at: :desc).limit(10)
  end

  def recent_commissions
    affiliate.commissions.order(earned_at: :desc).limit(10)
  end

  def recent_payouts
    affiliate.payouts.order(created_at: :desc).limit(5)
  end
end
