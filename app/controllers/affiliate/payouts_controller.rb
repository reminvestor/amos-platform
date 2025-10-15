class Affiliate::PayoutsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_affiliate
  skip_before_action :check_subscription_status
  skip_before_action :check_onboarding_status

  def index
    @affiliate = current_user.affiliate
    @payouts = @affiliate.payouts.order(created_at: :desc).page(params[:page]).per(20)

    # Filter by status if provided
    if params[:status].present?
      @payouts = @payouts.where(status: params[:status])
    end

    # Calculate summary stats
    @total_paid = @affiliate.payouts.completed.sum(:amount)
    @total_pending = @affiliate.payouts.where(status: [:pending, :processing]).sum(:amount)
  end

  private

  def ensure_affiliate
    unless current_user.affiliate&.active?
      redirect_to affiliate_apply_path, alert: "You must be an approved affiliate to view payouts."
    end
  end
end
