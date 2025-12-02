# frozen_string_literal: true

# Channel for user-specific notifications including billing alerts
class UserNotificationsChannel < ApplicationCable::Channel
  def subscribed
    # Stream from user-specific channel
    stream_from "user_notifications_#{current_user.id}"
    
    Rails.logger.info "📡 User #{current_user.id} subscribed to notifications"
    
    # Send any pending billing notifications on connect
    check_pending_billing_notifications
  end

  def unsubscribed
    Rails.logger.info "📡 User #{current_user.id} unsubscribed from notifications"
  end

  private

  def check_pending_billing_notifications
    return unless current_user
    
    billing_account = UserBillingAccount.find_by(user: current_user)
    return unless billing_account
    return if billing_account.has_payment_method?
    
    # Check current usage percentage and send appropriate notification
    usage_pct = billing_account.usage_percentage
    
    if usage_pct >= 100
      transmit_threshold_notification(100, billing_account)
    elsif usage_pct >= 90
      transmit_threshold_notification(90, billing_account)
    elsif usage_pct >= 75
      transmit_threshold_notification(75, billing_account)
    elsif usage_pct >= 50
      transmit_threshold_notification(50, billing_account)
    elsif usage_pct >= 25
      transmit_threshold_notification(25, billing_account)
    end
  end

  def transmit_threshold_notification(threshold, billing_account)
    message = case threshold
    when 25
      {
        type: 'billing_reminder',
        level: 'info',
        title: "You've used 25% of your free tokens",
        message: "Add a payment method to ensure uninterrupted service when your free tokens run out.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method',
        dismissable: true
      }
    when 50
      {
        type: 'billing_reminder',
        level: 'warning',
        title: "50% of free tokens used",
        message: "You're halfway through your free tokens. Add a payment method now to avoid any interruption.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method',
        dismissable: true
      }
    when 75
      {
        type: 'billing_reminder',
        level: 'warning',
        title: "75% of free tokens used",
        message: "You're running low on free tokens! Add a payment method to continue using AMOS without interruption.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method',
        dismissable: true
      }
    when 90
      {
        type: 'billing_reminder',
        level: 'danger',
        title: "Almost out of tokens!",
        message: "You've used 90% of your free tokens. Add a payment method now to avoid losing access.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method Now',
        dismissable: false
      }
    when 100
      {
        type: 'billing_required',
        level: 'danger',
        title: "Out of tokens",
        message: "You've used all your free tokens. Please add a payment method to continue using AMOS.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method',
        dismissable: false,
        blocking: true
      }
    end
    
    return unless message
    
    transmit(message.merge(
      timestamp: Time.current.iso8601,
      usage_percentage: billing_account.usage_percentage,
      remaining_tokens: billing_account.work_token_balance
    ))
  end
end

