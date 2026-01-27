require "test_helper"

class CommissionCreationFlowTest < ActionDispatch::IntegrationTest
  def setup
    @affiliate = affiliates(:active_affiliate)
    @entity = entities(:two)

    # Create pending referral
    @referral = Referral.create!(
      affiliate: @affiliate,
      referred_entity: @entity,
      referral_code_used: @affiliate.affiliate_code,
      status: :pending
    )
  end

  test "first payment creates commission and converts referral" do
    payment_amount = 1000.00

    # Simulate first payment
    assert_difference 'Commission.count', 1 do
      commission = AffiliateCommissionService.create_for_first_payment(
        @entity,
        payment_amount
      )

      assert_not_nil commission
      assert_equal 'first_payment', commission.commission_type
      assert_equal payment_amount * @affiliate.commission_rate, commission.amount
    end

    # Referral should be marked as converted
    @referral.reload
    assert @referral.converted?
    assert_not_nil @referral.converted_at
  end

  test "first payment commission is auto-approved for small amounts" do
    payment_amount = 100.00 # Results in $20 commission

    commission = AffiliateCommissionService.create_for_first_payment(
      @entity,
      payment_amount
    )

    assert commission.approved?
    assert_not_nil commission.approved_at
  end

  test "first payment commission requires review for high amounts" do
    payment_amount = 3000.00 # Results in $600 commission

    commission = AffiliateCommissionService.create_for_first_payment(
      @entity,
      payment_amount
    )

    assert commission.pending?
    assert_nil commission.approved_at
  end

  test "recurring payment creates commission for recent conversions" do
    # Convert the referral
    @referral.update!(status: :converted, converted_at: 1.day.ago)

    payment_amount = 100.00

    assert_difference 'Commission.count', 1 do
      commission = AffiliateCommissionService.create_for_recurring_payment(
        @entity,
        payment_amount
      )

      assert_not_nil commission
      assert_equal 'recurring', commission.commission_type
      assert_equal payment_amount * @affiliate.commission_rate, commission.amount
    end
  end

  test "recurring payment does not create commission after 12 months" do
    # Convert the referral 13 months ago
    @referral.update!(status: :converted, converted_at: 13.months.ago)

    payment_amount = 100.00

    assert_no_difference 'Commission.count' do
      commission = AffiliateCommissionService.create_for_recurring_payment(
        @entity,
        payment_amount
      )

      assert_nil commission
    end
  end

  test "multiple recurring payments create multiple commissions" do
    @referral.update!(status: :converted, converted_at: 1.day.ago)

    # First recurring payment
    commission1 = AffiliateCommissionService.create_for_recurring_payment(
      @entity,
      100.00
    )

    # Second recurring payment
    commission2 = AffiliateCommissionService.create_for_recurring_payment(
      @entity,
      100.00
    )

    assert_not_nil commission1
    assert_not_nil commission2
    assert_not_equal commission1.id, commission2.id
  end

  test "duplicate first payment commission is prevented" do
    # Create first commission
    commission1 = AffiliateCommissionService.create_for_first_payment(
      @entity,
      500.00
    )

    assert_not_nil commission1
    assert_not_nil commission1.id

    # Try to create duplicate
    commission2 = AffiliateCommissionService.create_for_first_payment(
      @entity,
      500.00
    )

    # Should return existing commission
    assert_not_nil commission2
    assert_equal commission1.id, commission2.id
  end

  test "commission lifecycle: pending -> approved -> paid" do
    # Create pending commission
    commission = Commission.create!(
      affiliate: @affiliate,
      referral: @referral,
      entity: @entity,
      commission_type: 'first_payment',
      amount: 600.00,
      status: :pending,
      earned_at: Time.current
    )

    assert commission.pending?

    # Admin approves it
    admin = AdminUser.find_or_create_by!(email: "admin_commission_flow_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'password123'
      u.first_name = 'Admin'
      u.last_name = 'User'
      u.role = :super_admin
    end
    commission.approve!(admin)

    assert commission.approved?
    assert_not_nil commission.approved_at
    assert_equal admin, commission.approved_by

    # Include in payout and mark as paid
    commission.mark_as_paid!

    assert commission.paid?
  end

  test "commission can be cancelled" do
    commission = Commission.create!(
      affiliate: @affiliate,
      referral: @referral,
      entity: @entity,
      commission_type: 'first_payment',
      amount: 100.00,
      status: :pending,
      earned_at: Time.current
    )

    commission.cancel!

    assert commission.cancelled?
  end

  test "complete flow: signup -> first payment -> recurring payments -> 12 month cutoff" do
    # Setup
    user = User.create!(
      email: 'flow@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'Flow',
      last_name: 'Test',
      role: 'admin'
    )

    entity = Entity.create!(
      name: 'Flow Entity',
      subdomain: 'flow',
      slug: 'flow',
      status: 'active'
    )

    # 1. Create referral on signup
    referral = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: user,
      entity: entity
    )

    assert_not_nil referral
    assert referral.pending?

    # 2. First payment
    first_commission = AffiliateCommissionService.create_for_first_payment(
      entity,
      500.00
    )

    assert_not_nil first_commission
    assert_equal 'first_payment', first_commission.commission_type

    referral.reload
    assert referral.converted?

    # 3. Recurring payments within 12 months
    recurring1 = AffiliateCommissionService.create_for_recurring_payment(
      entity,
      100.00
    )

    assert_not_nil recurring1
    assert_equal 'recurring', recurring1.commission_type

    # 4. Simulate time passing (13 months)
    referral.update!(converted_at: 13.months.ago)

    # 5. Recurring payment after 12 months should NOT create commission
    recurring_old = AffiliateCommissionService.create_for_recurring_payment(
      entity,
      100.00
    )

    assert_nil recurring_old
  end
end
