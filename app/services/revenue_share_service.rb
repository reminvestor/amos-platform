# frozen_string_literal: true

# RevenueShareService handles the distribution of platform revenue to token holders
# 
# REVENUE MODEL:
# Platform charges 20% markup on compute - this IS the revenue
# 50% of that revenue goes to token holders
#
# HYBRID DISTRIBUTION:
# - 50% of holder share → Direct USDC payment
# - 50% of holder share → Buyback & Burn (market purchase, then burn)
#
# This gives holders:
# 1. Real cash flow (USDC payments)
# 2. Token appreciation (buyback creates demand + burn reduces supply)
#
# ELIGIBILITY:
# - Only INTERNAL platform holdings count (not on-chain tokens)
# - Based on current_amount (post-decay)
# - Minimum threshold to receive payout (avoid dust)
# - SECURITY: 30-day minimum stake duration (prevents just-in-time staking attack)
class RevenueShareService
  # How to split the holder pool (50/50 USDC and buyback)
  DISTRIBUTION_METHOD = {
    usdc_direct: 0.50,      # 50% paid directly in USDC
    buyback_burn: 0.50      # 50% used to buy AMOS & burn
  }.freeze

  # Minimum payout threshold (avoid tiny transactions)
  MINIMUM_PAYOUT_USDC = 1.00

  # Minimum stake to be eligible for revenue share
  MINIMUM_STAKE_FOR_REVENUE = 100

  # SECURITY: Minimum days a stake must be held before earning revenue share
  # Prevents "just-in-time" staking attack where someone deposits right before
  # distribution and claims right after
  MINIMUM_STAKE_DAYS_FOR_REVENUE = 30

  class << self
    # Execute monthly revenue distribution
    # @param gross_revenue [Numeric] Total platform revenue for the period
    # @param period [String] Period identifier (e.g., "2026-01")
    # @return [Hash] Distribution results
    def distribute!(gross_revenue:, period:)
      return { error: 'No revenue to distribute' } if gross_revenue <= 0

      # Calculate the token holder pool (50% of revenue from 20% compute markup)
      holder_pool = gross_revenue * TokenEconomyService::REVENUE_ALLOCATION[:token_holders]
      
      # Split into USDC and buyback portions
      usdc_pool = holder_pool * DISTRIBUTION_METHOD[:usdc_direct]
      buyback_pool = holder_pool * DISTRIBUTION_METHOD[:buyback_burn]

      # Calculate each holder's share
      distributions = calculate_distributions(usdc_pool)
      
      # Execute USDC payments
      usdc_results = execute_usdc_payments(distributions, period)
      
      # Execute buyback and burn
      buyback_results = execute_buyback_burn(buyback_pool, period)

      # Record the distribution
      record_distribution(
        period: period,
        gross_revenue: gross_revenue,
        holder_pool: holder_pool,
        usdc_distributed: usdc_results[:total_paid],
        buyback_amount: buyback_results[:tokens_burned],
        recipients_count: usdc_results[:recipients_count]
      )

      {
        success: true,
        period: period,
        gross_revenue: gross_revenue,
        holder_pool: holder_pool,
        usdc_distributed: usdc_results[:total_paid],
        buyback_burned: buyback_results[:tokens_burned],
        recipients: usdc_results[:recipients_count],
        details: {
          usdc: usdc_results,
          buyback: buyback_results
        }
      }
    end

    # Calculate each holder's distribution (dry run)
    # @param gross_revenue [Numeric] Total platform revenue
    # @return [Hash] Projected distributions
    def preview(gross_revenue:)
      holder_pool = gross_revenue * TokenEconomyService::REVENUE_ALLOCATION[:token_holders]
      usdc_pool = holder_pool * DISTRIBUTION_METHOD[:usdc_direct]
      buyback_pool = holder_pool * DISTRIBUTION_METHOD[:buyback_burn]

      distributions = calculate_distributions(usdc_pool)
      
      cutoff_date = MINIMUM_STAKE_DAYS_FOR_REVENUE.days.ago
      eligible_stakes = TokenStake.active
        .where('current_amount >= ?', MINIMUM_STAKE_FOR_REVENUE)
        .where('earned_at <= ?', cutoff_date)
      total_eligible = eligible_stakes.sum(:current_amount)
      
      {
        gross_revenue: gross_revenue,
        holder_pool: holder_pool,
        usdc_pool: usdc_pool,
        buyback_pool: buyback_pool,
        eligible_holders: distributions.count,
        total_active_stake: TokenStake.active.sum(:current_amount),
        total_eligible_stake: total_eligible,
        minimum_stake_days: MINIMUM_STAKE_DAYS_FOR_REVENUE,
        ineligible_stake_note: "Stakes less than #{MINIMUM_STAKE_DAYS_FOR_REVENUE} days old are excluded",
        distribution_preview: distributions.map do |user_id, amount|
          user = User.find_by(id: user_id)
          stake = eligible_stakes.where(user_id: user_id).sum(:current_amount)
          {
            user_id: user_id,
            email: user&.email&.gsub(/(?<=.{2}).+(?=@)/, '***'),
            eligible_stake: stake,
            ownership_pct: total_eligible > 0 ? (stake / total_eligible * 100).round(4) : 0,
            usdc_payout: amount.round(2),
            estimated_buyback_value: total_eligible > 0 ? (buyback_pool * stake / total_eligible).round(2) : 0
          }
        end.sort_by { |d| -d[:usdc_payout] }
      }
    end

    private

    # Calculate distribution amounts for each eligible holder
    # SECURITY: Only includes stakes held for at least 30 days (prevents JIT attack)
    def calculate_distributions(usdc_pool)
      cutoff_date = MINIMUM_STAKE_DAYS_FOR_REVENUE.days.ago
      
      # Only count stakes that meet BOTH criteria:
      # 1. Minimum amount (100 AMOS)
      # 2. Minimum holding period (30 days)
      eligible_stakes = TokenStake.active
        .where('current_amount >= ?', MINIMUM_STAKE_FOR_REVENUE)
        .where('earned_at <= ?', cutoff_date)
      
      total_stake = eligible_stakes.sum(:current_amount)
      
      return {} if total_stake.zero?

      distributions = {}

      eligible_stakes
        .select('user_id, SUM(current_amount) as total_stake')
        .group(:user_id)
        .each do |row|
          ownership_pct = row.total_stake / total_stake
          payout = usdc_pool * ownership_pct
          
          # Only include if above minimum threshold
          distributions[row.user_id] = payout if payout >= MINIMUM_PAYOUT_USDC
        end

      distributions
    end

    # Execute USDC payments to holders
    def execute_usdc_payments(distributions, period)
      total_paid = 0
      successful = 0
      failed = 0
      payments = []

      distributions.each do |user_id, amount|
        user = User.find_by(id: user_id)
        next unless user

        begin
          # Create payment record
          payment = RevenuePayment.create!(
            user: user,
            amount: amount,
            currency: 'USDC',
            period: period,
            status: 'pending',
            payment_method: 'platform_credit', # or 'solana_transfer' if wallet connected
            metadata: {
              stake_at_distribution: TokenStake.active.where(user: user).sum(:current_amount),
              ownership_percentage: calculate_ownership_percentage(user)
            }
          )

          # If user has connected Solana wallet, queue transfer
          if user.solana_wallet_address.present? && user.preferred_disbursement == 'usdc'
            payment.update!(payment_method: 'solana_transfer')
            ProcessRevenuePaymentJob.perform_later(payment.id)
          else
            # Credit to platform balance (can be claimed later)
            payment.update!(status: 'credited')
          end

          total_paid += amount
          successful += 1
          payments << { user_id: user_id, amount: amount, status: payment.status }

        rescue => e
          Rails.logger.error "[REVENUE_SHARE] Failed payment to user #{user_id}: #{e.message}"
          failed += 1
        end
      end

      {
        total_paid: total_paid.round(2),
        recipients_count: successful,
        failed_count: failed,
        payments: payments
      }
    end

    # Execute buyback and burn
    def execute_buyback_burn(buyback_pool, period)
      return { tokens_burned: 0, note: 'No buyback pool' } if buyback_pool <= 0

      begin
        # In production, this would:
        # 1. Use Jupiter API to get quote for USDC → AMOS
        # 2. Execute the swap
        # 3. Burn the acquired tokens

        # For now, simulate the buyback
        token_price = ContributionRewardCalculator.current_token_price
        tokens_to_buy = buyback_pool / token_price

        # Record the buyback intent
        buyback_record = TokenBuyback.create!(
          period: period,
          usdc_amount: buyback_pool,
          estimated_tokens: tokens_to_buy,
          token_price_at_buyback: token_price,
          status: 'pending'
        )

        # Queue the actual buyback job
        ProcessBuybackJob.perform_later(buyback_record.id)

        {
          tokens_burned: tokens_to_buy.round(4),
          usdc_spent: buyback_pool.round(2),
          price_used: token_price,
          buyback_id: buyback_record.id,
          status: 'queued'
        }

      rescue => e
        Rails.logger.error "[REVENUE_SHARE] Buyback failed: #{e.message}"
        { tokens_burned: 0, error: e.message }
      end
    end

    def calculate_ownership_percentage(user)
      total = TokenStake.active.sum(:current_amount)
      return 0 if total.zero?
      
      user_stake = TokenStake.active.where(user: user).sum(:current_amount)
      (user_stake / total * 100).round(4)
    end

    def record_distribution(period:, gross_revenue:, holder_pool:, usdc_distributed:, buyback_amount:, recipients_count:)
      RevenueDistribution.create!(
        period: period,
        gross_revenue: gross_revenue,
        holder_pool: holder_pool,
        usdc_distributed: usdc_distributed,
        buyback_burned: buyback_amount,
        recipients_count: recipients_count,
        distributed_at: Time.current
      )
    end
  end
end
