# frozen_string_literal: true

# TokenEconomyService manages the platform's token-based ownership economy
# 
# Key responsibilities:
# - Award stakes for distribution (affiliate sales, referrals)
# - Award stakes for contributions (code, community)
# - Apply decay to all stakes with recycling to treasury
# - Burn tokens on payouts for deflation
# - Calculate revenue distribution
# - Provide transparency metrics
#
# ORGANIC ECONOMICS:
# - Decay is DYNAMIC based on platform revenue vs costs
# - Profitable platform → lower decay (rewarding holders)
# - Unprofitable platform → higher decay (recycling to operations)
# - This creates self-balancing equilibrium
#
# The token economy is designed to:
# - Align incentives (contributors and sellers are owners)
# - Tie decay to REAL economics (not arbitrary rates)
# - Encourage continued participation (dynamic decay function)
# - Be fully transparent (all ownership visible)
# - Allow wealth preservation (decay floor, tenure reduction)
# - Create scarcity (fixed supply, halving, burn)
class TokenEconomyService
  # Fixed supply
  TOTAL_SUPPLY = 100_000_000  # 100M tokens ever
  
  # Allocation percentages
  TOKEN_ALLOCATION = {
    treasury: 0.60,     # 60M - For ongoing contributor rewards
    entity: 0.15,       # 15M - AMOS Labs Inc. (company runway/strategic)
    investors: 0.10,    # 10M - Future investment rounds (if needed)
    community: 0.10,    # 10M - Grants, airdrops, ecosystem
    reserve: 0.05       # 5M  - Emergency (DAO-locked)
    # Founders: 0 - Start at zero, earn like everyone else
  }.freeze

  # Revenue allocation percentages (from 20% compute markup)
  REVENUE_ALLOCATION = {
    token_holders: 0.50,    # 50% to token stake holders - immutable on-chain
    r_and_d: 0.40,          # 40% to R&D (software, infra, research, AI work)
    treasury: 0.05,         # 5% to emergency treasury (DAO-controlled)
    operations: 0.05        # 5% to operations (accounting, legal only)
  }.freeze

  # Burn rates for deflation
  BURN_RATES = {
    revenue_payout: 0.01,    # 1% of payouts burned
    stake_transfer: 0.02,    # 2% on transfers burned
    decay_portion: 0.10      # 10% of decay burned (rest recycled)
  }.freeze

  # AMOS Labs entity lockup parameters
  # The company's 15% allocation is locked for 10 years with NO decay
  # This signals long-term commitment and eliminates dump risk
  ENTITY_LOCKUP = {
    allocation: 15_000_000,        # 15M AMOS (15% of supply)
    lockup_years: 10,              # 10 years locked
    unlock_years: 2,               # 2 years linear unlock after lockup
    decay_rate: 0.0,               # NO decay while locked
    can_stake: true,               # CAN stake for revenue share
    can_vote: true                 # CAN vote in governance
  }.freeze

  # LP incentive program (to bootstrap liquidity)
  LP_INCENTIVES = {
    total_allocation: 3_000_000,   # 3M AMOS (3% of supply) for LP rewards
    year_1: 1_500_000,             # 1.5M AMOS Year 1 (bootstrap incentive)
    year_2: 1_000_000,             # 1M AMOS Year 2
    year_3: 500_000,               # 500k AMOS Year 3
    trading_fee_bps: 25,           # 0.25% trading fee to LPs
    founder_lp_fee_bps: 5          # 0.05% permanent fee to founder LP
  }.freeze

  # Stake multipliers for different activities (pre-halving base amounts)
  DISTRIBUTION_MULTIPLIERS = {
    affiliate_sale: 100,        # 100 tokens per $1 of sale
    referral_conversion: 50,    # 50 tokens per conversion
    enterprise_deal: 200        # 200 tokens per $1 of enterprise sale
  }.freeze

  CONTRIBUTION_MULTIPLIERS = {
    feature: 1000,
    bug_fix: 500,
    code: 300,
    documentation: 200,
    review: 100,
    support: 150,
    content: 250,
    community: 100
  }.freeze

  class << self
    # === DISTRIBUTION STAKES ===

    # Award stake for affiliate commission
    # Called when a commission is approved
    def award_affiliate_stake!(commission)
      return nil unless commission.approved? || commission.paid?
      return nil if TokenStake.treasury_depleted?

      user = commission.affiliate.user
      base_amount = commission.amount * DISTRIBUTION_MULTIPLIERS[:affiliate_sale]
      
      # Apply halving multiplier
      stake_amount = TokenStake.calculate_stake_with_halving(base_amount)

      TokenStake.create_distribution_stake!(
        user: user,
        amount: stake_amount,
        category: 'affiliate_sale',
        source: commission,
        metadata: {
          commission_id: commission.id,
          commission_amount: commission.amount,
          referral_id: commission.referral_id,
          halving_multiplier: TokenStake.current_halving_multiplier,
          base_amount: base_amount
        }
      )
    end

    # Award stake for referral conversion
    # Called when a referred user converts to paid
    def award_referral_stake!(referral)
      return nil unless referral.converted?

      user = referral.affiliate.user
      stake_amount = DISTRIBUTION_MULTIPLIERS[:referral_conversion]

      TokenStake.create_distribution_stake!(
        user: user,
        amount: stake_amount,
        category: 'referral_conversion',
        source: referral,
        metadata: {
          referral_id: referral.id,
          referred_entity_id: referral.referred_entity_id
        }
      )
    end

    # === CONTRIBUTION STAKES ===

    # Award stake for contribution
    # Called when a contribution is approved/merged
    def award_contribution_stake!(contribution)
      return nil unless contribution.approved? || contribution.merged?
      return nil if contribution.stake_awarded?

      stake_value = contribution.stake_value || contribution.calculate_default_stake_value

      TokenStake.create_contribution_stake!(
        user: contribution.user,
        amount: stake_value,
        category: contribution.contribution_type,
        source: contribution,
        metadata: {
          contribution_id: contribution.id,
          title: contribution.title,
          external_reference: contribution.external_reference
        }
      )
    end

    # === DECAY MANAGEMENT ===

    # Apply decay to all active stakes with recycling and burning
    # Should be run daily via scheduled job
    def apply_daily_decay!
      Rails.logger.info "🔄 Applying daily decay to token stakes..."
      
      stakes_processed = 0
      total_decayed = 0
      total_recycled = 0
      total_burned = 0

      TokenStake.active.where('current_amount > 0').find_each do |stake|
        # Skip if at decay floor
        next if stake.at_floor?
        
        before_amount = stake.current_amount
        stake.apply_decay!
        
        decayed = before_amount - stake.current_amount
        if decayed > 0
          total_decayed += decayed
          
          # Split decay: 10% burned, 90% recycled to treasury
          burned = decayed * BURN_RATES[:decay_portion]
          recycled = decayed - burned
          
          total_burned += burned
          total_recycled += recycled
          
          # Record decay transaction
          TokenStakeTransaction.create!(
            token_stake: stake,
            user: stake.user,
            transaction_type: 'decay',
            amount: -decayed,
            balance_before: before_amount,
            balance_after: stake.current_amount,
            description: "Daily decay (#{(stake.effective_annual_decay_rate * 100).round(1)}% rate, Year #{stake.tenure_years})",
            metadata: {
              burned: burned,
              recycled: recycled,
              tenure_years: stake.tenure_years,
              at_floor: stake.at_floor?
            }
          )
        end
        
        stakes_processed += 1
      end

      # Record treasury recycling
      record_treasury_activity(:recycling, total_recycled) if total_recycled > 0
      record_treasury_activity(:burn, -total_burned) if total_burned > 0

      Rails.logger.info "✅ Decay complete: #{stakes_processed} stakes, " \
                        "#{total_decayed.round(2)} decayed, " \
                        "#{total_recycled.round(2)} recycled, " \
                        "#{total_burned.round(2)} burned"
      
      { 
        stakes_processed: stakes_processed, 
        total_decayed: total_decayed,
        total_recycled: total_recycled,
        total_burned: total_burned
      }
    end

    # Record treasury activity for transparency
    # Creates a TokenStakeTransaction as a system record
    def record_treasury_activity(activity_type, amount)
      # Log for transparency (can be exposed via public API)
      Rails.logger.info "[TOKEN_TREASURY] #{activity_type}: #{amount.round(2)} tokens, " \
                        "remaining: #{TokenStake.treasury_remaining.round(2)}"
      
      # Store in metadata for API access
      @treasury_activities ||= []
      @treasury_activities << {
        type: activity_type,
        amount: amount.round(4),
        treasury_remaining: TokenStake.treasury_remaining.round(4),
        timestamp: Time.current
      }
    end

    # Get recent treasury activities (for API)
    def treasury_activities
      @treasury_activities || []
    end

    # === REVENUE DISTRIBUTION ===

    # Calculate revenue share for each token holder
    # Returns hash of user_id => share_amount
    def calculate_revenue_distribution(gross_revenue)
      token_holder_pool = gross_revenue * REVENUE_ALLOCATION[:token_holders]
      total_supply = TokenStake.total_supply

      return {} if total_supply.zero?

      distribution = {}

      TokenStake.active
        .select('user_id, SUM(current_amount) as total_stake')
        .group(:user_id)
        .each do |row|
          ownership_percentage = row.total_stake / total_supply
          share = token_holder_pool * ownership_percentage
          distribution[row.user_id] = share.round(2)
        end

      distribution
    end

    # === TRANSPARENCY METRICS ===

    # Get comprehensive economy stats
    def economy_stats
      {
        total_supply: TokenStake.total_supply,
        active_stakes: TokenStake.active.count,
        total_stakeholders: TokenStake.active.select(:user_id).distinct.count,
        supply_by_type: TokenStake.total_by_type,
        top_stakeholders: TokenStake.top_stakeholders(limit: 10),
        ownership_concentration: calculate_ownership_concentration,
        decay_stats: calculate_decay_stats
      }
    end

    # Get user's token economy profile
    def user_profile(user)
      stakes = TokenStake.for_user(user).active
      
      {
        total_stake: stakes.sum(:current_amount),
        ownership_percentage: calculate_user_ownership_percentage(user),
        stakes_by_type: stakes.group(:stake_type).sum(:current_amount),
        stake_count: stakes.count,
        total_earned: TokenStake.for_user(user).sum(:initial_amount),
        total_decayed: TokenStake.for_user(user).sum(:total_decayed),
        recent_stakes: stakes.recent.limit(10),
        contributions: Contribution.for_user(user).accepted.count,
        projected_monthly_revenue: calculate_projected_monthly_revenue(user)
      }
    end

    # Public ownership distribution (for transparency dashboard)
    def public_ownership_distribution
      total = TokenStake.total_supply
      return [] if total.zero?

      TokenStake.active
        .joins(:user)
        .select(
          'users.id as user_id',
          'users.first_name',
          'users.last_name',
          'SUM(token_stakes.current_amount) as total_stake'
        )
        .group('users.id', 'users.first_name', 'users.last_name')
        .order('total_stake DESC')
        .map do |row|
          display_name = [row.first_name, row.last_name].compact.join(' ').presence || "User #{row.user_id}"
          {
            user_id: row.user_id,
            display_name: display_name,
            total_stake: row.total_stake.round(2),
            ownership_percentage: (row.total_stake / total * 100).round(4)
          }
        end
    end

    # === INTEGRATION WITH EXISTING SYSTEMS ===

    # Hook into affiliate commission approval
    # Add to AffiliateCommissionService or Commission model callbacks
    def on_commission_approved(commission)
      award_affiliate_stake!(commission)
    rescue StandardError => e
      Rails.logger.error "Failed to award affiliate stake: #{e.message}"
      nil
    end

    # Hook into referral conversion
    # Add to Referral model callbacks
    def on_referral_converted(referral)
      award_referral_stake!(referral)
    rescue StandardError => e
      Rails.logger.error "Failed to award referral stake: #{e.message}"
      nil
    end

    private

    def calculate_ownership_concentration
      total = TokenStake.total_supply
      return { gini: 0, top_10_percent: 0 } if total.zero?

      stakes_by_user = TokenStake.active
        .group(:user_id)
        .sum(:current_amount)
        .values
        .sort
        .reverse

      return { gini: 0, top_10_percent: 0 } if stakes_by_user.empty?

      # Calculate top 10% ownership
      top_10_count = [1, (stakes_by_user.length * 0.1).ceil].max
      top_10_sum = stakes_by_user.first(top_10_count).sum
      top_10_percent = (top_10_sum / total * 100).round(2)

      # Calculate Gini coefficient (0 = perfect equality, 1 = perfect inequality)
      n = stakes_by_user.length
      if n > 1
        sum_of_differences = 0
        stakes_by_user.each_with_index do |stake_i, i|
          stakes_by_user.each_with_index do |stake_j, j|
            sum_of_differences += (stake_i - stake_j).abs
          end
        end
        gini = sum_of_differences / (2 * n * n * (total / n))
      else
        gini = 0
      end

      { gini: gini.round(4), top_10_percent: top_10_percent }
    end

    def calculate_decay_stats
      {
        total_decayed_all_time: TokenStake.sum(:total_decayed),
        decay_last_30_days: TokenStakeTransaction.decays
          .where('created_at >= ?', 30.days.ago)
          .sum('ABS(amount)'),
        average_decay_rate: TokenStake.active.average(:decay_rate)&.round(4) || 0
      }
    end

    def calculate_user_ownership_percentage(user)
      total = TokenStake.total_supply
      return 0 if total.zero?

      user_stake = TokenStake.for_user(user).active.sum(:current_amount)
      (user_stake / total * 100).round(4)
    end

    def calculate_projected_monthly_revenue(user)
      # This would use actual revenue data in production
      # For now, return a placeholder based on ownership percentage
      ownership = calculate_user_ownership_percentage(user)
      # Assuming $100K monthly revenue for illustration
      estimated_monthly_revenue = 100_000
      (estimated_monthly_revenue * REVENUE_ALLOCATION[:token_holders] * ownership / 100).round(2)
    end

    # === PLATFORM ECONOMICS TRANSPARENCY ===
    
    # Get comprehensive platform economics summary
    # Exposes how decay connects to real platform costs
    def platform_economics_summary
      economics = PlatformEconomicsService.current_economics
      decay_explanation = PlatformEconomicsService.decay_rate_explanation
      
      {
        # Financial health
        monthly_revenue: economics[:monthly_revenue],
        monthly_costs: economics[:monthly_costs],
        profit_margin: economics[:profit_margin],
        runway_months: economics[:runway_months],
        
        # Dynamic decay (tied to economics)
        current_decay_rate: decay_explanation[:current_rate],
        annual_decay_percent: decay_explanation[:annual_percentage],
        platform_health_status: decay_explanation[:status],
        decay_explanation: decay_explanation[:explanation],
        
        # Token economy state
        total_staked: economics[:total_staked],
        daily_emission: economics[:daily_emission],
        treasury_remaining: TokenStake.treasury_remaining,
        
        # Revenue allocation
        revenue_allocation: REVENUE_ALLOCATION,
        
        # How decay connects to costs
        organic_economics_explanation: <<~EXPLANATION
          Token decay is not arbitrary - it's tied to REAL platform economics.
          
          When the platform is profitable:
          → Decay rate is LOW (#{PlatformEconomicsService::MIN_DECAY_RATE * 100}% minimum)
          → Token holders benefit from success
          
          When costs exceed revenue:
          → Decay rate INCREASES (up to #{PlatformEconomicsService::MAX_DECAY_RATE * 100}% maximum)
          → Tokens recycle to treasury to fund operations
          → This keeps the platform running without external funding
          
          Current status: #{decay_explanation[:status].upcase}
          Your tokens maintain value when the platform succeeds.
        EXPLANATION
      }
    end
    
    # Get decay rate explanation for a specific user's stakes
    def user_decay_explanation(user)
      stakes = TokenStake.for_user(user).active
      return nil if stakes.empty?
      
      platform_rate = PlatformEconomicsService.current_decay_rate
      
      stakes.map do |stake|
        {
          stake_id: stake.id,
          stake_type: stake.stake_type,
          current_amount: stake.current_amount,
          decay_explanation: stake.decay_rate_explanation,
          within_grace_period: stake.within_grace_period?,
          projected_1_year: stake.projected_value_at(1.year.from_now)
        }
      end
    end
  end
end
