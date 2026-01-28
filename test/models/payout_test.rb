require "test_helper"

class PayoutTest < ActiveSupport::TestCase
  # Validation tests
  test "should require amount greater than 0" do
    payout = Payout.new(
      affiliate: affiliates(:active_affiliate),
      amount: 0,
      payment_method: 'paypal'
    )

    assert_not payout.valid?
    assert_includes payout.errors[:amount], "must be greater than 0"
  end

  test "should not allow negative amount" do
    payout = Payout.new(
      affiliate: affiliates(:active_affiliate),
      amount: -50,
      payment_method: 'paypal'
    )

    assert_not payout.valid?
  end

  test "should require payment_method" do
    payout = Payout.new(
      affiliate: affiliates(:active_affiliate),
      amount: 100
    )
    payout.payment_method = nil

    assert_not payout.valid?
    assert_includes payout.errors[:payment_method], "can't be blank"
  end

  # Association tests
  test "should belong to affiliate" do
    payout = payouts(:pending_payout)
    assert_respond_to payout, :affiliate
    assert_instance_of Affiliate, payout.affiliate
  end

  test "processed_by should be optional" do
    payout = payouts(:pending_payout)
    assert_nil payout.processed_by
  end

  # Enum tests
  test "status enum should work" do
    payout = payouts(:pending_payout)

    assert payout.pending?

    payout.processing!
    assert payout.processing?

    payout.completed!
    assert payout.completed?

    payout.failed!
    assert payout.failed?
  end

  # Scope tests
  test "filter_by_status scope should filter by status" do
    pending_count = Payout.filter_by_status('pending').count
    completed_count = Payout.filter_by_status('completed').count

    assert pending_count > 0
    assert completed_count > 0

    assert Payout.filter_by_status('pending').all?(&:pending?)
    assert Payout.filter_by_status('completed').all?(&:completed?)
  end

  test "filter_by_status scope returns all when status is blank" do
    all_count = Payout.count
    filtered = Payout.filter_by_status(nil).count

    assert_equal all_count, filtered
  end

  test "recent scope should order by created_at desc" do
    payouts = Payout.recent.limit(2).to_a

    if payouts.size >= 2
      assert payouts[0].created_at >= payouts[1].created_at
    end
  end

  # Method tests
  test "mark_completed! should update status and set payment_reference" do
    payout = payouts(:pending_payout)
    admin_user = AdminUser.find_or_create_by!(email: "admin_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'password123'
    end

    assert payout.pending?
    assert_nil payout.payment_reference
    assert_nil payout.processed_by

    payout.mark_completed!(admin_user, 'PAYPAL-12345')

    assert payout.completed?
    assert_equal 'PAYPAL-12345', payout.payment_reference
    assert_equal admin_user, payout.processed_by
  end

  test "mark_completed! should work without payment_reference" do
    payout = payouts(:pending_payout)
    admin_user = AdminUser.find_or_create_by!(email: "admin_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'password123'
    end

    payout.mark_completed!(admin_user)

    assert payout.completed?
    assert_nil payout.payment_reference
    assert_equal admin_user, payout.processed_by
  end

  test "mark_completed! should mark associated commissions as paid" do
    # Create commissions
    commission1 = commissions(:approved_commission)
    commission2 = Commission.create!(
      affiliate: affiliates(:active_affiliate),
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'recurring',
      amount: 50,
      status: :approved,
      earned_at: Time.current
    )

    # Create payout with commission_ids
    payout = Payout.create!(
      affiliate: affiliates(:active_affiliate),
      amount: 150,
      payment_method: 'paypal',
      commission_ids: [commission1.id, commission2.id],
      status: :pending
    )

    admin_user = AdminUser.find_or_create_by!(email: "admin_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'password123'
    end

    # Mark payout as completed
    payout.mark_completed!(admin_user, 'TXN-123')

    # Reload commissions and check status
    commission1.reload
    commission2.reload

    assert commission1.paid?
    assert commission2.paid?
  end

  # Business logic tests
  test "should support different payment methods" do
    methods = ['paypal', 'stripe', 'manual', 'bank_transfer']

    methods.each do |method|
      payout = Payout.new(
        affiliate: affiliates(:active_affiliate),
        amount: 100,
        payment_method: method
      )

      assert payout.valid?, "Should accept payment_method: #{method}"
    end
  end

  test "should track currency" do
    payout = payouts(:pending_payout)
    assert_equal 'USD', payout.currency
  end

  test "should store commission_ids as array" do
    payout = Payout.create!(
      affiliate: affiliates(:active_affiliate),
      amount: 150,
      payment_method: 'paypal',
      commission_ids: [1, 2, 3]
    )

    assert_equal [1, 2, 3], payout.commission_ids
  end

  test "commission_ids should default to empty array" do
    payout = Payout.create!(
      affiliate: affiliates(:active_affiliate),
      amount: 100,
      payment_method: 'paypal'
    )

    assert_equal [], payout.commission_ids
  end

  test "should allow storing notes" do
    payout = payouts(:pending_payout)
    payout.update!(notes: 'Special payout instructions')

    assert_equal 'Special payout instructions', payout.notes
  end

  test "should track payout_date" do
    payout = payouts(:completed_payout)
    assert_instance_of Date, payout.payout_date
  end
end
