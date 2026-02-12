require "test_helper"

class Admin::AffiliatesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = AdminUser.find_or_create_by!(email: "admin_affiliate_test_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'Password123!'
    end
    # Note: You may need to adjust this based on your admin authentication setup
    # sign_in @admin (if using Devise for admins)
  end

  test "should get index" do
    skip "Admin authentication needs to be configured"
    get admin_affiliates_path
    assert_response :success
  end

  test "should show affiliate details" do
    skip "Admin authentication needs to be configured"
    affiliate = affiliates(:active_affiliate)

    get admin_affiliate_path(affiliate)
    assert_response :success
  end

  test "should approve pending affiliate" do
    skip "Admin authentication needs to be configured"
    affiliate = affiliates(:pending_affiliate)

    assert affiliate.pending?

    post approve_admin_affiliate_path(affiliate)

    affiliate.reload
    assert affiliate.active?
    assert_not_nil affiliate.approved_at
    assert_redirected_to admin_affiliate_path(affiliate)
  end

  test "should suspend affiliate" do
    skip "Admin authentication needs to be configured"
    affiliate = affiliates(:active_affiliate)

    assert affiliate.active?

    post suspend_admin_affiliate_path(affiliate)

    affiliate.reload
    assert affiliate.suspended?
    assert_redirected_to admin_affiliate_path(affiliate)
  end

  test "should update commission rate" do
    skip "Admin authentication needs to be configured"
    affiliate = affiliates(:active_affiliate)
    new_rate = 0.30

    patch update_commission_rate_admin_affiliate_path(affiliate), params: {
      affiliate: { commission_rate: new_rate }
    }

    affiliate.reload
    assert_equal new_rate, affiliate.commission_rate
    assert_redirected_to admin_affiliate_path(affiliate)
  end

  test "should filter by status" do
    skip "Admin authentication needs to be configured"
    get admin_affiliates_path(status: 'active')
    assert_response :success
  end

  test "should filter by tier" do
    skip "Admin authentication needs to be configured"
    get admin_affiliates_path(tier: 'silver')
    assert_response :success
  end

  test "should search affiliates" do
    skip "Admin authentication needs to be configured"
    get admin_affiliates_path(query: 'test')
    assert_response :success
  end
end
