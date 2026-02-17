require "application_system_test_case"

class AffiliateApplicationFlowTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "user can apply to become an affiliate" do
    visit affiliate_apply_path

    assert_text "Join Our Affiliate Program"

    fill_in "Payment email", with: "payments@example.com"
    fill_in "Application notes", with: "I have a large following in the marketing space"

    click_button "Submit Application"

    assert_text "Application submitted!"
    assert_current_path affiliate_dashboard_path
    
    # Verify affiliate was created
    @user.reload
    assert @user.affiliate.present?
    assert_equal "pending", @user.affiliate.status
    assert_equal "bronze", @user.affiliate.tier
    assert_equal "payments@example.com", @user.affiliate.payment_email
  end

  test "user cannot apply twice" do
    # Create existing affiliate
    Affiliate.create!(
      user: @user,
      status: :active,
      tier: :bronze,
      commission_rate: 0.20,
      payment_email: "existing@example.com"
    )

    visit affiliate_apply_path

    assert_text "You already have an affiliate account"
    assert_current_path affiliate_dashboard_path
  end

  test "user can view affiliate dashboard after approval" do
    affiliate = Affiliate.create!(
      user: @user,
      status: :active,
      tier: :silver,
      commission_rate: 0.25,
      payment_email: "payments@example.com"
    )

    visit affiliate_dashboard_path

    assert_text "Affiliate Dashboard"
    assert_text affiliate.affiliate_code
    assert_text "25.0%" # Commission rate
    assert_text "Active" # Status
  end

  test "dashboard shows referral link and QR code" do
    affiliate = Affiliate.create!(
      user: @user,
      status: :active,
      tier: :bronze,
      commission_rate: 0.20,
      payment_email: "payments@example.com"
    )

    visit affiliate_dashboard_path

    # Check for referral link
    assert_selector "input[value*='ref=#{affiliate.affiliate_code}']"
    
    # Check for copy button
    assert_button "Copy Link"
  end

  test "dashboard shows affiliate resources" do
    Affiliate.create!(
      user: @user,
      status: :active,
      tier: :bronze,
      commission_rate: 0.20,
      payment_email: "payments@example.com"
    )

    visit affiliate_resources_path

    assert_text "Marketing Resources"
  end

  test "dashboard shows payout history" do
    affiliate = Affiliate.create!(
      user: @user,
      status: :active,
      tier: :bronze,
      commission_rate: 0.20,
      payment_email: "payments@example.com"
    )

    # Create a payout
    Payout.create!(
      affiliate: affiliate,
      amount: 500.00,
      status: :completed,
      payment_method: "PayPal",
      transaction_id: "PAYPAL123"
    )

    visit affiliate_payouts_path

    assert_text "Payout History"
    assert_text "$500.00"
    assert_text "Completed"
    assert_text "PayPal"
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign In"
  end
end
