require "test_helper"

class PayoutBatchServiceTest < ActiveSupport::TestCase
  def setup
    @admin_user = AdminUser.find_or_create_by!(email: "admin_payout_batch_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'password123'
    end
    @affiliate1 = affiliates(:active_affiliate)
    @affiliate2 = affiliates(:silver_affiliate)

    # Create approved commissions for testing
    @commission1 = Commission.create!(
      affiliate: @affiliate1,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 60.00,
      status: :approved,
      earned_at: Time.current
    )

    @commission2 = Commission.create!(
      affiliate: @affiliate1,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'recurring',
      amount: 40.00,
      status: :approved,
      earned_at: Time.current
    )
  end

  # Successful batch creation
  test "create_batch creates payouts for affiliates with approved commissions" do
    affiliate_ids = [@affiliate1.id]

    assert_difference 'Payout.count', 1 do
      result = PayoutBatchService.create_batch(
        affiliate_ids: affiliate_ids,
        payment_method: 'paypal',
        admin_user: @admin_user
      )

      assert result.success?
      assert_equal 1, result.payouts.length
      assert_nil result.error
    end
  end

  test "create_batch calculates total amount from approved commissions" do
    affiliate_ids = [@affiliate1.id]

    result = PayoutBatchService.create_batch(
      affiliate_ids: affiliate_ids,
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    payout = result.payouts.first
    expected_amount = @commission1.amount + @commission2.amount

    assert_equal expected_amount, payout.amount
  end

  test "create_batch sets payment method correctly" do
    affiliate_ids = [@affiliate1.id]

    result = PayoutBatchService.create_batch(
      affiliate_ids: affiliate_ids,
      payment_method: 'stripe',
      admin_user: @admin_user
    )

    payout = result.payouts.first
    assert_equal 'stripe', payout.payment_method
  end

  test "create_batch sets processed_by to admin_user" do
    affiliate_ids = [@affiliate1.id]

    result = PayoutBatchService.create_batch(
      affiliate_ids: affiliate_ids,
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    payout = result.payouts.first
    assert_equal @admin_user, payout.processed_by
  end

  test "create_batch sets payout_date to today" do
    affiliate_ids = [@affiliate1.id]

    result = PayoutBatchService.create_batch(
      affiliate_ids: affiliate_ids,
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    payout = result.payouts.first
    assert_equal Date.today, payout.payout_date
  end

  test "create_batch sets status to pending" do
    affiliate_ids = [@affiliate1.id]

    result = PayoutBatchService.create_batch(
      affiliate_ids: affiliate_ids,
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    payout = result.payouts.first
    assert payout.pending?
  end

  test "create_batch stores commission_ids" do
    affiliate_ids = [@affiliate1.id]

    result = PayoutBatchService.create_batch(
      affiliate_ids: affiliate_ids,
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    payout = result.payouts.first
    assert_includes payout.commission_ids, @commission1.id
    assert_includes payout.commission_ids, @commission2.id
  end

  # Minimum threshold filtering
  test "create_batch respects default minimum threshold of 50" do
    # Create affiliate with only $30 in approved commissions
    affiliate_below_threshold = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.20,
      status: :active
    )

    Commission.create!(
      affiliate: affiliate_below_threshold,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 30.00,
      status: :approved,
      earned_at: Time.current
    )

    # Should not create payout for affiliate below threshold
    result = PayoutBatchService.create_batch(
      affiliate_ids: [affiliate_below_threshold.id],
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    assert result.success?
    assert_equal 0, result.payouts.length
  end

  test "create_batch uses custom minimum threshold" do
    # Create affiliate with $60 in approved commissions
    affiliate = @affiliate1

    # With threshold of 100, should not create payout
    result = PayoutBatchService.create_batch(
      affiliate_ids: [affiliate.id],
      payment_method: 'paypal',
      admin_user: @admin_user,
      minimum_threshold: 100
    )

    assert result.success?
    assert_equal 0, result.payouts.length
  end

  test "create_batch includes affiliate at exact threshold" do
    # Create affiliate with exactly $50 in approved commissions
    affiliate_at_threshold = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.20,
      status: :active
    )

    Commission.create!(
      affiliate: affiliate_at_threshold,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 50.00,
      status: :approved,
      earned_at: Time.current
    )

    result = PayoutBatchService.create_batch(
      affiliate_ids: [affiliate_at_threshold.id],
      payment_method: 'paypal',
      admin_user: @admin_user,
      minimum_threshold: 50
    )

    assert result.success?
    assert_equal 1, result.payouts.length
  end

  # Multiple affiliates
  test "create_batch processes multiple affiliates" do
    # Add approved commissions for second affiliate
    Commission.create!(
      affiliate: @affiliate2,
      referral: referrals(:silver_referral),
      entity: entities(:two),
      commission_type: 'first_payment',
      amount: 100.00,
      status: :approved,
      earned_at: Time.current
    )

    affiliate_ids = [@affiliate1.id, @affiliate2.id]

    result = PayoutBatchService.create_batch(
      affiliate_ids: affiliate_ids,
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    assert result.success?
    assert_equal 2, result.payouts.length
  end

  test "create_batch handles mixed affiliates (some above, some below threshold)" do
    # affiliate1 has $100 in commissions (above threshold)
    # Create affiliate2 with only $30 (below threshold)
    affiliate_below = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.20,
      status: :active
    )

    Commission.create!(
      affiliate: affiliate_below,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 30.00,
      status: :approved,
      earned_at: Time.current
    )

    affiliate_ids = [@affiliate1.id, affiliate_below.id]

    result = PayoutBatchService.create_batch(
      affiliate_ids: affiliate_ids,
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    assert result.success?
    assert_equal 1, result.payouts.length # Only affiliate1
  end

  # Commission status filtering
  test "create_batch only includes approved commissions" do
    # Create pending and paid commissions (should not be included)
    pending_commission = Commission.create!(
      affiliate: @affiliate1,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'recurring',
      amount: 50.00,
      status: :pending,
      earned_at: Time.current
    )

    paid_commission = Commission.create!(
      affiliate: @affiliate1,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'recurring',
      amount: 50.00,
      status: :paid,
      earned_at: Time.current
    )

    result = PayoutBatchService.create_batch(
      affiliate_ids: [@affiliate1.id],
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    payout = result.payouts.first

    # Should only include the two approved commissions from setup
    assert_not_includes payout.commission_ids, pending_commission.id
    assert_not_includes payout.commission_ids, paid_commission.id
  end

  # Edge cases and error handling
  test "create_batch with empty affiliate_ids returns success with no payouts" do
    result = PayoutBatchService.create_batch(
      affiliate_ids: [],
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    assert result.success?
    assert_equal 0, result.payouts.length
  end

  test "create_batch with non-existent affiliate_ids returns success" do
    result = PayoutBatchService.create_batch(
      affiliate_ids: [99999],
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    assert result.success?
    assert_equal 0, result.payouts.length
  end

  test "create_batch handles affiliate with no approved commissions" do
    affiliate_no_commissions = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.20,
      status: :active
    )

    result = PayoutBatchService.create_batch(
      affiliate_ids: [affiliate_no_commissions.id],
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    assert result.success?
    assert_equal 0, result.payouts.length
  end

  # Currency
  test "create_batch sets currency to USD" do
    result = PayoutBatchService.create_batch(
      affiliate_ids: [@affiliate1.id],
      payment_method: 'paypal',
      admin_user: @admin_user
    )

    payout = result.payouts.first
    assert_equal 'USD', payout.currency
  end

  # Different payment methods
  test "create_batch supports different payment methods" do
    payment_methods = ['paypal', 'stripe', 'manual', 'bank_transfer']

    payment_methods.each do |method|
      result = PayoutBatchService.create_batch(
        affiliate_ids: [@affiliate1.id],
        payment_method: method,
        admin_user: @admin_user
      )

      payout = result.payouts.first
      assert_equal method, payout.payment_method
    end
  end
end
