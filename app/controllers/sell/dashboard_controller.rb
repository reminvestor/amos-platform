# frozen_string_literal: true

module Sell
  class DashboardController < Sell::BaseController
    def index
      @stats = calculate_stats
      @recent_referrals = affiliate_referrals.order(created_at: :desc).limit(5)
      @pending_earnings = calculate_pending_earnings
    end
    
    private

    def current_affiliate
      @current_affiliate ||= current_user.affiliate
    end

    def affiliate_referrals
      current_affiliate&.referrals || Referral.none
    end
    
    def calculate_stats
      {
        total_referrals: affiliate_referrals.count,
        active_referrals: affiliate_referrals.where(status: :active).count,
        total_earnings: current_affiliate&.total_earned || 0,
        pending_payout: current_affiliate&.pending_commissions_amount || 0,
        conversion_rate: calculate_conversion_rate,
        this_month_referrals: affiliate_referrals.where("created_at > ?", Time.current.beginning_of_month).count
      }
    rescue => e
      Rails.logger.error "Error calculating affiliate stats: #{e.message}"
      {
        total_referrals: 0,
        active_referrals: 0,
        total_earnings: 0,
        pending_payout: 0,
        conversion_rate: 0,
        this_month_referrals: 0
      }
    end
    
    def calculate_conversion_rate
      total = affiliate_referrals.count
      return 0 if total.zero?
      
      active = affiliate_referrals.where(status: :active).count
      ((active.to_f / total) * 100).round(1)
    rescue
      0
    end
    
    def calculate_pending_earnings
      current_affiliate&.pending_commissions_amount || 0
    end
  end
end
