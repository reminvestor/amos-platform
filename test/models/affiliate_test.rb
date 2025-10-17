require "test_helper"

class AffiliateTest < ActiveSupport::TestCase
  # Validation tests
  test "should require affiliate_code" do
    affiliate = Affiliate.new(user: users(:one), commission_rate: 0.20)
    affiliate.affiliate_code = nil
    assert_not affiliate.valid?
    assert_includes affiliate.errors[:affiliate_code], "can't be blank"
  end

  test "affiliate_code should be unique" do
    existing = affiliates(:active_affiliate)
    affiliate = Affiliate.new(
      user: users(:one),
      affiliate_code: existing.affiliate_code,
      commission_rate: 0.20
    )
    assert_not affiliate.valid?
    assert_includes affiliate.errors[:affiliate_code], "has already been taken"
  end

  test "commission_rate should be between 0 and 1" do
    affiliate = affiliates(:active_affiliate)

    affiliate.commission_rate = -0.1
    assert_not affiliate.valid?

    affiliate.commission_rate = 1.1
    assert_not affiliate.valid?

    affiliate.commission_rate = 0.5
    assert affiliate.valid?
  end

  test "commission_rate accepts 0 and 1 as valid values" do
    affiliate = affiliates(:active_affiliate)

    affiliate.commission_rate = 0
    assert affiliate.valid?

    affiliate.commission_rate = 1
    assert affiliate.valid?
  end

  # Association tests
  test "should belong to user" do
    affiliate = affiliates(:active_affiliate)
    assert_respond_to affiliate, :user
    assert_instance_of User, affiliate.user
  end

  test "should have many referrals" do
    affiliate = affiliates(:active_affiliate)
    assert_respond_to affiliate, :referrals
  end

  test "should have many affiliate_clicks" do
    affiliate = affiliates(:active_affiliate)
    assert_respond_to affiliate, :affiliate_clicks
  end

  test "should have many commissions" do
    affiliate = affiliates(:active_affiliate)
    assert_respond_to affiliate, :commissions
  end

  test "should have many payouts" do
    affiliate = affiliates(:active_affiliate)
    assert_respond_to affiliate, :payouts
  end

  # Enum tests
  test "status enum should work" do
    affiliate = affiliates(:active_affiliate)

    assert affiliate.active?

    affiliate.pending!
    assert affiliate.pending?

    affiliate.suspended!
    assert affiliate.suspended?

    affiliate.terminated!
    assert affiliate.terminated?
  end

  test "tier enum should work" do
    affiliate = affiliates(:active_affiliate)

    assert affiliate.bronze?

    affiliate.silver!
    assert affiliate.silver?

    affiliate.gold!
    assert affiliate.gold?
  end

  # Callback tests
  test "should generate affiliate_code before validation on create" do
    affiliate = Affiliate.new(
      user: users(:one),
      commission_rate: 0.20
    )

    assert_nil affiliate.affiliate_code
    affiliate.save
    assert_not_nil affiliate.affiliate_code
    assert_equal 8, affiliate.affiliate_code.length
    assert_match /^[A-Z0-9]+$/, affiliate.affiliate_code
  end

  test "should not regenerate affiliate_code if already set" do
    affiliate = Affiliate.new(
      user: users(:one),
      affiliate_code: "CUSTOM99",
      commission_rate: 0.20
    )

    affiliate.save
    assert_equal "CUSTOM99", affiliate.affiliate_code
  end

  # Scope tests
  test "filter_by_status scope should filter by status" do
    pending_count = Affiliate.filter_by_status('pending').count
    active_count = Affiliate.filter_by_status('active').count

    assert pending_count > 0
    assert active_count > 0
  end

  test "filter_by_status scope should return all when status is nil" do
    all_count = Affiliate.count
    filtered_count = Affiliate.filter_by_status(nil).count

    assert_equal all_count, filtered_count
  end

  test "filter_by_tier scope should filter by tier" do
    bronze_count = Affiliate.filter_by_tier('bronze').count
    silver_count = Affiliate.filter_by_tier('silver').count

    assert bronze_count > 0
    assert silver_count > 0
  end

  test "search scope should find affiliates by user email" do
    affiliate = affiliates(:active_affiliate)
    user_email = affiliate.user.email

    results = Affiliate.search(user_email)
    assert_includes results, affiliate
  end

  test "search scope should find affiliates by affiliate_code" do
    affiliate = affiliates(:active_affiliate)

    results = Affiliate.search(affiliate.affiliate_code)
    assert_includes results, affiliate
  end

  test "search scope should return all when query is blank" do
    all_count = Affiliate.count
    results = Affiliate.search(nil).count

    assert_equal all_count, results
  end

  test "with_approved_commissions scope should return affiliates with approved commissions" do
    affiliate = affiliates(:active_affiliate)

    # Create an approved commission
    Commission.create!(
      affiliate: affiliate,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 100,
      status: :approved,
      earned_at: Time.current
    )

    results = Affiliate.with_approved_commissions
    assert_includes results, affiliate
  end

  test "with_approved_commissions_above_threshold should return affiliates above threshold" do
    affiliate = affiliates(:active_affiliate)

    # Create commissions totaling more than threshold
    Commission.create!(
      affiliate: affiliate,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 60,
      status: :approved,
      earned_at: Time.current
    )

    results = Affiliate.with_approved_commissions_above_threshold(50)
    assert_includes results, affiliate
  end

  # Helper method tests
  test "total_clicks should return count of affiliate_clicks" do
    affiliate = affiliates(:active_affiliate)
    expected = affiliate.affiliate_clicks.count

    assert_equal expected, affiliate.total_clicks
  end

  test "total_referrals should return count of referrals" do
    affiliate = affiliates(:active_affiliate)
    expected = affiliate.referrals.count

    assert_equal expected, affiliate.total_referrals
  end

  test "total_conversions should return count of converted referrals" do
    affiliate = affiliates(:active_affiliate)
    expected = affiliate.referrals.converted.count

    assert_equal expected, affiliate.total_conversions
  end

  test "total_earned should sum approved and paid commissions" do
    affiliate = affiliates(:active_affiliate)
    expected = affiliate.commissions.approved.sum(:amount) +
               affiliate.commissions.paid.sum(:amount)

    assert_equal expected, affiliate.total_earned
  end

  test "pending_commissions_amount should sum pending commissions" do
    affiliate = affiliates(:active_affiliate)
    expected = affiliate.commissions.pending.sum(:amount)

    assert_equal expected, affiliate.pending_commissions_amount
  end

  test "approved_commissions_amount should sum approved commissions" do
    affiliate = affiliates(:active_affiliate)
    expected = affiliate.commissions.approved.sum(:amount)

    assert_equal expected, affiliate.approved_commissions_amount
  end

  test "total_paid_out should sum completed payouts" do
    affiliate = affiliates(:active_affiliate)
    expected = affiliate.payouts.completed.sum(:amount)

    assert_equal expected, affiliate.total_paid_out
  end

  test "conversion_rate should calculate percentage correctly" do
    affiliate = affiliates(:active_affiliate)

    # Create some clicks and conversions
    3.times do
      AffiliateClick.create!(
        affiliate: affiliate,
        referral_code: affiliate.affiliate_code,
        ip_address: '192.168.1.1',
        landed_at: Time.current
      )
    end

    # One conversion out of 3 clicks = 33.33%
    referral = Referral.create!(
      affiliate: affiliate,
      referred_entity: entities(:one),
      referral_code_used: affiliate.affiliate_code,
      status: :converted
    )

    # Reload to get fresh counts
    affiliate.reload

    expected_rate = (1.0 / affiliate.total_clicks * 100).round(2)
    assert_equal expected_rate, affiliate.conversion_rate
  end

  test "conversion_rate should return 0 when no clicks" do
    affiliate = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.20
    )

    assert_equal 0, affiliate.conversion_rate
  end
end
