# frozen_string_literal: true

# TransparencyController
#
# Public-facing dashboard showing real-time platform financials.
# Part of the AMOS value proposition: complete transparency.
#
# This is intentionally PUBLIC - no authentication required.
# Users can see exactly where their money goes.
#
class TransparencyController < ApplicationController
  # No authentication required - this is public
  skip_before_action :authenticate_user!, if: -> { respond_to?(:authenticate_user!) }
  
  def index
    @economics = PlatformEconomicsService.dashboard
    @distributions = recent_distributions
  rescue => e
    Rails.logger.error "[Transparency] Dashboard error: #{e.message}"
    @economics = empty_economics
    @distributions = []
  end

  # API endpoint for real-time updates
  def api
    economics = PlatformEconomicsService.dashboard
    distributions = recent_distributions
    
    render json: {
      success: true,
      data: {
        financials: economics[:financials],
        token_economy: economics[:token_economy],
        revenue_breakdown: economics[:revenue_breakdown],
        cost_breakdown: economics[:cost_breakdown],
        distributions: distributions.map do |d|
          {
            period: d.period,
            gross_revenue: d.gross_revenue,
            holder_pool: d.holder_pool,
            usdc_distributed: d.usdc_distributed,
            recipients_count: d.recipients_count,
            average_payout: d.average_payout
          }
        end
      },
      generated_at: Time.current
    }
  rescue => e
    Rails.logger.error "[Transparency] API error: #{e.message}"
    render json: { success: false, error: "Unable to load transparency data" }, status: :internal_server_error
  end

  private

  def recent_distributions
    if defined?(RevenueDistribution) && RevenueDistribution.table_exists?
      RevenueDistribution.recent.limit(12)
    else
      []
    end
  rescue
    []
  end

  def empty_economics
    {
      financials: {
        monthly_revenue: 0,
        monthly_costs: 0,
        profit_margin: 0,
        runway_months: 0,
        profit_ratio: 0
      },
      token_economy: {
        total_staked: 0,
        daily_emission: ContributionRewardCalculator.current_daily_emission,
        decay_rate: 0.10,
        decay_status: 'unknown',
        halving_multiplier: ContributionRewardCalculator.current_halving_multiplier
      },
      cost_breakdown: {},
      revenue_breakdown: {},
      generated_at: Time.current
    }
  end

  # Helper method for decay color
  helper_method :decay_color
  def decay_color(rate)
    return "secondary" if rate.nil?
    
    case rate
    when 0..0.05 then "success"
    when 0.05..0.10 then "primary"
    when 0.10..0.15 then "warning"
    else "danger"
    end
  end
end
