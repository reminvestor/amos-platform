# frozen_string_literal: true

# TokenEconomyService manages the platform's token-based ownership economy
# 
# Key responsibilities:
# - Award stakes for distribution (affiliate sales, referrals)
# - Award stakes for contributions (code, community)
# - Apply decay to all stakes
# - Calculate revenue distribution
# - Provide transparency metrics
#
# The token economy is designed to:
# - Align incentives (contributors and sellers are owners)
# - Encourage continued participation (decay function)
# - Be fully transparent (all ownership visible)
class TokenEconomyService
  # Revenue allocation percentages
  REVENUE_ALLOCATION = {
    token_holders: 0.40,    # 40% to token stake holders
    operations: 0.30,       # 30% to operations
    r_and_d: 0.20,          # 20% to R&D (voted by token holders)
    treasury: 0.10          # 10% to treasury/reserves
  }.freeze

  # Stake multipliers for different activities
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

      user = commission.affiliate.user
      stake_amount = commission.amount * DISTRIBUTION_MULTIPLIERS[:affiliate_sale]

      TokenStake.create_distribution_stake!(
        user: user,
        amount: stake_amount,
        category: 'affiliate_sale',
        source: commission,
        metadata: {
          commission_id: commission.id,
          commission_amount: commission.amount,
          referral_id: commission.referral_id
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

    # Apply decay to all active stakes
    # Should be run daily via scheduled job
    def apply_daily_decay!
      Rails.logger.info "🔄 Applying daily decay to token stakes..."
      
      stakes_processed = 0
      total_decayed = 0

      TokenStake.active.find_each do |stake|
        before_amount = stake.current_amount
        stake.apply_decay!
        
        decayed = before_amount - stake.current_amount
        if decayed > 0
          total_decayed += decayed
          
          # Record decay transaction
          TokenStakeTransaction.create!(
            token_stake: stake,
            user: stake.user,
            transaction_type: 'decay',
            amount: -decayed,
            balance_before: before_amount,
            balance_after: stake.current_amount,
            description: "Daily decay applied (#{(stake.decay_rate * 100).round(1)}% annual rate)"
          )
        end
        
        stakes_processed += 1
      end

      Rails.logger.info "✅ Decay complete: #{stakes_processed} stakes processed, #{total_decayed.round(2)} tokens decayed"
      
      { stakes_processed: stakes_processed, total_decayed: total_decayed }
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
  end
end
