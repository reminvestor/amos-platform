require "test_helper"

class AffiliateCommissionServiceTest < ActiveSupport::TestCase
  def setup
    @affiliate = affiliates(:active_affiliate)
    @entity = entities(:two)

    # Create a pending referral for testing
    @referral = Referral.create!(
      affiliate: @affiliate,
      referred_entity: @entity,
      referral_code_used: @affiliate.affiliate_code,
      status: :pending
    )
  end

  # First payment commission tests
  test "create_for_first_payment creates commission for pending referral" do
    amount = 500.00

    assert_difference 'Commission.count', 1 do
      commission = AffiliateCommissionService.create_for_first_payment(@entity, amount)

      assert_not_nil commission
      assert_equal @affiliate, commission.affiliate
      assert_equal @referral, commission.referral
      assert_equal @entity, commission.entity
      assert_equal 'first_payment', commission.commission_type
    end
  end

  test "create_for_first_payment calculates commission amount correctly" do
    amount = 1000.00
    expected_commission = amount * @affiliate.commission_rate

    commission = AffiliateCommissionService.create_for_first_payment(@entity, amount)

    assert_equal expected_commission, commission.amount
  end

  test "create_for_first_payment auto-approves small commissions" do
    amount = 100.00 # Will result in $20 commission (below $500 threshold)

    commission = AffiliateCommissionService.create_for_first_payment(@entity, amount)

    assert commission.approved?
    assert_not_nil commission.approved_at
  end

  test "create_for_first_payment requires review for high commissions" do
    amount = 3000.00 # Will result in $600 commission (above $500 threshold)

    commission = AffiliateCommissionService.create_for_first_payment(@entity, amount)

    assert commission.pending?
    assert_nil commission.approved_at
  end

  test "create_for_first_payment marks referral as converted" do
    amount = 500.00

    assert @referral.pending?

    commission = AffiliateCommissionService.create_for_first_payment(@entity, amount)

    @referral.reload
    assert @referral.converted?
    assert_not_nil @referral.converted_at
  end

  test "create_for_first_payment returns nil when no pending referral exists" do
    entity_without_referral = entities(:default)

    commission = AffiliateCommissionService.create_for_first_payment(entity_without_referral, 500)

    assert_nil commission
  end

  test "create_for_first_payment prevents duplicate first payment commissions" do
    amount = 500.00

    # Create first commission
    first_commission = AffiliateCommissionService.create_for_first_payment(@entity, amount)
    assert_not_nil first_commission

    # Try to create duplicate
    assert_no_difference 'Commission.count' do
      second_commission = AffiliateCommissionService.create_for_first_payment(@entity, amount)

      # Should return existing commission
      assert_equal first_commission.id, second_commission.id
    end
  end

  test "create_for_first_payment sets currency to USD" do
    commission = AffiliateCommissionService.create_for_first_payment(@entity, 500)

    assert_equal 'USD', commission.currency
  end

  test "create_for_first_payment sets earned_at timestamp" do
    commission = AffiliateCommissionService.create_for_first_payment(@entity, 500)

    assert_not_nil commission.earned_at
    assert_in_delta Time.current, commission.earned_at, 5.seconds
  end

  # Recurring payment commission tests
  test "create_for_recurring_payment creates commission for converted referral" do
    # Convert the referral first
    @referral.update!(status: :converted, converted_at: 1.day.ago)

    amount = 100.00

    assert_difference 'Commission.count', 1 do
      commission = AffiliateCommissionService.create_for_recurring_payment(@entity, amount)

      assert_not_nil commission
      assert_equal 'recurring', commission.commission_type
    end
  end

  test "create_for_recurring_payment calculates commission amount correctly" do
    @referral.update!(status: :converted, converted_at: 1.day.ago)

    amount = 100.00
    expected_commission = amount * @affiliate.commission_rate

    commission = AffiliateCommissionService.create_for_recurring_payment(@entity, amount)

    assert_equal expected_commission, commission.amount
  end

  test "create_for_recurring_payment returns nil for referrals older than 12 months" do
    # Destroy any other converted referrals for this entity to avoid test pollution
    Referral.where(referred_entity: @entity, status: :converted).destroy_all

    # Set converted_at to 13 months ago (beyond 12-month limit)
    @referral.update!(status: :converted, converted_at: 13.months.ago)

    commission = AffiliateCommissionService.create_for_recurring_payment(@entity, 100)

    assert_nil commission
  end

  test "create_for_recurring_payment works for referrals within 12 months" do
    # Set converted_at to 11 months ago (within 12-month limit)
    @referral.update!(status: :converted, converted_at: 11.months.ago)

    commission = AffiliateCommissionService.create_for_recurring_payment(@entity, 100)

    assert_not_nil commission
  end

  test "create_for_recurring_payment works for referrals exactly 12 months old" do
    # Set converted_at to exactly 12 months ago
    @referral.update!(status: :converted, converted_at: 12.months.ago + 1.day)

    commission = AffiliateCommissionService.create_for_recurring_payment(@entity, 100)

    assert_not_nil commission
  end

  test "create_for_recurring_payment returns nil for pending referrals" do
    # Ensure only the pending referral exists for this entity
    Referral.where(referred_entity: @entity, status: :converted).destroy_all

    assert @referral.pending?

    commission = AffiliateCommissionService.create_for_recurring_payment(@entity, 100)

    assert_nil commission
  end

  test "create_for_recurring_payment returns nil when no converted referral exists" do
    entity_without_referral = entities(:one)

    commission = AffiliateCommissionService.create_for_recurring_payment(entity_without_referral, 100)

    assert_nil commission
  end

  test "create_for_recurring_payment auto-approves small commissions" do
    @referral.update!(status: :converted, converted_at: 1.day.ago)

    amount = 100.00 # Will result in $20 commission

    commission = AffiliateCommissionService.create_for_recurring_payment(@entity, amount)

    assert commission.approved?
    assert_not_nil commission.approved_at
  end

  test "create_for_recurring_payment requires review for high commissions" do
    @referral.update!(status: :converted, converted_at: 1.day.ago)

    amount = 3000.00 # Will result in $600 commission

    commission = AffiliateCommissionService.create_for_recurring_payment(@entity, amount)

    assert commission.pending?
    assert_nil commission.approved_at
  end

  test "create_for_recurring_payment allows multiple recurring commissions" do
    @referral.update!(status: :converted, converted_at: 1.day.ago)

    # Create first recurring commission
    commission1 = AffiliateCommissionService.create_for_recurring_payment(@entity, 100)
    assert_not_nil commission1

    # Create second recurring commission (should succeed)
    commission2 = AffiliateCommissionService.create_for_recurring_payment(@entity, 100)
    assert_not_nil commission2

    # Should be different commissions
    assert_not_equal commission1.id, commission2.id
  end

  # Commission threshold tests
  test "commission threshold is set to 500" do
    assert_equal 500.00, AffiliateCommissionService::HIGH_COMMISSION_THRESHOLD
  end

  test "commission of exactly 500 requires review" do
    # Set commission rate to create exactly $500 commission
    @affiliate.update!(commission_rate: 0.5)
    @referral.update!(status: :converted, converted_at: 1.day.ago)

    commission = AffiliateCommissionService.create_for_recurring_payment(@entity, 1000)

    assert_equal 500.00, commission.amount
    assert commission.pending?
  end

  test "commission of 499.99 is auto-approved" do
    # Set commission rate to create $499.99 commission
    @affiliate.update!(commission_rate: 0.499999)
    @referral.update!(status: :converted, converted_at: 1.day.ago)

    commission = AffiliateCommissionService.create_for_recurring_payment(@entity, 1000)

    assert commission.amount < 500
    assert commission.approved?
  end

  # Edge cases
  test "create_for_first_payment handles very small amounts" do
    commission = AffiliateCommissionService.create_for_first_payment(@entity, 0.01)

    assert_not_nil commission
    assert commission.amount > 0
  end

  test "create_for_first_payment handles very large amounts" do
    commission = AffiliateCommissionService.create_for_first_payment(@entity, 10000.00)

    assert_not_nil commission
    assert commission.pending? # Should require review due to high amount
  end

  test "commissions for different commission rates" do
    amounts = [100, 500, 1000]
    rates = [0.10, 0.20, 0.30]

    rates.each do |rate|
      @affiliate.update!(commission_rate: rate)

      amounts.each do |amount|
        # Create new referral for each test
        referral = Referral.create!(
          affiliate: @affiliate,
          referred_entity: Entity.create!(
            name: "Test #{rand(1000)}",
            subdomain: "test-#{rand(1000)}",
            slug: "test-#{rand(1000)}",
            status: 'active'
          ),
          referral_code_used: @affiliate.affiliate_code,
          status: :pending
        )

        commission = AffiliateCommissionService.create_for_first_payment(
          referral.referred_entity,
          amount
        )

        expected_amount = amount * rate
        assert_equal expected_amount, commission.amount
      end
    end
  end
end
