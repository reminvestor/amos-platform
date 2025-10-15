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
end
