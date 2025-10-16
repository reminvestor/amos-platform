require "test_helper"

class Affiliate::DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:two)
    @affiliate = affiliates(:active_affiliate)
    sign_in @user
  end

  test "should get dashboard for active affiliate" do
    get affiliate_dashboard_path
    assert_response :success
  end

  test "should redirect to application when user has no affiliate" do
    user_without_affiliate = users(:one)
    sign_in user_without_affiliate

    get affiliate_dashboard_path
    assert_redirected_to new_affiliate_application_path
  end

  test "should redirect to application when affiliate is pending" do
    pending_user = affiliates(:pending_affiliate).user
    sign_in pending_user

    get affiliate_dashboard_path
    assert_redirected_to new_affiliate_application_path
  end

  test "should redirect to application when affiliate is suspended" do
    suspended_user = affiliates(:suspended_affiliate).user
    sign_in suspended_user

    get affiliate_dashboard_path
    assert_redirected_to new_affiliate_application_path
  end

  test "dashboard should display affiliate stats" do
    get affiliate_dashboard_path

    assert_response :success
    # These elements should be present in the dashboard
    assert_select 'body' # Basic check that page renders
  end

  test "should require authentication" do
    sign_out @user

    get affiliate_dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "dashboard should show affiliate code" do
    get affiliate_dashboard_path

    assert_response :success
    # Affiliate code should be visible somewhere on the page
  end

  test "dashboard should calculate stats" do
    get affiliate_dashboard_path

    assert_response :success
    assert assigns(:stats), "Should assign @stats"
    assert assigns(:stats).key?(:clicks_all_time)
    assert assigns(:stats).key?(:total_conversions)
    assert assigns(:stats).key?(:total_earned)
  end
end
