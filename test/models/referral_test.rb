require "test_helper"

class ReferralTest < ActiveSupport::TestCase
  # Validation tests
  test "should require referral_code_used" do
    referral = Referral.new(
      affiliate: affiliates(:active_affiliate),
      referred_entity: entities(:one)
    )
    referral.referral_code_used = nil

    assert_not referral.valid?
    assert_includes referral.errors[:referral_code_used], "can't be blank"
  end

  # Association tests
  test "should belong to affiliate" do
    referral = referrals(:pending_referral)
    assert_respond_to referral, :affiliate
    assert_instance_of Affiliate, referral.affiliate
  end

  test "should belong to referred_user" do
    referral = referrals(:pending_referral)
    assert_respond_to referral, :referred_user
  end

  test "should belong to referred_entity" do
    referral = referrals(:pending_referral)
    assert_respond_to referral, :referred_entity
  end

  test "referred_user should be optional" do
    referral = Referral.new(
      affiliate: affiliates(:active_affiliate),
      referred_entity: entities(:one),
      referral_code_used: 'TEST123',
      status: :pending
    )

    assert referral.valid?
  end

  test "referred_entity should be optional" do
    referral = Referral.new(
      affiliate: affiliates(:active_affiliate),
      referred_user: users(:one),
      referral_code_used: 'TEST123',
      status: :pending
    )

    assert referral.valid?
  end

  test "should have many commissions" do
    referral = referrals(:converted_referral)
    assert_respond_to referral, :commissions
  end

  # Enum tests
  test "status enum should work" do
    referral = referrals(:pending_referral)

    assert referral.pending?

    referral.converted!
    assert referral.converted?
    assert_not referral.pending?

    referral.cancelled!
    assert referral.cancelled?
    assert_not referral.converted?
  end

  test "should create with pending status by default" do
    referral = Referral.create!(
      affiliate: affiliates(:active_affiliate),
      referred_entity: entities(:one),
      referral_code_used: 'TEST123'
    )

    assert referral.pending?
  end

  # Scope tests
  test "filter_by_status scope should filter by status" do
    pending_count = Referral.filter_by_status('pending').count
    converted_count = Referral.filter_by_status('converted').count

    assert pending_count > 0
    assert converted_count > 0

    assert Referral.filter_by_status('pending').all?(&:pending?)
    assert Referral.filter_by_status('converted').all?(&:converted?)
  end

  test "filter_by_status scope should return all when status is blank" do
    all_count = Referral.count
    filtered_count = Referral.filter_by_status(nil).count

    assert_equal all_count, filtered_count
  end

  test "recent scope should order by created_at desc" do
    referrals = Referral.recent.limit(2).to_a

    if referrals.size >= 2
      assert referrals[0].created_at >= referrals[1].created_at
    end
  end

  # Business logic tests
  test "should store cookie_data as json" do
    referral = referrals(:pending_referral)

    assert_instance_of Hash, referral.cookie_data
    assert_equal "192.168.1.100", referral.cookie_data["ip"]
  end

  test "should allow updating converted_at when status changes to converted" do
    referral = referrals(:pending_referral)

    referral.update!(
      status: :converted,
      converted_at: Time.current
    )

    assert referral.converted?
    assert_not_nil referral.converted_at
  end

  test "should track which affiliate code was used" do
    referral = referrals(:converted_referral)

    assert_equal 'ACTIVE123', referral.referral_code_used
    assert_equal 'ACTIVE123', referral.affiliate.affiliate_code
  end
end
