class Affiliate::ApplicationsController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_already_affiliate, only: [:new, :create]
  skip_before_action :check_subscription_status
  skip_before_action :check_onboarding_status

  def new
    @affiliate_application = Affiliate.new
  end

  def create
    @affiliate_application = current_user.build_affiliate(affiliate_params.merge(
      status: :pending,
      tier: :bronze,
      commission_rate: 0.20
    ))

    if @affiliate_application.save
      # Send confirmation to affiliate
      AffiliateMailer.application_received(@affiliate_application).deliver_later

      # Notify admins
      AdminMailer.new_affiliate_application(@affiliate_application).deliver_later

      redirect_to affiliate_dashboard_path, notice: "Application submitted! We'll review it within 2 business days."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def affiliate_params
    params.require(:affiliate).permit(:application_notes, :payment_email)
  end

  def redirect_if_already_affiliate
    if current_user.affiliate.present?
      redirect_to affiliate_dashboard_path, notice: "You already have an affiliate account."
    end
  end
end
