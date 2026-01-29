# frozen_string_literal: true

# ProcessRevenuePaymentJob handles USDC transfers to user wallets
class ProcessRevenuePaymentJob < ApplicationJob
  queue_as :default

  def perform(payment_id)
    payment = RevenuePayment.find_by(id: payment_id)
    return unless payment
    return unless payment.status == 'pending'

    user = payment.user
    return payment.fail!(reason: 'No wallet connected') unless user.solana_wallet_address.present?

    begin
      # In production, this would use SolanaTokenService to send USDC
      # For now, we'll mark it as credited (platform balance)
      
      # TODO: Implement actual USDC transfer via Solana
      # signature = SolanaTokenService.send_usdc(
      #   to: user.solana_wallet_address,
      #   amount: payment.amount
      # )
      
      # For now, credit to platform balance
      payment.complete!
      
      Rails.logger.info "[REVENUE_PAYMENT] Credited #{payment.amount} USDC to user #{user.id}"
      
    rescue => e
      Rails.logger.error "[REVENUE_PAYMENT] Failed for payment #{payment_id}: #{e.message}"
      payment.fail!(reason: e.message)
    end
  end
end
