# frozen_string_literal: true

# Job to auto-replenish work tokens when balance is low
class AutoReplenishTokensJob < ApplicationJob
  queue_as :billing
  
  # Retry with exponential backoff for payment failures
  retry_on Stripe::StripeError, wait: :polynomially_longer, attempts: 3
  
  def perform(billing_account_id)
    billing_account = UserBillingAccount.find(billing_account_id)
    
    # Double-check conditions
    return unless billing_account.can_auto_replenish?
    return unless billing_account.low_balance?
    
    Rails.logger.info "🔄 Auto-replenishing tokens for user #{billing_account.user_id}"
    
    begin
      purchase = billing_account.purchase_tokens!(
        amount_usd: billing_account.auto_replenish_amount_usd,
        trigger: 'auto_replenish'
      )
      
      Rails.logger.info "✅ Auto-replenishment successful: #{purchase.total_tokens} tokens for $#{purchase.amount_usd}"
      
      # Notify user of successful auto-replenishment
      notify_user_of_replenishment(billing_account, purchase)
      
    rescue UserBillingAccount::PaymentFailedError => e
      Rails.logger.error "❌ Auto-replenishment failed for user #{billing_account.user_id}: #{e.message}"
      
      # Notify user of failed payment
      notify_user_of_payment_failure(billing_account, e.message)
      
      raise # Re-raise for retry logic
    end
  end
  
  private
  
  def notify_user_of_replenishment(billing_account, purchase)
    # Create in-app notification
    UserNotification.create(
      user: billing_account.user,
      entity: billing_account.user.entities.first,
      title: "Work Tokens Replenished",
      message: "Your account was automatically topped up with #{purchase.total_tokens.to_s(:delimited)} AMOS Work Tokens for $#{purchase.amount_usd}.",
      notification_type: 'billing',
      channel: 'in_app',
      priority: 'low',
      action_url: '/billing',
      metadata: {
        purchase_id: purchase.id,
        amount_usd: purchase.amount_usd,
        tokens: purchase.total_tokens
      }
    )
  rescue => e
    Rails.logger.error "Failed to create replenishment notification: #{e.message}"
  end
  
  def notify_user_of_payment_failure(billing_account, error_message)
    UserNotification.create(
      user: billing_account.user,
      entity: billing_account.user.entities.first,
      title: "Payment Failed - Low Token Balance",
      message: "We couldn't automatically replenish your AMOS Work Tokens. Please update your payment method to continue using AI features.",
      notification_type: 'billing',
      channel: 'in_app',
      priority: 'high',
      action_url: '/billing/payment-method',
      metadata: {
        error: error_message
      }
    )
  rescue => e
    Rails.logger.error "Failed to create payment failure notification: #{e.message}"
  end
end

