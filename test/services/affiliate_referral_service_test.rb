require "test_helper"

class AffiliateReferralServiceTest < ActiveSupport::TestCase
  def setup
    @affiliate = affiliates(:active_affiliate)
    # Create entity first so user can reference it
    @entity = Entity.create!(
      name: 'New Entity',
      subdomain: "new-entity-#{SecureRandom.hex(4)}",
      slug: "new-entity-#{SecureRandom.hex(4)}",
      status: 'active'
    )
    @user = User.create!(
      email: "newuser-#{SecureRandom.hex(4)}@example.com",
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'New',
      last_name: 'User',
      entity: @entity  # Associate user with entity
    )
    @cookie_data = {
      ip: '192.168.1.100',
      user_agent: 'Mozilla/5.0'
    }
  end

  # Successful referral creation
  test "create_referral creates referral for active affiliate" do
    assert_difference 'Referral.count', 1 do
      referral = AffiliateReferralService.create_referral(
        referral_code: @affiliate.affiliate_code,
        user: @user,
        entity: @entity,
        cookie_data: @cookie_data
      )

      assert_not_nil referral
      assert_equal @affiliate, referral.affiliate
      assert_equal @user, referral.referred_user
      assert_equal @entity, referral.referred_entity
      assert_equal @affiliate.affiliate_code, referral.referral_code_used
      assert referral.pending?
    end
  end

  test "create_referral stores cookie_data" do
    referral = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: @user,
      entity: @entity,
      cookie_data: @cookie_data
    )

    assert_equal '192.168.1.100', referral.cookie_data['ip']
    assert_equal 'Mozilla/5.0', referral.cookie_data['user_agent']
    assert_not_nil referral.cookie_data['created_at']
  end

  test "create_referral sets status to pending" do
    referral = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: @user,
      entity: @entity,
      cookie_data: @cookie_data
    )

    assert referral.pending?
  end

  # Affiliate not found or inactive
  test "create_referral returns nil for non-existent affiliate code" do
    referral = AffiliateReferralService.create_referral(
      referral_code: 'INVALID123',
      user: @user,
      entity: @entity,
      cookie_data: @cookie_data
    )

    assert_nil referral
  end

  test "create_referral returns nil for inactive affiliate" do
    inactive_affiliate = affiliates(:suspended_affiliate)

    referral = AffiliateReferralService.create_referral(
      referral_code: inactive_affiliate.affiliate_code,
      user: @user,
      entity: @entity,
      cookie_data: @cookie_data
    )

    assert_nil referral
  end

  test "create_referral returns nil for pending affiliate" do
    pending_affiliate = affiliates(:pending_affiliate)

    referral = AffiliateReferralService.create_referral(
      referral_code: pending_affiliate.affiliate_code,
      user: @user,
      entity: @entity,
      cookie_data: @cookie_data
    )

    assert_nil referral
  end

  # Duplicate prevention
  test "create_referral prevents duplicate referrals for same entity" do
    # Create first referral
    first_referral = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: @user,
      entity: @entity,
      cookie_data: @cookie_data
    )

    assert_not_nil first_referral

    # Try to create second referral for same entity
    second_referral = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: @user,
      entity: @entity,
      cookie_data: @cookie_data
    )

    # Should return existing referral, not create new one
    assert_equal first_referral.id, second_referral.id
  end

  test "create_referral does not create duplicate for same entity" do
    # Create first referral
    AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: @user,
      entity: @entity,
      cookie_data: @cookie_data
    )

    # Try to create duplicate - should not increase count
    assert_no_difference 'Referral.count' do
      AffiliateReferralService.create_referral(
        referral_code: @affiliate.affiliate_code,
        user: @user,
        entity: @entity,
        cookie_data: @cookie_data
      )
    end
  end

  # Error handling
  test "create_referral handles invalid data gracefully" do
    # Try to create referral with nil entity (should fail validation)
    referral = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: @user,
      entity: nil,
      cookie_data: @cookie_data
    )

    # Service should handle error and return nil
    assert_nil referral
  end

  # Optional parameters
  test "create_referral works without cookie_data" do
    referral = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: @user,
      entity: @entity
    )

    assert_not_nil referral
    assert_instance_of Hash, referral.cookie_data
    assert_not_nil referral.cookie_data['created_at']
  end

  test "create_referral works with only entity (no user)" do
    referral = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: nil,
      entity: @entity,
      cookie_data: @cookie_data
    )

    assert_not_nil referral
    assert_nil referral.referred_user
    assert_equal @entity, referral.referred_entity
  end

  test "create_referral works with only user (no entity)" do
    referral = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: @user,
      entity: nil,
      cookie_data: @cookie_data
    )

    assert_not_nil referral
    assert_equal @user, referral.referred_user
    assert_nil referral.referred_entity
  end

  # Edge cases
  test "create_referral with different affiliates for different entities" do
    entity2 = Entity.create!(
      name: 'Second Entity',
      subdomain: 'second-entity',
      slug: 'second-entity',
      status: 'active'
    )

    # First referral with first affiliate
    referral1 = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: @user,
      entity: @entity,
      cookie_data: @cookie_data
    )

    # Second referral with different affiliate and entity
    silver_affiliate = affiliates(:silver_affiliate)
    referral2 = AffiliateReferralService.create_referral(
      referral_code: silver_affiliate.affiliate_code,
      user: @user,
      entity: entity2,
      cookie_data: @cookie_data
    )

    assert_not_nil referral1
    assert_not_nil referral2
    assert_not_equal referral1.affiliate, referral2.affiliate
  end
end
