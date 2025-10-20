class Admin::AffiliatesController < Admin::BaseController
  before_action :set_affiliate, only: [:show, :approve, :suspend, :update_commission_rate]

  def index
    @affiliates = Affiliate.includes(:user)
                          .filter_by_status(params[:status])
                          .filter_by_tier(params[:tier])
                          .search(params[:query])
                          .order(created_at: :desc)
                          .page(params[:page])
                          .per(25)

    @total_affiliates = Affiliate.count
    @pending_count = Affiliate.pending.count
    @active_count = Affiliate.active.count

    respond_to do |format|
      format.html
      format.csv { send_data generate_csv, filename: "affiliates-#{Date.today}.csv" }
    end
  end

  def show
    @stats = AffiliateStatsService.new(@affiliate).detailed_stats
  end

  def approve
    @affiliate.update!(
      status: :active,
      approved_at: Time.current,
      approved_by: current_admin
    )

    # Send approval email to affiliate
    AffiliateMailer.application_approved(@affiliate).deliver_later

    redirect_to admin_affiliate_path(@affiliate), notice: "Affiliate approved successfully!"
  end

  def suspend
    @affiliate.update!(status: :suspended)
    redirect_to admin_affiliate_path(@affiliate), notice: "Affiliate suspended."
  end

  def update_commission_rate
    new_rate = params[:commission_rate].to_f

    if new_rate >= 0 && new_rate <= 1
      @affiliate.update!(commission_rate: new_rate)
      redirect_to admin_affiliate_path(@affiliate), notice: "Commission rate updated to #{(new_rate * 100).round(2)}%"
    else
      redirect_to admin_affiliate_path(@affiliate), alert: "Invalid commission rate. Must be between 0 and 1."
    end
  end

  def analytics
    @time_range = params[:time_range]&.to_i&.days || 30.days

    # Overall affiliate program stats
    @total_affiliates = Affiliate.count
    @active_affiliates = Affiliate.active.count
    @pending_affiliates = Affiliate.pending.count
    @suspended_affiliates = Affiliate.suspended.count

    # Commission stats
    @total_commissions = Commission.sum(:amount)
    @pending_commissions = Commission.pending.sum(:amount)
    @paid_commissions = Commission.paid.sum(:amount)
    @commissions_this_month = Commission.where("created_at > ?", 30.days.ago).sum(:amount)

    # Referral stats
    @total_clicks = Affiliate.sum(:total_clicks)
    @total_referrals = Affiliate.sum(:total_referrals)
    @total_conversions = Affiliate.sum(:total_conversions)
    @conversion_rate = @total_clicks > 0 ? ((@total_conversions.to_f / @total_clicks) * 100).round(2) : 0

    # Top performing affiliates
    @top_affiliates_by_revenue = Affiliate.joins(:commissions)
                                          .group("affiliates.id", "users.first_name", "users.last_name")
                                          .joins(:user)
                                          .select("affiliates.*, users.first_name, users.last_name, SUM(commissions.amount) as total_revenue")
                                          .order("total_revenue DESC")
                                          .limit(10)

    @top_affiliates_by_referrals = Affiliate.includes(:user)
                                            .order(total_referrals: :desc)
                                            .limit(10)

    # Revenue over time chart
    @revenue_chart = generate_revenue_chart

    # Referrals over time chart
    @referrals_chart = generate_referrals_chart

    respond_to do |format|
      format.html
      format.json do
        render json: {
          total_affiliates: @total_affiliates,
          active_affiliates: @active_affiliates,
          total_commissions: @total_commissions,
          paid_commissions: @paid_commissions,
          conversion_rate: @conversion_rate
        }
      end
    end
  end

  def settings
    @affiliate_settings = AffiliateSettings.first_or_initialize
  end

  def update_settings
    @affiliate_settings = AffiliateSettings.first_or_initialize

    if @affiliate_settings.update(affiliate_settings_params)
      redirect_to admin_settings_affiliate_path, notice: "Affiliate settings updated successfully!"
    else
      render :settings, alert: "Failed to update settings."
    end
  end

  private

  def set_affiliate
    @affiliate = Affiliate.find(params[:id])
  end

  def generate_csv
    require 'csv'

    CSV.generate(headers: true) do |csv|
      csv << ['ID', 'Name', 'Email', 'Code', 'Status', 'Tier', 'Commission Rate', 'Clicks', 'Referrals', 'Conversions', 'Total Earned', 'Created At']

      Affiliate.includes(:user).find_each do |affiliate|
        csv << [
          affiliate.id,
          affiliate.user.full_name,
          affiliate.user.email,
          affiliate.affiliate_code,
          affiliate.status,
          affiliate.tier,
          affiliate.commission_rate,
          affiliate.total_clicks,
          affiliate.total_referrals,
          affiliate.total_conversions,
          affiliate.total_earned,
          affiliate.created_at.strftime('%Y-%m-%d')
        ]
      end
    end
  end

  def affiliate_settings_params
    params.require(:affiliate_settings).permit(
      :default_commission_rate,
      :min_payout_threshold,
      :auto_approve_affiliates,
      :cookie_duration_days,
      :allow_self_referrals
    )
  end

  def generate_revenue_chart
    days = (@time_range.to_i / 1.day.to_i).times.map { |d| d.days.ago.beginning_of_day }

    data_by_day = Commission.where("created_at > ?", @time_range.ago)
                            .group_by { |c| c.created_at.beginning_of_day }

    {
      labels: days.reverse.map { |d| d.strftime("%b %-d") },
      datasets: [
        {
          label: "Revenue ($)",
          data: days.reverse.map do |day|
            commissions = data_by_day[day] || []
            commissions.sum(&:amount).round(2)
          end,
          borderColor: "rgb(16, 185, 129)",
          backgroundColor: "rgba(16, 185, 129, 0.1)",
          fill: true
        }
      ]
    }
  end

  def generate_referrals_chart
    days = (@time_range.to_i / 1.day.to_i).times.map { |d| d.days.ago.beginning_of_day }

    # This would ideally come from a referrals table with timestamps
    # For now, using a simplified version
    {
      labels: days.reverse.map { |d| d.strftime("%b %-d") },
      datasets: [
        {
          label: "Referrals",
          data: days.reverse.map { |_day| rand(5..50) }, # Placeholder data
          borderColor: "rgb(59, 130, 246)",
          backgroundColor: "rgba(59, 130, 246, 0.1)",
          fill: true
        }
      ]
    }
  end
end
