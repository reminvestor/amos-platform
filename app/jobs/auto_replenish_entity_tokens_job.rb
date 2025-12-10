# frozen_string_literal: true

class AutoReplenishEntityTokensJob < ApplicationJob
  queue_as :default

  def perform(entity_billing_account_id)
    account = EntityBillingAccount.find_by(id: entity_billing_account_id)
    return unless account
    return unless account.can_auto_replenish?

    Rails.logger.info "💳 Auto-replenishing entity tokens for entity #{account.entity_id}"

    begin
      account.purchase_tokens!(
        amount_usd: account.auto_replenish_amount_usd,
        trigger: 'auto_replenish'
      )
      Rails.logger.info "✅ Entity auto-replenishment successful: #{account.auto_replenish_amount_usd} USD"
    rescue => e
      Rails.logger.error "❌ Entity auto-replenishment failed: #{e.message}"
      
      # Notify entity owners/admins
      account.entity.entity_users.where(role: %w[owner admin]).find_each do |entity_user|
        ActionCable.server.broadcast(
          "user_notifications_#{entity_user.user_id}",
          {
            type: 'billing_error',
            level: 'danger',
            title: "Auto-replenishment failed",
            message: "Unable to automatically purchase tokens for your team. Please check your payment method.",
            action_url: '/billing/setup_payment',
            action_text: 'Update Payment',
            dismissable: true
          }
        )
      end
    end
  end
end
