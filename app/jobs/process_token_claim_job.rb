# frozen_string_literal: true

# ProcessTokenClaimJob handles the actual Solana transaction for token claims
#
# This job:
# 1. Validates the claim has sufficient balance
# 2. Sends tokens via SolanaTokenService
# 3. Updates claim status based on result
class ProcessTokenClaimJob < ApplicationJob
  queue_as :blockchain
  
  # Retry with exponential backoff
  retry_on SolanaTokenService::SolanaError, wait: :polynomially_longer, attempts: 3
  discard_on SolanaTokenService::InvalidAddressError

  def perform(claim_id)
    claim = TokenClaim.find(claim_id)
    
    Rails.logger.info "[CLAIM] Processing claim ##{claim_id} for #{claim.amount} tokens"

    # Skip if already completed or cancelled
    if claim.status.in?(%w[completed cancelled])
      Rails.logger.info "[CLAIM] Claim ##{claim_id} already #{claim.status}, skipping"
      return
    end

    # Validate if still pending
    if claim.status == 'pending'
      unless claim.validate_claim!
        Rails.logger.warn "[CLAIM] Claim ##{claim_id} validation failed: #{claim.error_message}"
        return
      end
    end

    # Start processing
    claim.start_processing!

    begin
      # Send tokens via Solana
      signature = SolanaTokenService.send_tokens(
        to_address: claim.wallet_address,
        amount: claim.net_amount,  # Amount after fees
        claim_id: claim.id
      )

      # Get transaction details
      tx = SolanaTokenService.get_transaction(signature)
      
      # Complete the claim
      claim.complete!(
        transaction_signature: signature,
        blockhash: tx&.dig('transaction', 'message', 'recentBlockhash'),
        slot: tx&.dig('slot')
      )

      Rails.logger.info "[CLAIM] Claim ##{claim_id} completed. Signature: #{signature}"

      # Notify user
      notify_user_claim_completed(claim)

    rescue SolanaTokenService::InsufficientFundsError => e
      claim.fail!("Treasury insufficient funds: #{e.message}")
      notify_admin_treasury_low(claim)
      raise # Re-raise to trigger retry

    rescue SolanaTokenService::TransactionFailedError => e
      claim.fail!("Transaction failed: #{e.message}")
      Rails.logger.error "[CLAIM] Claim ##{claim_id} failed: #{e.message}"
      raise # Re-raise to trigger retry

    rescue => e
      claim.fail!("Unexpected error: #{e.message}")
      Rails.logger.error "[CLAIM] Claim ##{claim_id} unexpected error: #{e.message}"
      raise
    end
  end

  private

  def notify_user_claim_completed(claim)
    # Send notification to user
    # ClaimNotificationMailer.completed(claim).deliver_later
    Rails.logger.info "[CLAIM] Would notify user #{claim.user_id} of completed claim"
  end

  def notify_admin_treasury_low(claim)
    # Alert admins that treasury is low
    Rails.logger.error "[CLAIM] ALERT: Treasury low! Claim ##{claim.id} failed due to insufficient funds"
  end
end
