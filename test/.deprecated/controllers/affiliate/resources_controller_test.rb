require "test_helper"

class Affiliate::ResourcesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:two)
    @affiliate = affiliates(:active_affiliate)
    host! "app.example.com"  # Required for subdomain routing
    sign_in @user
  end

  test "should get resources index for active affiliate" do
    get affiliate_resources_path
    assert_response :success
  end

  test "should redirect to application when user has no affiliate" do
    user_without_affiliate = users(:one)
    sign_in user_without_affiliate

    get affiliate_resources_path
    assert_redirected_to affiliate_apply_path
  end

  test "should redirect when affiliate is not active" do
    pending_user = affiliates(:pending_affiliate).user
    sign_in pending_user

    get affiliate_resources_path
    assert_redirected_to affiliate_apply_path
  end

  test "should require authentication" do
    sign_out @user

    get affiliate_resources_path
    assert_redirected_to new_user_session_path
  end

  test "resources page should display marketing materials" do
    get affiliate_resources_path

    assert_response :success
    # Page should render successfully
  end
end
