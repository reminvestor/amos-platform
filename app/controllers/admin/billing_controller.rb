# frozen_string_literal: true

module Admin
  class BillingController < Admin::BaseController
    before_action :set_billing_configuration, only: [:edit, :update]

    def index
      @config = BillingConfiguration.current
      
      # User billing statistics
      @total_user_accounts = UserBillingAccount.count
      @active_user_accounts = UserBillingAccount.active.count
      @user_accounts_with_payment = UserBillingAccount.where(has_payment_method: true).count
      
      # Entity billing statistics
      @total_entity_accounts = EntityBillingAccount.count
      @active_entity_accounts = EntityBillingAccount.where(status: 'active').count
      @entity_accounts_with_payment = EntityBillingAccount.where(has_payment_method: true).count
      
      # Token statistics
      @total_tokens_sold = WorkTokenPurchase.completed.sum(:tokens_purchased)
      @total_bonus_tokens = WorkTokenPurchase.completed.sum(:bonus_tokens)
      @total_revenue_cents = WorkTokenPurchase.completed.sum(:amount_usd_cents)
      
      # Usage statistics (last 30 days)
      @usage_last_30_days = WorkTokenUsageSummary.last_30_days
      @total_tokens_used_30d = @usage_last_30_days.total_tokens
      @usage_by_category = @usage_last_30_days.by_category
      
      # Recent purchases
      @recent_purchases = WorkTokenPurchase.completed.recent.includes(:user).limit(20)
      
      # Low balance user accounts
      @low_balance_accounts = UserBillingAccount.active.low_balance.includes(:user).limit(20)
      
      # Low balance entity accounts
      @low_balance_entity_accounts = EntityBillingAccount.where(status: 'active').low_balance.includes(:entity).limit(20)
    end

    def edit
      # @config is set by before_action
    end

    def update
      if @config.update(billing_configuration_params)
        redirect_to admin_billing_index_path, notice: 'Billing configuration updated successfully.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # View all user billing accounts
    def accounts
      @accounts = UserBillingAccount
        .includes(:user)
        .order(created_at: :desc)
        .page(params[:page])
        .per(50)
      
      # Apply filters
      @accounts = @accounts.where(status: params[:status]) if params[:status].present?
      @accounts = @accounts.where(has_payment_method: true) if params[:has_payment] == 'true'
      @accounts = @accounts.low_balance if params[:low_balance] == 'true'
    end

    # View specific account details
    def account_detail
      @account = UserBillingAccount.includes(:user, :work_token_transactions, :work_token_purchases).find(params[:id])
      @recent_transactions = @account.work_token_transactions.recent.limit(50)
      @purchases = @account.work_token_purchases.recent.limit(20)
      @usage_summary = WorkTokenUsageSummary
        .where(user_billing_account: @account)
        .last_30_days
        .by_category
    end

    # Admin action to credit tokens
    def credit_tokens
      @account = UserBillingAccount.find(params[:id])
      amount = params[:amount].to_i
      reason = params[:reason] || "Admin credit"
      
      if amount <= 0
        redirect_to admin_billing_account_detail_path(@account), alert: 'Amount must be positive.'
        return
      end
      
      @account.credit_tokens!(
        amount: amount,
        transaction_type: 'adjustment',
        category: 'admin_adjustment',
        description: "Admin credit: #{reason}",
        metadata: { admin_id: current_admin_user.id, reason: reason }
      )
      
      redirect_to admin_billing_account_detail_path(@account), notice: "Credited #{number_with_delimiter(amount)} tokens to account."
    end

    # Admin action to suspend account
    def suspend_account
      @account = UserBillingAccount.find(params[:id])
      reason = params[:reason] || "Admin action"
      
      @account.suspend!(reason: reason)
      
      redirect_to admin_billing_account_detail_path(@account), notice: 'Account suspended.'
    end

    # Admin action to reactivate account
    def reactivate_account
      @account = UserBillingAccount.find(params[:id])
      
      @account.reactivate!
      
      redirect_to admin_billing_account_detail_path(@account), notice: 'Account reactivated.'
    end

    # View all transactions
    def transactions
      @transactions = WorkTokenTransaction
        .includes(:user, :user_billing_account)
        .recent
        .page(params[:page])
        .per(100)
      
      # Apply filters
      @transactions = @transactions.where(transaction_type: params[:type]) if params[:type].present?
      @transactions = @transactions.for_category(params[:category]) if params[:category].present?
      @transactions = @transactions.in_date_range(params[:start_date], params[:end_date]) if params[:start_date].present? && params[:end_date].present?
    end

    # ========================================
    # Entity Billing Account Management
    # ========================================

    # View all entity billing accounts
    def entity_accounts
      @accounts = EntityBillingAccount
        .includes(:entity)
        .order(created_at: :desc)
        .page(params[:page])
        .per(50)

      # Apply filters
      @accounts = @accounts.where(status: params[:status]) if params[:status].present?
      @accounts = @accounts.where(has_payment_method: true) if params[:has_payment] == 'true'
      @accounts = @accounts.low_balance if params[:low_balance] == 'true'
    end

    # View specific entity account details
    def entity_account_detail
      @account = EntityBillingAccount.includes(:entity).find(params[:id])
      @entity = @account.entity
      @recent_transactions = WorkTokenTransaction
        .where(entity_billing_account: @account)
        .order(created_at: :desc)
        .limit(50)
      @team_members = @entity.entity_users.includes(:user)
    end

    # Admin action to credit tokens to entity
    def credit_entity_tokens
      @account = EntityBillingAccount.find(params[:id])
      amount = params[:amount].to_i
      reason = params[:reason] || "Admin credit"

      if amount <= 0
        redirect_to admin_billing_entity_account_detail_path(@account), alert: 'Amount must be positive.'
        return
      end

      @account.credit_tokens!(
        amount: amount,
        transaction_type: 'adjustment',
        category: 'admin_adjustment',
        description: "Admin credit: #{reason}",
        user: nil,
        metadata: { admin_id: current_admin_user.id, reason: reason }
      )

      redirect_to admin_billing_entity_account_detail_path(@account), 
        notice: "Credited #{number_with_delimiter(amount)} tokens to #{@account.entity.name}."
    end

    # Admin action to suspend entity account
    def suspend_entity_account
      @account = EntityBillingAccount.find(params[:id])
      reason = params[:reason] || "Admin action"

      @account.update!(status: 'suspended')
      
      Rails.logger.info "🚫 Admin suspended entity billing account #{@account.id}: #{reason}"

      redirect_to admin_billing_entity_account_detail_path(@account), notice: 'Entity account suspended.'
    end

    # Admin action to reactivate entity account
    def reactivate_entity_account
      @account = EntityBillingAccount.find(params[:id])

      @account.update!(status: 'active')
      
      Rails.logger.info "✅ Admin reactivated entity billing account #{@account.id}"

      redirect_to admin_billing_entity_account_detail_path(@account), notice: 'Entity account reactivated.'
    end

    # Revenue report
    def revenue_report
      @start_date = params[:start_date]&.to_date || 30.days.ago.to_date
      @end_date = params[:end_date]&.to_date || Date.current
      
      purchases = WorkTokenPurchase.completed.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
      
      @total_revenue = purchases.sum(:amount_usd_cents) / 100.0
      @total_tokens_sold = purchases.sum(:tokens_purchased)
      @total_bonus_tokens = purchases.sum(:bonus_tokens)
      @purchase_count = purchases.count
      @auto_replenish_count = purchases.auto_replenish.count
      @manual_count = purchases.manual.count
      
      # Daily breakdown
      @daily_revenue = purchases
        .group('DATE(created_at)')
        .sum(:amount_usd_cents)
        .transform_values { |v| v / 100.0 }
      
      # By tier
      @revenue_by_tier = purchases
        .group(:purchase_tier)
        .sum(:amount_usd_cents)
        .transform_values { |v| v / 100.0 }
    end

    # Usage report
    def usage_report
      @start_date = params[:start_date]&.to_date || 30.days.ago.to_date
      @end_date = params[:end_date]&.to_date || Date.current
      
      summaries = WorkTokenUsageSummary.for_date_range(@start_date, @end_date)
      
      @total_tokens_used = summaries.total_tokens
      @total_cost = summaries.total_cost_usd
      @by_category = summaries.by_category
      @daily_totals = summaries.daily_totals
      
      # Top users by usage
      @top_users = summaries
        .group(:user_id)
        .sum(:tokens_used)
        .sort_by { |_, v| -v }
        .first(20)
        .map { |user_id, tokens| [User.find(user_id), tokens] }
    end

    private

    def set_billing_configuration
      @config = BillingConfiguration.current
    end

    def billing_configuration_params
      params.require(:billing_configuration).permit(
        :uplift_percentage,
        :ai_tokens_rate,
        :email_rate,
        :storage_rate_mb,
        :api_call_rate,
        :other_compute_rate,
        :free_tokens_on_signup,
        :default_auto_replenish_amount_usd,
        :default_monthly_limit_usd
      )
    end
  end
end

