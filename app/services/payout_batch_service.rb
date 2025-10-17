class PayoutBatchService
  Result = Struct.new(:success?, :payouts, :error, keyword_init: true)

  def self.create_batch(affiliate_ids:, payment_method:, admin_user:, minimum_threshold: 50)
    new(affiliate_ids, payment_method, admin_user, minimum_threshold).create_batch
  end

  def initialize(affiliate_ids, payment_method, admin_user, minimum_threshold)
    @affiliate_ids = affiliate_ids
    @payment_method = payment_method
    @admin_user = admin_user
    @minimum_threshold = minimum_threshold
  end

  def create_batch
    payouts = []
    errors = []

    Affiliate.where(id: @affiliate_ids).find_each do |affiliate|
      result = create_payout_for_affiliate(affiliate)

      if result[:success]
        payouts << result[:payout] if result[:payout]
      else
        errors << result[:error]
      end
    end

    if errors.any?
      Result.new(success?: false, payouts: payouts, error: errors.join('; '))
    else
      Result.new(success?: true, payouts: payouts, error: nil)
    end
  rescue => e
    Result.new(success?: false, payouts: [], error: e.message)
  end

  private

  def create_payout_for_affiliate(affiliate)
    commissions = affiliate.commissions.approved
    total_amount = commissions.sum(:amount)

    if total_amount < @minimum_threshold
      return { success: true, payout: nil, error: nil } # Skip, but not an error
    end

    payout = Payout.create!(
      affiliate: affiliate,
      amount: total_amount,
      currency: 'USD',
      payment_method: @payment_method,
      status: :pending,
      payout_date: Date.today,
      commission_ids: commissions.pluck(:id),
      processed_by: @admin_user
    )

    { success: true, payout: payout, error: nil }
  rescue => e
    { success: false, payout: nil, error: "#{affiliate.user.email}: #{e.message}" }
  end
end
