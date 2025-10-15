require "test_helper"

class Affiliate::ApplicationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    sign_in @user
  end

  test "should get new when logged in" do
    get new_affiliate_application_path
    assert_response :success
  end

  test "should create affiliate application" do
    assert_difference 'Affiliate.count', 1 do
      post affiliate_applications_path, params: {
        affiliate: {
          payment_email: 'affiliate@example.com',
          application_notes: 'I want to promote your product'
        }
      }
    end

    assert_redirected_to affiliate_dashboard_path
    follow_redirect!
    assert_match /application submitted/i, response.body
  end

  test "should not create duplicate affiliate application" do
    # Create first application
    post affiliate_applications_path, params: {
      affiliate: {
        payment_email: 'affiliate@example.com',
        application_notes: 'First application'
      }
    }

    # Try to create second application - should fail
    assert_no_difference 'Affiliate.count' do
      post affiliate_applications_path, params: {
        affiliate: {
          payment_email: 'affiliate@example.com',
          application_notes: 'Second application'
        }
      }
    end
  end

  test "should require authentication" do
    sign_out @user

    get new_affiliate_application_path
    assert_redirected_to new_user_session_path
  end

  test "should set default commission rate on creation" do
    post affiliate_applications_path, params: {
      affiliate: {
        payment_email: 'affiliate@example.com',
        application_notes: 'Test application'
      }
    }

    affiliate = Affiliate.last
    assert_equal 0.20, affiliate.commission_rate # Default 20%
  end

  test "should set status to pending on creation" do
    post affiliate_applications_path, params: {
      affiliate: {
        payment_email: 'affiliate@example.com',
        application_notes: 'Test application'
      }
    }

    affiliate = Affiliate.last
    assert affiliate.pending?
  end
end
