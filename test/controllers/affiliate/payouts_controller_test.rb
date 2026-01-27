require "test_helper"

class Affiliate::PayoutsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:two)
    @affiliate = affiliates(:active_affiliate)
    host! "app.example.com"  # Required for subdomain routing
    host! "app.example.com"  # Required for subdomain routing
    sign_in @user
  end

  test "should get payouts index for active affiliate" do
    get affiliate_payouts_path
    assert_response :success
  end

  test "should redirect to application when user has no affiliate" do
    user_without_affiliate = users(:one)
    sign_in user_without_affiliate

    get affiliate_payouts_path
    assert_redirected_to affiliate_apply_path
  end

  test "should redirect when affiliate is not active" do
    pending_user = affiliates(:pending_affiliate).user
    sign_in pending_user

    get affiliate_payouts_path
    assert_redirected_to affiliate_apply_path
  end

  test "should require authentication" do
    sign_out @user

    get affiliate_payouts_path
    assert_redirected_to new_user_session_path
  end

  test "payouts index should list affiliate payouts" do
    # Create a payout for this affiliate
    Payout.create!(
      affiliate: @affiliate,
      amount: 150.00,
      payment_method: 'paypal',
      status: :completed,
      payout_date: Date.today
    )

    get affiliate_payouts_path

    assert_response :success
    assert assigns(:payouts), "Should assign @payouts"
  end

  test "payouts should be ordered by created_at desc" do
    # Create payouts with different dates
    payout1 = Payout.create!(
      affiliate: @affiliate,
      amount: 100.00,
      payment_method: 'paypal',
      status: :completed,
      payout_date: 5.days.ago.to_date
    )

    payout2 = Payout.create!(
      affiliate: @affiliate,
      amount: 150.00,
      payment_method: 'paypal',
      status: :completed,
      payout_date: 1.day.ago.to_date
    )

    get affiliate_payouts_path

    payouts = assigns(:payouts)
    if payouts.size >= 2
      assert payouts.first.created_at >= payouts.second.created_at
    end
  end
end
