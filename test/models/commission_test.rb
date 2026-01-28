require "test_helper"

class CommissionTest < ActiveSupport::TestCase
  # Validation tests
  test "should require amount greater than 0" do
    commission = Commission.new(
      affiliate: affiliates(:active_affiliate),
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 0
    )

    assert_not commission.valid?
    assert_includes commission.errors[:amount], "must be greater than 0"
  end

  test "should not allow negative amount" do
    commission = Commission.new(
      affiliate: affiliates(:active_affiliate),
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: -10
    )

    assert_not commission.valid?
  end

  test "should require commission_type" do
    commission = Commission.new(
      affiliate: affiliates(:active_affiliate),
      referral: referrals(:converted_referral),
      entity: entities(:one),
      amount: 100
    )
    commission.commission_type = nil

    assert_not commission.valid?
    assert_includes commission.errors[:commission_type], "can't be blank"
  end

  # Association tests
  test "should belong to affiliate" do
    commission = commissions(:pending_commission)
    assert_respond_to commission, :affiliate
    assert_instance_of Affiliate, commission.affiliate
  end

  test "should belong to referral" do
    commission = commissions(:pending_commission)
    assert_respond_to commission, :referral
    assert_instance_of Referral, commission.referral
  end

  test "should belong to entity" do
    commission = commissions(:pending_commission)
    assert_respond_to commission, :entity
    assert_instance_of Entity, commission.entity
  end

  test "subscription_event should be optional" do
    commission = Commission.new(
      affiliate: affiliates(:active_affiliate),
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 100,
      status: :pending,
      earned_at: Time.current
    )

    assert commission.valid?
  end

  test "approved_by should be optional" do
    commission = commissions(:pending_commission)
    assert_nil commission.approved_by
  end

  # Enum tests
  test "status enum should work" do
    commission = commissions(:pending_commission)

    assert commission.pending?

    commission.approved!
    assert commission.approved?

    commission.paid!
    assert commission.paid?

    commission.cancelled!
    assert commission.cancelled?
  end

  # Scope tests
  test "filter_by_status scope should filter by status" do
    pending_count = Commission.filter_by_status('pending').count
    approved_count = Commission.filter_by_status('approved').count

    assert pending_count > 0
    assert approved_count > 0

    assert Commission.filter_by_status('pending').all?(&:pending?)
    assert Commission.filter_by_status('approved').all?(&:approved?)
  end

  test "filter_by_status scope returns all when status is blank" do
    all_count = Commission.count
    filtered = Commission.filter_by_status(nil).count

    assert_equal all_count, filtered
  end

  test "filter_by_date_range scope should filter by earned_at" do
    start_date = 20.days.ago
    end_date = 2.days.ago

    commissions = Commission.filter_by_date_range(start_date, end_date)

    commissions.each do |commission|
      assert commission.earned_at >= start_date
      assert commission.earned_at <= end_date
    end
  end

  test "filter_by_date_range scope returns all when dates are nil" do
    all_count = Commission.count
    filtered = Commission.filter_by_date_range(nil, nil).count

    assert_equal all_count, filtered
  end

  test "filter_by_affiliate scope should filter by affiliate_id" do
    affiliate = affiliates(:active_affiliate)
    commissions = Commission.filter_by_affiliate(affiliate.id)

    commissions.each do |commission|
      assert_equal affiliate.id, commission.affiliate_id
    end
  end

  test "recent scope should order by earned_at desc" do
    commissions = Commission.recent.limit(2).to_a

    if commissions.size >= 2
      assert commissions[0].earned_at >= commissions[1].earned_at
    end
  end

  # Method tests
  test "approve! should update status and set approved_at" do
    commission = commissions(:pending_commission)
    admin_user = AdminUser.find_or_create_by!(email: "admin_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'password123'
    end

    assert commission.pending?
    assert_nil commission.approved_at
    assert_nil commission.approved_by

    commission.approve!(admin_user)

    assert commission.approved?
    assert_not_nil commission.approved_at
    assert_equal admin_user, commission.approved_by
  end

  test "cancel! should update status to cancelled" do
    commission = commissions(:pending_commission)

    assert commission.pending?

    commission.cancel!

    assert commission.cancelled?
  end

  test "mark_as_paid! should update status to paid" do
    commission = commissions(:approved_commission)

    assert commission.approved?

    commission.mark_as_paid!

    assert commission.paid?
  end

  # Business logic tests
  test "should support different commission types" do
    types = ['first_payment', 'recurring', 'signup_bonus', 'lifetime']

    types.each do |type|
      commission = Commission.new(
        affiliate: affiliates(:active_affiliate),
        referral: referrals(:converted_referral),
        entity: entities(:one),
        commission_type: type,
        amount: 100,
        earned_at: Time.current
      )

      assert commission.valid?, "Should accept commission_type: #{type}"
    end
  end

  test "should track currency" do
    commission = commissions(:pending_commission)
    assert_equal 'USD', commission.currency
  end

  test "should allow decimal amounts" do
    commission = Commission.create!(
      affiliate: affiliates(:active_affiliate),
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 123.45,
      earned_at: Time.current
    )

    assert_equal 123.45, commission.amount
  end
end
