class Admin::PayoutsController < Admin::BaseController
  before_action :set_payout, only: [:mark_completed]

  def index
    @payouts = Payout.includes(:affiliate)
                    .filter_by_status(params[:status])
                    .recent
                    .page(params[:page])
                    .per(25)

    @pending_commissions_total = Commission.approved.sum(:amount)
    @ready_for_payout_count = Affiliate.with_approved_commissions_above_threshold(50).count

    respond_to do |format|
      format.html
      format.csv { send_data generate_csv, filename: "payouts-#{Date.today}.csv" }
    end
  end

  def new
    @minimum_threshold = params[:threshold]&.to_f || 50.0
    @affiliates_ready = Affiliate.with_approved_commissions_above_threshold(@minimum_threshold)
                                 .includes(:user, :commissions)

    @affiliates_data = @affiliates_ready.map do |affiliate|
      {
        affiliate: affiliate,
        amount: affiliate.commissions.approved.sum(:amount),
        commission_count: affiliate.commissions.approved.count
      }
    end
  end

  def create
    affiliate_ids = params[:affiliate_ids] || []

    if affiliate_ids.empty?
      redirect_to new_admin_payout_path, alert: "No affiliates selected."
      return
    end

    result = PayoutBatchService.create_batch(
      affiliate_ids: affiliate_ids,
      payment_method: params[:payment_method] || 'manual',
      admin_user: current_admin,
      minimum_threshold: params[:minimum_threshold]&.to_f || 50.0
    )

    if result.success?
      redirect_to admin_payouts_path, notice: "#{result.payouts.count} payout(s) created successfully."
    else
      redirect_to new_admin_payout_path, alert: "Error creating payouts: #{result.error}"
    end
  end

  def mark_completed
    payment_reference = params[:payment_reference]

    @payout.mark_completed!(current_admin, payment_reference)

    # Send payout confirmation email
    AffiliateMailer.payout_processed(@payout).deliver_later

    redirect_to admin_payouts_path, notice: "Payout marked as completed."
  end

  private

  def set_payout
    @payout = Payout.find(params[:id])
  end

  def generate_csv
    require 'csv'

    CSV.generate(headers: true) do |csv|
      csv << ['ID', 'Affiliate', 'Email', 'Amount', 'Currency', 'Method', 'Status', 'Reference', 'Date', 'Processed By']

      Payout.includes(affiliate: :user, processed_by: []).find_each do |payout|
        csv << [
          payout.id,
          payout.affiliate.user.full_name,
          payout.affiliate.user.email,
          payout.amount,
          payout.currency,
          payout.payment_method,
          payout.status,
          payout.payment_reference,
          payout.payout_date&.strftime('%Y-%m-%d'),
          payout.processed_by&.full_name
        ]
      end
    end
  end
end
