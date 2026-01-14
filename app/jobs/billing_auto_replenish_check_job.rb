# frozen_string_literal: true

# Recurring job to check for accounts that need auto-replenishment
# This catches cases where:
# 1. Payment method was added via webhook but replenishment wasn't triggered
# 2. Balance went negative through some path that didn't check replenishment
# 3. Previous replenishment attempts failed and need retry
class BillingAutoReplenishCheckJob < ApplicationJob
  queue_as :billing

  def perform
    Rails.logger.info "💰 [Billing] Checking for accounts needing auto-replenishment..."

    # Check user billing accounts
    user_accounts_processed = process_user_accounts

    # Check entity billing accounts
    entity_accounts_processed = process_entity_accounts

    Rails.logger.info "💰 [Billing] Auto-replenish check complete. " \
                      "User accounts: #{user_accounts_processed}, Entity accounts: #{entity_accounts_processed}"
  end

  private

  def process_user_accounts
    accounts = UserBillingAccount.needs_replenishment

    accounts.find_each do |account|
      process_account(account, :user)
    end

    accounts.count
  rescue => e
    Rails.logger.error "💰 [Billing] Error processing user accounts: #{e.message}"
    0
  end

  def process_entity_accounts
    accounts = EntityBillingAccount.needs_replenishment

    accounts.find_each do |account|
      process_account(account, :entity)
    end

    accounts.count
  rescue => e
    Rails.logger.error "💰 [Billing] Error processing entity accounts: #{e.message}"
    0
  end

  def process_account(account, type)
    # Skip if already has a pending replenishment job or in cooldown
    if recently_attempted_replenishment?(account)
      recent_failure = account.work_token_purchases
                              .where(trigger: 'auto_replenish', status: 'failed')
                              .order(created_at: :desc)
                              .first
      
      if recent_failure
        Rails.logger.info "💰 [Billing] Skipping #{type} account #{account.id} - in cooldown after failure: #{recent_failure.failure_reason}"
      end
      return
    end

    # Log diagnostics
    Rails.logger.info "💰 [Billing] Queueing auto-replenishment for #{type} account #{account.id} " \
                      "(balance: #{account.work_token_balance}, threshold: #{account.auto_replenish_threshold}, " \
                      "stripe_customer: #{account.stripe_customer_id.present?}, payment_method: #{account.stripe_default_payment_method_id.present?})"

    if type == :user
      AutoReplenishTokensJob.perform_later(account.id)
    else
      AutoReplenishEntityTokensJob.perform_later(account.id)
    end
  rescue => e
    Rails.logger.error "💰 [Billing] Error queueing replenishment for #{type} account #{account.id}: #{e.message}"
  end

  def recently_attempted_replenishment?(account)
    last_purchase = account.work_token_purchases
                           .where(trigger: 'auto_replenish')
                           .order(created_at: :desc)
                           .first

    return false if last_purchase.nil?

    case last_purchase.status
    when 'pending'
      # Don't retry while a payment is still processing
      true
    when 'completed'
      # Avoid duplicate successful charges within 10 minutes
      last_purchase.created_at > 10.minutes.ago
    when 'failed'
      # For failed attempts, use exponential backoff based on failure count
      # Wait longer each time: 1 hour, 4 hours, 12 hours, 24 hours
      recent_failures = account.work_token_purchases
                               .where(trigger: 'auto_replenish', status: 'failed')
                               .where('created_at > ?', 24.hours.ago)
                               .count
      
      cooldown = case recent_failures
                 when 0..1 then 1.hour
                 when 2..3 then 4.hours
                 when 4..5 then 12.hours
                 else 24.hours
                 end
      
      last_purchase.created_at > cooldown.ago
    else
      false
    end
  end
end
