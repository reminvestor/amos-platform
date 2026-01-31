# frozen_string_literal: true

# VerifyTokenDepositJob verifies incoming token deposits on Solana
#
# This job:
# 1. Fetches transaction from Solana
# 2. Verifies it's a valid token transfer to treasury
# 3. Credits user's internal balance
class VerifyTokenDepositJob < ApplicationJob
  queue_as :blockchain
  
  retry_on SolanaTokenService::SolanaError, wait: :polynomially_longer, attempts: 5

  def perform(deposit_id)
    deposit = TokenDeposit.find(deposit_id)
    
    Rails.logger.info "[DEPOSIT] Verifying deposit ##{deposit_id}"

    # Skip if already completed or failed
    if deposit.status.in?(%w[completed failed])
      Rails.logger.info "[DEPOSIT] Deposit ##{deposit_id} already #{deposit.status}, skipping"
      return
    end

    begin
      # Verify the transaction on Solana
      result = SolanaTokenService.verify_deposit(
        transaction_signature: deposit.transaction_signature,
        expected_amount: deposit.amount,
        expected_from: deposit.wallet_address
      )

      # Update deposit with verification details
      deposit.update!(
        blockhash: result[:blockhash],
        slot: result[:slot]
      )
      
      deposit.verify!

      # Credit internal balance
      stake = deposit.complete!

      Rails.logger.info "[DEPOSIT] Deposit ##{deposit_id} completed. " \
                        "Created stake ##{stake.id} for #{deposit.amount} tokens"

      # Notify user
      notify_user_deposit_completed(deposit)

    rescue SolanaTokenService::VerificationFailedError => e
      deposit.fail!("Verification failed: #{e.message}")
      Rails.logger.warn "[DEPOSIT] Deposit ##{deposit_id} verification failed: #{e.message}"
      
      # Don't retry verification failures - they're usually permanent
      # (wrong tx, wrong amount, etc.)

    rescue SolanaTokenService::SolanaError => e
      Rails.logger.error "[DEPOSIT] Deposit ##{deposit_id} Solana error: #{e.message}"
      raise # Re-raise to trigger retry

    rescue => e
      deposit.fail!("Unexpected error: #{e.message}")
      Rails.logger.error "[DEPOSIT] Deposit ##{deposit_id} unexpected error: #{e.message}"
      raise
    end
  end

  private

  def notify_user_deposit_completed(deposit)
    Rails.logger.info "[DEPOSIT] Would notify user #{deposit.user_id} of completed deposit"
  end
end
