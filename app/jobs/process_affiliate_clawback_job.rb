# frozen_string_literal: true

# Job to process affiliate stake clawbacks when a customer churns
#
# SECURITY: This job is triggered when a referred customer cancels their
# subscription within the 90-day clawback period. It revokes the affiliate's
# token stake and returns the tokens to the treasury.
#
# Usage:
#   ProcessAffiliateClawbackJob.perform_later(referral_id: 123, reason: "Customer cancelled")
#
class ProcessAffiliateClawbackJob < ApplicationJob
  queue_as :default

  def perform(referral_id:, reason: nil)
    referral = Referral.find_by(id: referral_id)
    return unless referral

    # Find distribution stakes linked to this referral
    stakes = TokenStake.distribution_stakes
                       .pending_clawback
                       .where(source: referral)
    
    if stakes.empty?
      # Also check for stakes linked via commission
      commission_stakes = TokenStake.distribution_stakes
                                    .pending_clawback
                                    .joins("LEFT JOIN commissions ON commissions.id = token_stakes.source_id AND token_stakes.source_type = 'Commission'")
                                    .where(commissions: { referral_id: referral_id })
      stakes = commission_stakes
    end

    if stakes.empty?
      Rails.logger.info "[CLAWBACK] No clawbackable stakes found for referral #{referral_id}"
      return
    end

    total_clawed = 0
    stakes.each do |stake|
      if stake.clawback!(reason: reason || "Customer churned within #{TokenStake::CLAWBACK_PERIOD_DAYS} days")
        total_clawed += stake.metadata['clawed_amount'] || stake.initial_amount
      end
    end

    Rails.logger.info "[CLAWBACK] Clawed back #{total_clawed} AMOS from #{stakes.count} stakes for referral #{referral_id}"

    # Notify the affiliate
    notify_affiliate(referral, total_clawed) if total_clawed > 0
  end

  private

  def notify_affiliate(referral, amount)
    affiliate = referral.affiliate
    return unless affiliate&.user
    
    # Send notification about clawback
    SystemNotificationService.send_to_user(
      user: affiliate.user,
      category: 'token_economy',
      severity: 'warning',
      title: 'Token Stake Clawed Back',
      message: "#{amount} AMOS was clawed back because the referred customer cancelled within 90 days.",
      metadata: { 
        referral_id: referral.id,
        amount_clawed: amount 
      }
    )
  rescue => e
    Rails.logger.error "[CLAWBACK] Failed to notify affiliate: #{e.message}"
  end
end
