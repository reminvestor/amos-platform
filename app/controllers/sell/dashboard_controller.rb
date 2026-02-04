# frozen_string_literal: true

module Sell
  class DashboardController < Sell::BaseController
    def index
      @stats = calculate_stats
      @recent_referrals = current_user.referrals.order(created_at: :desc).limit(5) rescue []
      @pending_earnings = calculate_pending_earnings
    end
    
    private
    
    def calculate_stats
      {
        total_referrals: current_user.referrals.count,
        active_referrals: current_user.referrals.where(status: 'active').count,
        total_earnings: current_user.affiliate_earnings_total || 0,
        pending_payout: current_user.affiliate_pending_payout || 0,
        conversion_rate: calculate_conversion_rate,
        this_month_referrals: current_user.referrals.where('created_at > ?', Time.current.beginning_of_month).count
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
      total = current_user.referrals.count
      return 0 if total.zero?
      
      active = current_user.referrals.where(status: 'active').count
      ((active.to_f / total) * 100).round(1)
    rescue
      0
    end
    
    def calculate_pending_earnings
      # Calculate earnings not yet paid out
      0 # Placeholder
    end
  end
end
