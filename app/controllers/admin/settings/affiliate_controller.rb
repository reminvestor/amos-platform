class Admin::Settings::AffiliateController < Admin::BaseController
  def show
    @settings = load_settings
    @tiers = AffiliateTier.ordered
  end

  def update
    settings = load_settings
    settings.update!(settings_params)

    redirect_to admin_settings_affiliate_path, notice: "Settings updated successfully."
  rescue => e
    redirect_to admin_settings_affiliate_path, alert: "Error updating settings: #{e.message}"
  end

  private

  def load_settings
    # For now, we'll use a simple hash stored in a file or database
    # In a real app, you might use a Settings model or gem like rails-settings-cached
    OpenStruct.new(
      default_commission_rate: 0.20,
      cookie_duration_days: 60,
      minimum_payout_threshold: 50.0,
      auto_approve_applications: false,
      require_review_for_high_commissions: true,
      high_commission_threshold: 500.0
    )
  end

  def settings_params
    params.require(:settings).permit(
      :default_commission_rate,
      :cookie_duration_days,
      :minimum_payout_threshold,
      :auto_approve_applications,
      :require_review_for_high_commissions,
      :high_commission_threshold
    )
  end
end
