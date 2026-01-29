# frozen_string_literal: true

# RevenueShareService handles the distribution of platform revenue to token holders
# 
# HYBRID MODEL:
# - 60% of holder share → Direct USDC payment
# - 40% of holder share → Buyback & Burn (market purchase, then burn)
#
# This gives holders:
# 1. Real cash flow (USDC payments)
# 2. Token appreciation (buyback creates demand + burn reduces supply)
#
# ELIGIBILITY:
# - Only INTERNAL platform holdings count (not on-chain tokens)
# - Based on current_amount (post-decay)
# - Minimum threshold to receive payout (avoid dust)
class RevenueShareService
  # How to split the holder pool
  DISTRIBUTION_METHOD = {
    usdc_direct: 0.60,      # 60% paid directly in USDC
    buyback_burn: 0.40      # 40% used to buy AMOS & burn
  }.freeze

  # Minimum payout threshold (avoid tiny transactions)
  MINIMUM_PAYOUT_USDC = 1.00

  # Minimum stake to be eligible for revenue share
  MINIMUM_STAKE_FOR_REVENUE = 100

  class << self
    # Execute monthly revenue distribution
    # @param gross_revenue [Numeric] Total platform revenue for the period
    # @param period [String] Period identifier (e.g., "2026-01")
    # @return [Hash] Distribution results
    def distribute!(gross_revenue:, period:)
      return { error: 'No revenue to distribute' } if gross_revenue <= 0

      # Calculate the token holder pool (40% of revenue)
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
      
      {
        gross_revenue: gross_revenue,
        holder_pool: holder_pool,
        usdc_pool: usdc_pool,
        buyback_pool: buyback_pool,
        eligible_holders: distributions.count,
        total_active_stake: TokenStake.active.sum(:current_amount),
        distribution_preview: distributions.map do |user_id, amount|
          user = User.find_by(id: user_id)
          stake = TokenStake.active.where(user_id: user_id).sum(:current_amount)
          {
            user_id: user_id,
            email: user&.email&.gsub(/(?<=.{2}).+(?=@)/, '***'),
            stake: stake,
            ownership_pct: (stake / TokenStake.active.sum(:current_amount) * 100).round(4),
            usdc_payout: amount.round(2),
            estimated_buyback_value: (buyback_pool * stake / TokenStake.active.sum(:current_amount)).round(2)
          }
        end.sort_by { |d| -d[:usdc_payout] }
      }
    end

    private

    # Calculate distribution amounts for each eligible holder
    def calculate_distributions(usdc_pool)
      total_stake = TokenStake.active
        .where('current_amount >= ?', MINIMUM_STAKE_FOR_REVENUE)
        .sum(:current_amount)
      
      return {} if total_stake.zero?

      distributions = {}

      TokenStake.active
        .where('current_amount >= ?', MINIMUM_STAKE_FOR_REVENUE)
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
