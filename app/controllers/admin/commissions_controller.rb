class Admin::CommissionsController < Admin::BaseController
  before_action :set_commission, only: [:approve, :cancel]

  def index
    @commissions = Commission.includes(:affiliate, :referral, :entity)
                            .filter_by_status(params[:status])
                            .filter_by_date_range(params[:date_from], params[:date_to])
                            .filter_by_affiliate(params[:affiliate_id])
                            .recent
                            .page(params[:page])
                            .per(25)

    @total_pending = Commission.pending.sum(:amount)
    @total_approved = Commission.approved.sum(:amount)
    @total_paid = Commission.paid.sum(:amount)

    respond_to do |format|
      format.html
      format.csv { send_data generate_csv, filename: "commissions-#{Date.today}.csv" }
    end
  end

  def approve
    @commission.approve!(current_admin)
    redirect_to admin_commissions_path, notice: "Commission approved."
  end

  def bulk_approve
    commission_ids = params[:commission_ids] || []

    if commission_ids.empty?
      redirect_to admin_commissions_path, alert: "No commissions selected."
      return
    end

    count = Commission.where(id: commission_ids, status: :pending).update_all(
      status: Commission.statuses[:approved],
      approved_at: Time.current,
      approved_by_id: current_admin.id
    )

    redirect_to admin_commissions_path, notice: "#{count} commission(s) approved."
  end

  def cancel
    @commission.cancel!
    redirect_to admin_commissions_path, notice: "Commission cancelled."
  end

  private

  def set_commission
    @commission = Commission.find(params[:id])
  end

  def generate_csv
    require 'csv'

    CSV.generate(headers: true) do |csv|
      csv << ['ID', 'Affiliate', 'Email', 'Customer', 'Type', 'Amount', 'Status', 'Earned At', 'Approved At']

      Commission.includes(affiliate: :user, entity: :users).find_each do |commission|
        csv << [
          commission.id,
          commission.affiliate.user.full_name,
          commission.affiliate.user.email,
          commission.entity.name,
          commission.commission_type,
          commission.amount,
          commission.status,
          commission.earned_at&.strftime('%Y-%m-%d %H:%M'),
          commission.approved_at&.strftime('%Y-%m-%d %H:%M')
        ]
      end
    end
  end
end
