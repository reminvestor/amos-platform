# frozen_string_literal: true

# PlatformEconomicsService
# 
# Tracks real platform economics (costs, revenue) and calculates
# dynamic token decay rates based on actual financial health.
#
# The core insight: Decay isn't arbitrary - it represents the real cost
# of maintaining the platform that benefits token holders. When the platform
# is profitable, decay is lower. When costs exceed revenue, decay increases
# to recycle tokens back to treasury for operations.
#
# This creates ORGANIC equilibrium - the token economy self-balances.
#
class PlatformEconomicsService
  # Base annual decay rate when platform is at break-even
  BASE_DECAY_RATE = 0.10 # 10% annual at equilibrium
  
  # Minimum decay rate (even profitable platforms have some decay)
  MIN_DECAY_RATE = 0.02 # 2% annual minimum
  
  # Maximum decay rate (cap to prevent excessive loss)
  MAX_DECAY_RATE = 0.25 # 25% annual maximum
  
  # How much decay adjusts per unit of profit/loss ratio
  DECAY_SENSITIVITY = 0.05
  
  # Revenue allocation (must match TokenEconomyService)
  REVENUE_ALLOCATION = {
    token_holders: 0.50,  # 50% to stakers
    r_and_d: 0.30,        # 30% to development
    operations: 0.10,     # 10% to third-party tools
    treasury: 0.10        # 10% to emergency fund
  }.freeze

  class << self
    # Calculate current dynamic decay rate based on platform economics
    # Returns annual decay rate as decimal (e.g., 0.10 = 10%)
    def current_decay_rate
      # Use thread-local guard to prevent recursion
      return BASE_DECAY_RATE if Thread.current[:_calculating_decay_rate]
      
      Thread.current[:_calculating_decay_rate] = true
      begin
        economics = current_economics
        
        # If no data, use base rate
        return BASE_DECAY_RATE if economics[:monthly_revenue].zero? && economics[:monthly_costs].zero?
        
        # Calculate profit ratio: (revenue - costs) / costs
        # Positive = profitable, negative = losing money
        if economics[:monthly_costs] > 0
          profit_ratio = (economics[:monthly_revenue] - economics[:monthly_costs]) / economics[:monthly_costs].to_f
        else
          profit_ratio = economics[:monthly_revenue] > 0 ? 1.0 : 0.0
        end
        
        # Adjust decay rate based on profit ratio
        # Profitable (positive ratio) → lower decay
        # Unprofitable (negative ratio) → higher decay
        adjusted_rate = BASE_DECAY_RATE - (profit_ratio * DECAY_SENSITIVITY)
        
        # Clamp to min/max bounds
        [[adjusted_rate, MIN_DECAY_RATE].max, MAX_DECAY_RATE].min
      rescue => e
        Rails.logger.warn "[PlatformEconomics] Error calculating decay rate: #{e.message}"
        BASE_DECAY_RATE
      ensure
        Thread.current[:_calculating_decay_rate] = nil
      end
    end
    
    # Get current platform economics
    def current_economics
      # Try to get from cache first
      cached = Rails.cache.read("platform_economics:current")
      return cached if cached.present?
      
      # Calculate fresh
      economics = calculate_economics
      
      # Cache for 1 hour
      Rails.cache.write("platform_economics:current", economics, expires_in: 1.hour)
      
      economics
    end
    
    # Calculate platform economics from real data
    def calculate_economics
      now = Time.current
      start_of_month = now.beginning_of_month
      last_30_days = now - 30.days
      
      {
        # Revenue from subscriptions, compute sales, etc.
        monthly_revenue: calculate_monthly_revenue(start_of_month),
        last_30_days_revenue: calculate_monthly_revenue(last_30_days),
        
        # Costs: compute, infrastructure, third-party services
        monthly_costs: calculate_monthly_costs(start_of_month),
        last_30_days_costs: calculate_monthly_costs(last_30_days),
        
        # Derived metrics
        profit_margin: calculate_profit_margin,
        runway_months: calculate_runway,
        
        # Token economy health
        total_staked: TokenStake.active.sum(:current_amount),
        daily_emission: ContributionRewardCalculator::BASE_DAILY_EMISSION,
        decay_rate: current_decay_rate,
        
        # Timestamps
        calculated_at: now,
        period_start: start_of_month
      }
    end
    
    # Record platform costs (called by admin or automated processes)
    def record_cost(category:, amount:, description: nil, metadata: {})
      PlatformCost.create!(
        category: category,
        amount: amount,
        description: description,
        recorded_at: Time.current,
        metadata: metadata
      )
      
      # Invalidate cache
      Rails.cache.delete("platform_economics:current")
    end
    
    # Get decay rate explanation for transparency
    def decay_rate_explanation
      economics = current_economics
      rate = current_decay_rate
      
      status = if rate <= MIN_DECAY_RATE + 0.02
        "excellent"
      elsif rate <= BASE_DECAY_RATE
        "healthy"
      elsif rate <= BASE_DECAY_RATE + 0.05
        "moderate"
      else
        "elevated"
      end
      
      {
        current_rate: rate,
        annual_percentage: (rate * 100).round(2),
        daily_rate: (rate / 365.0).round(6),
        status: status,
        explanation: generate_explanation(economics, rate, status),
        factors: {
          monthly_revenue: economics[:monthly_revenue],
          monthly_costs: economics[:monthly_costs],
          profit_margin: economics[:profit_margin]
        }
      }
    end
    
    # Project token value over time with dynamic decay
    def project_stake_value(initial_amount:, months: 12, assume_contribution: false)
      projections = []
      current_value = initial_amount.to_f
      
      # Get current decay rate (may change over time in reality)
      monthly_decay = current_decay_rate / 12.0
      
      # If contributing, estimate earning rate
      monthly_contribution = assume_contribution ? estimate_monthly_earnings : 0
      
      months.times do |month|
        # Apply decay
        decay_amount = current_value * monthly_decay
        floor_amount = initial_amount * graduated_floor_percentage(month)
        
        # Don't decay below floor
        new_value = [current_value - decay_amount, floor_amount].max
        
        # Add contributions if active
        new_value += monthly_contribution if assume_contribution
        
        projections << {
          month: month + 1,
          value: new_value.round(2),
          decay_applied: decay_amount.round(2),
          floor: floor_amount.round(2),
          contribution: monthly_contribution.round(2)
        }
        
        current_value = new_value
      end
      
      projections
    end
    
    # Get the decay rate that would apply to a specific stake
    def decay_rate_for_stake(token_stake)
      base_rate = current_decay_rate
      
      # Apply tenure-based reduction
      tenure_years = token_stake.tenure_years
      
      reduction = case tenure_years
        when 0..1 then 0.0
        when 1..3 then 0.10  # 10% reduction
        when 3..5 then 0.20  # 20% reduction
        else 0.30            # 30% reduction for 5+ years
      end
      
      # Apply staking vault reduction if stake is locked
      if token_stake.locked? && token_stake.staking_tier.present?
        tier = TokenStake::STAKING_TIERS[token_stake.staking_tier.to_sym]
        if tier
          vault_reduction = tier[:decay_reduction] || 0.0
          reduction = [reduction, vault_reduction].max
        end
      end
      
      # Calculate final rate with reductions
      (base_rate * (1 - reduction)).round(4)
    end
    
    private
    
    def calculate_monthly_revenue(since_date)
      # Sum up all revenue sources
      total = 0.0
      
      # Subscription revenue
      if safe_table_exists?('subscriptions')
        total += (Subscription.where('created_at >= ?', since_date)
                              .where(status: 'active')
                              .sum(:amount_cents).to_f rescue 0.0) / 100.0
      end
      
      # Payment transactions
      if safe_table_exists?('payment_transactions')
        total += (PaymentTransaction.where('created_at >= ?', since_date)
                                    .where(status: 'completed')
                                    .sum(:amount_cents).to_f rescue 0.0) / 100.0
      end
      
      # Compute usage billing (from billed compute)
      if safe_table_exists?('compute_usages')
        total += (ComputeUsage.where('created_at >= ?', since_date)
                              .where(billed: true)
                              .sum(:cost_cents).to_f rescue 0.0) / 100.0
      end
      
      total
    end
    
    def calculate_monthly_costs(since_date)
      total = 0.0
      
      # Recorded platform costs - only query if table exists
      if safe_table_exists?('platform_costs')
        total += PlatformCost.where('recorded_at >= ?', since_date).sum(:amount).to_f rescue 0.0
      end
      
      # Estimate compute costs from usage - only if table exists
      if safe_table_exists?('compute_usages')
        billed = (ComputeUsage.where('created_at >= ?', since_date).sum(:cost_cents).to_f rescue 0.0) / 100.0
        total += billed * 0.80
      end
      
      total
    end
    
    def safe_table_exists?(table_name)
      ActiveRecord::Base.connection.table_exists?(table_name)
    rescue
      false
    end
    
    def calculate_profit_margin
      economics = {
        monthly_revenue: calculate_monthly_revenue(Time.current.beginning_of_month),
        monthly_costs: calculate_monthly_costs(Time.current.beginning_of_month)
      }
      
      return 0.0 if economics[:monthly_revenue].zero?
      
      ((economics[:monthly_revenue] - economics[:monthly_costs]) / economics[:monthly_revenue] * 100).round(2)
    end
    
    def calculate_runway
      # How many months of operations can treasury cover at current burn rate
      treasury_balance = 0.0
      
      if safe_table_exists?('treasury_balances')
        treasury_balance = TreasuryBalance.current_balance.to_f rescue 0.0
      end
      
      monthly_costs = calculate_monthly_costs(Time.current.beginning_of_month)
      monthly_revenue = calculate_monthly_revenue(Time.current.beginning_of_month)
      
      monthly_burn = monthly_costs - monthly_revenue
      
      return 999 if monthly_burn <= 0  # Profitable = infinite runway
      return 999 if monthly_burn.zero?  # Prevent division by zero
      
      (treasury_balance / monthly_burn).floor
    end
    
    def generate_explanation(economics, rate, status)
      case status
      when "excellent"
        "Platform is highly profitable. Decay rate minimized to reward long-term holders."
      when "healthy"
        "Platform economics are healthy. Decay rate at sustainable equilibrium level."
      when "moderate"
        "Platform is near break-even. Decay rate slightly elevated to maintain operations."
      when "elevated"
        "Platform costs exceed revenue. Higher decay rate recycles tokens to fund operations. " \
        "Consider contributing to earn tokens and offset decay."
      end
    end
    
    def graduated_floor_percentage(months)
      years = months / 12.0
      
      case years
      when 0..1 then 0.05
      when 1..3 then 0.10
      when 3..5 then 0.15
      else 0.25
      end
    end
    
    def estimate_monthly_earnings
      # Estimate average monthly token earnings for an active contributor
      daily_emission = ContributionRewardCalculator::BASE_DAILY_EMISSION
      active_contributors = Contribution.where('created_at > ?', 30.days.ago)
                                        .distinct.count(:user_id)
      
      return 0 if active_contributors.zero?
      
      # Average monthly earning = (daily emission * 30) / active contributors
      (daily_emission * 30.0 / active_contributors).round(2)
    rescue
      1000.0  # Default estimate
    end
    
    # =========================================================================
    # ECONOMICS DASHBOARD - Complete platform financial overview
    # =========================================================================
    
    public
    
    # Get complete economics dashboard for admin/transparency
    def self.dashboard
      economics = current_economics
      decay_info = decay_rate_explanation
      
      {
        # Real-world financials
        financials: {
          monthly_revenue: economics[:monthly_revenue],
          monthly_costs: economics[:monthly_costs],
          profit_margin: economics[:profit_margin],
          runway_months: economics[:runway_months],
          profit_ratio: calculate_profit_ratio
        },
        
        # Token economy health
        token_economy: {
          total_staked: economics[:total_staked],
          daily_emission: economics[:daily_emission],
          decay_rate: decay_info[:current_rate],
          decay_status: decay_info[:status],
          halving_multiplier: ContributionRewardCalculator.current_halving_multiplier
        },
        
        # Cost breakdown
        cost_breakdown: cost_breakdown_by_category,
        
        # Revenue breakdown
        revenue_breakdown: revenue_breakdown_by_source,
        
        # Key equations (for transparency)
        equations: {
          decay_formula: "δ = 10% - (π × 5%) where π = (R - C) / C",
          current_profit_ratio: "π = #{calculate_profit_ratio.round(4)}",
          current_decay_calc: "δ = 10% - (#{calculate_profit_ratio.round(4)} × 5%) = #{(decay_info[:current_rate] * 100).round(2)}%"
        },
        
        # Timestamp
        generated_at: Time.current
      }
    end
    
    # Calculate the profit ratio (the bridge between real economy and token economy)
    def self.calculate_profit_ratio
      economics = current_economics
      return 0.0 if economics[:monthly_costs].zero?
      
      (economics[:monthly_revenue] - economics[:monthly_costs]) / economics[:monthly_costs].to_f
    end
    
    # Get cost breakdown by category
    def self.cost_breakdown_by_category
      return {} unless safe_table_exists?('platform_costs')
      
      start_of_month = Time.current.beginning_of_month
      
      costs = PlatformCost.where('recorded_at >= ?', start_of_month)
                         .group(:category)
                         .sum(:amount)
      
      # Add estimated AI costs from usage logs
      if safe_table_exists?('ai_usage_logs')
        ai_costs = AiUsageLog.where('created_at >= ?', start_of_month)
                            .sum(:cost_cents).to_f / 100.0
        costs['ai_compute'] = (costs['ai_compute'] || 0) + ai_costs
      end
      
      # Add work token usage costs
      if safe_table_exists?('work_token_usage_summaries')
        work_costs = WorkTokenUsageSummary.where('summary_date >= ?', start_of_month.to_date)
                                          .sum(:raw_cost_cents).to_f / 100.0
        costs['tracked_compute'] = work_costs
      end
      
      costs.transform_values { |v| v.round(2) }
    rescue => e
      Rails.logger.warn "[PlatformEconomics] Error getting cost breakdown: #{e.message}"
      {}
    end
    
    # Get revenue breakdown by source
    def self.revenue_breakdown_by_source
      start_of_month = Time.current.beginning_of_month
      breakdown = {}
      
      # Subscription revenue
      if safe_table_exists?('subscriptions')
        breakdown[:subscriptions] = Subscription.where('created_at >= ?', start_of_month)
                                                .where(status: 'active')
                                                .sum(:amount_cents).to_f / 100.0 rescue 0.0
      end
      
      # Compute revenue (from work tokens with markup)
      if safe_table_exists?('work_token_usage_summaries')
        breakdown[:compute_usage] = WorkTokenUsageSummary.where('summary_date >= ?', start_of_month.to_date)
                                                         .sum(:uplifted_cost_cents).to_f / 100.0 rescue 0.0
      end
      
      # Payment transactions
      if safe_table_exists?('payment_transactions')
        breakdown[:payments] = PaymentTransaction.where('created_at >= ?', start_of_month)
                                                  .where(status: 'completed')
                                                  .sum(:amount_cents).to_f / 100.0 rescue 0.0
      end
      
      breakdown.transform_values { |v| v.round(2) }
    rescue => e
      Rails.logger.warn "[PlatformEconomics] Error getting revenue breakdown: #{e.message}"
      {}
    end
  end
end
