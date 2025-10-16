require "test_helper"

class AffiliateTrackingFlowTest < ActionDispatch::IntegrationTest
  def setup
    @affiliate = affiliates(:active_affiliate)
  end

  test "complete affiliate tracking flow: visit with ref -> signup -> referral created" do
    # Step 1: Visit page with affiliate ref parameter
    get root_path(ref: @affiliate.affiliate_code)
    assert_response :success

    # Step 2: Cookie should be set
    assert cookies.signed[:affiliate_ref].present?
    assert_equal @affiliate.affiliate_code, cookies.signed[:affiliate_ref]

    # Step 3: Click should be logged
    click = AffiliateClick.last
    assert_equal @affiliate.id, click.affiliate_id
    assert_equal @affiliate.affiliate_code, click.referral_code

    # Step 4: User signs up
    assert_difference 'User.count', 1 do
      assert_difference 'Entity.count', 1 do
        post user_registration_path, params: {
          user: {
            email: 'newuser@example.com',
            password: 'password123',
            password_confirmation: 'password123',
            first_name: 'New',
            last_name: 'User'
          }
        }
      end
    end

    new_user = User.find_by(email: 'newuser@example.com')
    assert_not_nil new_user

    # Step 5: Referral should be created
    referral = Referral.find_by(referred_user: new_user)
    assert_not_nil referral
    assert_equal @affiliate, referral.affiliate
    assert_equal @affiliate.affiliate_code, referral.referral_code_used
    assert referral.pending?

    # Step 6: Cookie should be cleared after signup
    # (This depends on implementation - you may want to test this)
  end

  test "click is tracked with metadata" do
    utm_params = {
      utm_source: 'twitter',
      utm_medium: 'social',
      utm_campaign: 'spring_promo'
    }

    get root_path(ref: @affiliate.affiliate_code, **utm_params)

    click = AffiliateClick.last
    assert_equal 'twitter', click.metadata['utm_source']
    assert_equal 'social', click.metadata['utm_medium']
    assert_equal 'spring_promo', click.metadata['utm_campaign']
  end

  test "click tracks IP address and user agent" do
    get root_path(ref: @affiliate.affiliate_code)

    click = AffiliateClick.last
    assert_not_nil click.ip_address
    assert_not_nil click.user_agent
    assert_not_nil click.landed_at
  end

  test "invalid ref code does not create click" do
    initial_count = AffiliateClick.count

    get root_path(ref: 'INVALID123')

    assert_equal initial_count, AffiliateClick.count
  end

  test "suspended affiliate does not track clicks" do
    suspended = affiliates(:suspended_affiliate)
    initial_count = AffiliateClick.count

    get root_path(ref: suspended.affiliate_code)

    assert_equal initial_count, AffiliateClick.count
  end

  test "cookie persists across multiple page visits" do
    get root_path(ref: @affiliate.affiliate_code)
    assert cookies.signed[:affiliate_ref].present?

    # Visit another page - cookie should still be set
    get about_path
    assert_equal @affiliate.affiliate_code, cookies.signed[:affiliate_ref]
  end

  test "duplicate referrals are prevented" do
    # Create user and entity
    user = User.create!(
      email: 'test@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'Test',
      last_name: 'User'
    )

    entity = Entity.create!(
      name: 'Test Entity',
      subdomain: 'test',
      slug: 'test',
      status: 'active'
    )

    # Create first referral
    referral1 = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: user,
      entity: entity,
      cookie_data: {}
    )

    assert_not_nil referral1

    # Try to create duplicate - should return existing one
    referral2 = AffiliateReferralService.create_referral(
      referral_code: @affiliate.affiliate_code,
      user: user,
      entity: entity,
      cookie_data: {}
    )

    assert_equal referral1.id, referral2.id
  end
end
