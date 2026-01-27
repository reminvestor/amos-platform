require "test_helper"

class PayoutFlowTest < ActionDispatch::IntegrationTest
  def setup
    @admin = AdminUser.find_or_create_by!(email: "admin_payout_flow_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'password123'
    end

    @affiliate1 = affiliates(:active_affiliate)
    @affiliate2 = affiliates(:silver_affiliate)

    # Create approved commissions for affiliate1
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

    # Create approved commissions for affiliate2
    @commission3 = Commission.create!(
      affiliate: @affiliate2,
      referral: referrals(:silver_referral),
      entity: entities(:two),
      commission_type: 'first_payment',
      amount: 150.00,
      status: :approved,
      earned_at: Time.current
    )
  end

  test "complete payout flow: create batch -> process -> mark completed" do
    # Step 1: Create payout batch for affiliates with approved commissions
    result = PayoutBatchService.create_batch(
      affiliate_ids: [@affiliate1.id, @affiliate2.id],
      payment_method: 'paypal',
      admin_user: @admin
    )

    assert result.success?
    assert_equal 2, result.payouts.length

    payout1 = result.payouts.find { |p| p.affiliate == @affiliate1 }
    payout2 = result.payouts.find { |p| p.affiliate == @affiliate2 }

    # Step 2: Verify payout details
    assert_equal 100.00, payout1.amount # $60 + $40
    assert_equal 150.00, payout2.amount
    assert payout1.pending?
    assert payout2.pending?

    # Step 3: Mark first payout as completed
    payout1.mark_completed!(@admin, 'PAYPAL-TXN-12345')

    payout1.reload
    assert payout1.completed?
    assert_equal 'PAYPAL-TXN-12345', payout1.payment_reference
    assert_equal @admin, payout1.processed_by

    # Step 4: Verify commissions are marked as paid
    @commission1.reload
    @commission2.reload

    assert @commission1.paid?
    assert @commission2.paid?

    # Step 5: Mark second payout as completed
    payout2.mark_completed!(@admin, 'PAYPAL-TXN-67890')

    @commission3.reload
    assert @commission3.paid?
  end

  test "payout batch respects minimum threshold" do
    # Create affiliate with less than minimum threshold
    low_affiliate = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.20,
      status: :active
    )

    Commission.create!(
      affiliate: low_affiliate,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 30.00,
      status: :approved,
      earned_at: Time.current
    )

    # Should not create payout for affiliate below $50 threshold
    result = PayoutBatchService.create_batch(
      affiliate_ids: [low_affiliate.id],
      payment_method: 'paypal',
      admin_user: @admin,
      minimum_threshold: 50
    )

    assert result.success?
    assert_equal 0, result.payouts.length
  end

  test "payout batch only includes approved commissions" do
    # Create pending and cancelled commissions
    pending = Commission.create!(
      affiliate: @affiliate1,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'recurring',
      amount: 50.00,
      status: :pending,
      earned_at: Time.current
    )

    cancelled = Commission.create!(
      affiliate: @affiliate1,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'recurring',
      amount: 50.00,
      status: :cancelled,
      earned_at: Time.current
    )

    result = PayoutBatchService.create_batch(
      affiliate_ids: [@affiliate1.id],
      payment_method: 'paypal',
      admin_user: @admin
    )

    payout = result.payouts.first

    # Should only include approved commissions
    assert_includes payout.commission_ids, @commission1.id
    assert_includes payout.commission_ids, @commission2.id
    assert_not_includes payout.commission_ids, pending.id
    assert_not_includes payout.commission_ids, cancelled.id
  end

  test "payout stores commission_ids for tracking" do
    result = PayoutBatchService.create_batch(
      affiliate_ids: [@affiliate1.id],
      payment_method: 'paypal',
      admin_user: @admin
    )

    payout = result.payouts.first

    assert_equal 2, payout.commission_ids.length
    assert_includes payout.commission_ids, @commission1.id
    assert_includes payout.commission_ids, @commission2.id
  end

  test "payout can have different payment methods" do
    payment_methods = ['paypal', 'stripe', 'manual', 'bank_transfer']

    payment_methods.each do |method|
      result = PayoutBatchService.create_batch(
        affiliate_ids: [@affiliate1.id],
        payment_method: method,
        admin_user: @admin
      )

      payout = result.payouts.first
      assert_equal method, payout.payment_method
    end
  end

  test "payout can fail and be retried" do
    # Create payout
    result = PayoutBatchService.create_batch(
      affiliate_ids: [@affiliate1.id],
      payment_method: 'paypal',
      admin_user: @admin
    )

    payout = result.payouts.first

    # Mark as failed
    payout.update!(status: :failed, notes: 'Payment processing failed')

    assert payout.failed?

    # Commissions should remain approved (not paid)
    @commission1.reload
    @commission2.reload

    assert @commission1.approved?
    assert @commission2.approved?

    # Can be retried - create new payout
    retry_result = PayoutBatchService.create_batch(
      affiliate_ids: [@affiliate1.id],
      payment_method: 'paypal',
      admin_user: @admin
    )

    retry_payout = retry_result.payouts.first
    assert retry_payout.pending?

    # Complete the retry
    retry_payout.mark_completed!(@admin, 'SUCCESS-123')

    @commission1.reload
    @commission2.reload

    assert @commission1.paid?
    assert @commission2.paid?
  end

  test "complete affiliate earnings cycle" do
    # Start fresh
    affiliate = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.25,
      status: :active
    )

    entity = Entity.create!(
      name: 'Cycle Test',
      subdomain: 'cycle',
      slug: 'cycle',
      status: 'active'
    )

    # 1. Create referral
    referral = Referral.create!(
      affiliate: affiliate,
      referred_entity: entity,
      referral_code_used: affiliate.affiliate_code,
      status: :pending
    )

    # 2. First payment creates commission
    first_commission = AffiliateCommissionService.create_for_first_payment(
      entity,
      400.00 # $100 commission at 25%
    )

    assert first_commission.approved? # Auto-approved under $500
    assert_equal 100.00, first_commission.amount

    # 3. Recurring payments
    referral.reload
    assert referral.converted?

    recurring1 = AffiliateCommissionService.create_for_recurring_payment(
      entity,
      400.00 # $100 commission
    )

    recurring2 = AffiliateCommissionService.create_for_recurring_payment(
      entity,
      400.00 # $100 commission
    )

    # Total: $300 in approved commissions
    total_approved = affiliate.commissions.approved.sum(:amount)
    assert_equal 300.00, total_approved

    # 4. Create payout
    result = PayoutBatchService.create_batch(
      affiliate_ids: [affiliate.id],
      payment_method: 'paypal',
      admin_user: @admin
    )

    payout = result.payouts.first
    assert_equal 300.00, payout.amount

    # 5. Complete payout
    payout.mark_completed!(@admin, 'FINAL-PAYOUT')

    # 6. Verify all commissions are paid
    assert affiliate.commissions.all?(&:paid?)
    assert_equal 0, affiliate.commissions.approved.sum(:amount)
    assert_equal 300.00, affiliate.payouts.completed.sum(:amount)
  end

  test "affiliate stats reflect payout status" do
    # Before payout
    stats_before = AffiliateStatsService.new(@affiliate1).calculate

    assert stats_before[:approved_commissions] > 0
    initial_paid = stats_before[:total_paid]

    # Create and complete payout
    result = PayoutBatchService.create_batch(
      affiliate_ids: [@affiliate1.id],
      payment_method: 'paypal',
      admin_user: @admin
    )

    payout = result.payouts.first
    payout.mark_completed!(@admin, 'STATS-TEST')

    # After payout
    @affiliate1.reload
    stats_after = AffiliateStatsService.new(@affiliate1).calculate

    assert_equal 0.0, stats_after[:approved_commissions]
    assert stats_after[:total_paid] > initial_paid
    assert_equal payout.amount, stats_after[:total_paid] - initial_paid
  end
end
