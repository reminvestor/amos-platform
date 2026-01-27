require "test_helper"

class Affiliate::ApplicationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Use user without existing affiliate for application tests
    @user = users(:user_without_affiliate)
    host! "app.example.com"  # Required for subdomain routing
    sign_in @user
  end

  test "should get new when logged in" do
    get affiliate_apply_path
    assert_response :success
  end

  test "should create affiliate application" do
    assert_difference 'Affiliate.count', 1 do
      post affiliate_applications_path, params: {
        affiliate: {
          payment_email: 'new_affiliate@example.com',
          application_notes: 'I want to promote your product'
        }
      }
    end

    # After creation, user should be redirected to dashboard
    assert_redirected_to affiliate_dashboard_path
  end

  test "should redirect to dashboard if user already has affiliate" do
    # User with existing affiliate
    user_with_affiliate = users(:two)
    sign_in user_with_affiliate

    get affiliate_apply_path
    assert_redirected_to affiliate_dashboard_path
  end

  test "should require authentication" do
    sign_out @user

    get affiliate_apply_path
    assert_redirected_to new_user_session_path
  end

  test "should set default commission rate on creation" do
    post affiliate_applications_path, params: {
      affiliate: {
        payment_email: 'commission_test@example.com',
        application_notes: 'Test application'
      }
    }

    affiliate = Affiliate.last
    assert_equal 0.20, affiliate.commission_rate # Default 20% (per db schema)
  end

  test "should set status to pending on creation" do
    post affiliate_applications_path, params: {
      affiliate: {
        payment_email: 'pending_test@example.com',
        application_notes: 'Test application'
      }
    }

    affiliate = Affiliate.last
    assert affiliate.pending?
  end
end
