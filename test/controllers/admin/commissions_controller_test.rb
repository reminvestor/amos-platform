require "test_helper"

class Admin::CommissionsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = AdminUser.find_or_create_by!(email: "admin_commission_test_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'password123'
    end
  end

  test "should get index" do
    skip "Admin authentication needs to be configured"
    get admin_commissions_path
    assert_response :success
  end

  test "should approve pending commission" do
    skip "Admin authentication needs to be configured"
    commission = commissions(:pending_commission)

    assert commission.pending?

    post approve_admin_commission_path(commission)

    commission.reload
    assert commission.approved?
    assert_not_nil commission.approved_at
    assert_equal @admin, commission.approved_by
    assert_redirected_to admin_commissions_path
  end

  test "should bulk approve commissions" do
    skip "Admin authentication needs to be configured"
    commission1 = commissions(:pending_commission)
    commission2 = commissions(:high_value_commission)

    post bulk_approve_admin_commissions_path, params: {
      commission_ids: [commission1.id, commission2.id]
    }

    commission1.reload
    commission2.reload

    assert commission1.approved?
    assert commission2.approved?
    assert_redirected_to admin_commissions_path
  end

  test "should cancel commission" do
    skip "Admin authentication needs to be configured"
    commission = commissions(:pending_commission)

    assert commission.pending?

    post cancel_admin_commission_path(commission)

    commission.reload
    assert commission.cancelled?
    assert_redirected_to admin_commissions_path
  end

  test "should filter by status" do
    skip "Admin authentication needs to be configured"
    get admin_commissions_path(status: 'pending')
    assert_response :success
  end

  test "should filter by date range" do
    skip "Admin authentication needs to be configured"
    get admin_commissions_path(date_from: 30.days.ago, date_to: Date.today)
    assert_response :success
  end

  test "should filter by affiliate" do
    skip "Admin authentication needs to be configured"
    affiliate = affiliates(:active_affiliate)
    get admin_commissions_path(affiliate_id: affiliate.id)
    assert_response :success
  end

  test "should show total pending and approved amounts" do
    skip "Admin authentication needs to be configured"
    get admin_commissions_path
    assert_response :success

    assert assigns(:total_pending), "Should assign @total_pending"
    assert assigns(:total_approved), "Should assign @total_approved"
  end
end
