# frozen_string_literal: true

class BillingController < ApplicationController
  layout 'customer_admin'
  
  before_action :authenticate_user!
  before_action :set_billing_account
  before_action :set_config

  def index
    @timeframe = params[:timeframe] || "30d"
    @timeframe_start = case @timeframe
    when "today" then 24.hours.ago
    when "7d" then 7.days.ago
    when "30d" then 30.days.ago
    else 30.days.ago
    end
    
    # Usage summary
    @usage_summary = @work_token_service.usage_summary(days: 30)
    @recent_transactions = @work_token_service.recent_transactions(limit: 10)
    
    # Purchase history
    @purchases = @billing_account.work_token_purchases.completed.recent.limit(5)
    
    # Daily usage for chart
    @daily_usage = WorkTokenUsageSummary
      .where(user_billing_account: @billing_account)
      .last_30_days
      .daily_totals
    
    # Calculate billing stats
    @stats = {
      balance: @billing_account.work_token_balance,
      usage_this_month: @billing_account.usage_this_month,
      spending_this_month: @billing_account.spending_this_month_usd,
      monthly_limit: @billing_account.monthly_limit_usd,
      lifetime_purchased: @billing_account.lifetime_tokens_purchased,
      lifetime_used: @billing_account.lifetime_tokens_used,
      free_remaining: @billing_account.free_tokens_remaining
    }
    
    # Observability stats (merged from entity/observability)
    @ai_stats = {
      conversations: current_user.scout_conversations.where(created_at: @timeframe_start..).count,
      messages: current_user.scout_messages.where(created_at: @timeframe_start..).count,
      workflows_started: current_user.task_sessions.where(created_at: @timeframe_start..).count,
      workflows_completed: current_user.task_sessions.where(status: "completed", created_at: @timeframe_start..).count,
      workflows_failed: current_user.task_sessions.where(status: "failed", created_at: @timeframe_start..).count,
      estimated_tokens: current_user.scout_messages.where(created_at: @timeframe_start..).count * 500,
      estimated_cost: (current_user.scout_messages.where(created_at: @timeframe_start..).count * 500 * 0.00002).round(2)
    }

    # Integration Usage
    @integration_stats = {
      active_connections: current_user.connections.where(status: "connected").count,
      api_calls: IntegrationLog.joins(connection: :entity)
                               .where(connections: { entity_id: current_user.entity_id })
                               .where(created_at: @timeframe_start..).count,
      failed_calls: IntegrationLog.joins(connection: :entity)
                                  .where(connections: { entity_id: current_user.entity_id })
                                  .where("response_status >= 400")
                                  .where(created_at: @timeframe_start..).count
    }

    # Campaign Stats
    @campaign_stats = {
      total: current_user.campaigns.where(entity: current_user.entity, created_at: @timeframe_start..).count,
      sent: current_user.campaigns.where(entity: current_user.entity, status: "sent", created_at: @timeframe_start..).count,
      draft: current_user.campaigns.where(entity: current_user.entity, status: "draft", created_at: @timeframe_start..).count
    }
  end

  def settings
    # Payment method details
    @payment_method = @billing_account.payment_method_details
  end

  def update_settings
    if @billing_account.update(billing_settings_params)
      redirect_to settings_billing_path, notice: 'Billing settings updated successfully.'
    else
      @payment_method = @billing_account.payment_method_details
      render :settings, status: :unprocessable_entity
    end
  end

  def purchase
    # Show purchase options
    @tiers = @config.purchase_tiers
  end

  def create_purchase
    amount = params[:amount].to_i
    
    if amount <= 0
      redirect_to purchase_billing_path, alert: 'Please select a valid amount.'
      return
    end
    
    # Check monthly limit
    unless @billing_account.within_monthly_limit?
      redirect_to purchase_billing_path, alert: "This purchase would exceed your monthly limit of $#{@billing_account.monthly_limit_usd}."
      return
    end
    
    begin
      purchase = @billing_account.purchase_tokens!(amount_usd: amount, trigger: 'manual')
      redirect_to billing_path, notice: "Successfully purchased #{number_with_delimiter(purchase.total_tokens)} AMOS Work Tokens!"
    rescue UserBillingAccount::PaymentFailedError => e
      redirect_to purchase_billing_path, alert: "Payment failed: #{e.message}"
    end
  end

  # Stripe setup for adding payment method
  def setup_payment
    @billing_account.ensure_stripe_customer!
    
    # Check if this is onboarding (no payment method yet)
    @is_onboarding = !@billing_account.has_payment_method?
    
    # Create a SetupIntent for collecting payment method
    @setup_intent = Stripe::SetupIntent.create(
      customer: @billing_account.stripe_customer_id,
      payment_method_types: ['card'],
      metadata: {
        user_id: current_user.id,
        billing_account_id: @billing_account.id
      }
    )
    
    @publishable_key = ENV['STRIPE_PUBLISHABLE_KEY']
  end

  def confirm_payment_method
    payment_method_id = params[:payment_method_id]
    
    begin
      # Attach the payment method
      @billing_account.attach_payment_method!(payment_method_id)
      
      # Update billing settings if provided
      if params[:auto_replenish_enabled].present?
        @billing_account.update(
          auto_replenish_enabled: params[:auto_replenish_enabled],
          auto_replenish_amount_usd: params[:auto_replenish_amount_usd] || 20,
          monthly_limit_usd: params[:monthly_limit_usd] || 100
        )
      end
      
      # Respond based on request type
      if request.format.json? || request.content_type&.include?('json')
        render json: { success: true, message: 'Payment method added successfully.' }
      else
        redirect_to settings_billing_path, notice: 'Payment method added successfully.'
      end
    rescue Stripe::StripeError => e
      if request.format.json? || request.content_type&.include?('json')
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      else
        redirect_to setup_payment_billing_path, alert: "Failed to add payment method: #{e.message}"
      end
    end
  end

  def remove_payment_method
    @billing_account.remove_payment_method!
    redirect_to settings_billing_path, notice: 'Payment method removed.'
  end

  # Transaction history
  def transactions
    @transactions = @billing_account.work_token_transactions
      .recent
      .page(params[:page])
      .per(50)
    
    # Apply filters
    @transactions = @transactions.where(transaction_type: params[:type]) if params[:type].present?
    @transactions = @transactions.for_category(params[:category]) if params[:category].present?
  end

  # Usage breakdown
  def usage
    @start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    @end_date = params[:end_date]&.to_date || Date.current
    
    summaries = WorkTokenUsageSummary
      .where(user_billing_account: @billing_account)
      .for_date_range(@start_date, @end_date)
    
    @total_tokens = summaries.total_tokens
    @by_category = summaries.by_category
    @daily_totals = summaries.daily_totals
    
    # Get detailed breakdown for AI usage
    @ai_breakdown = WorkTokenUsageSummary
      .where(user_billing_account: @billing_account, category: 'ai_tokens')
      .for_date_range(@start_date, @end_date)
      .pluck(:breakdown)
      .compact
      .reduce({}) { |acc, b| acc.merge(b) { |_, v1, v2| v1 + v2 } }
  end

  private

  def set_billing_account
    @billing_account = UserBillingAccount.for_user(current_user)
    @work_token_service = WorkTokenService.new(user: current_user, entity: current_user.entity)
  end

  def set_config
    @config = BillingConfiguration.current
  end

  def billing_settings_params
    params.require(:user_billing_account).permit(
      :auto_replenish_enabled,
      :auto_replenish_amount_usd,
      :auto_replenish_threshold,
      :monthly_limit_usd
    )
  end
end

