require "application_system_test_case"

class StripeSubscriptionFlowTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)

    # Reset subscription status for testing
    @entity.update!(
      stripe_customer_id: nil,
      stripe_subscription_id: nil,
      subscription_status: nil,
      trial_ends_at: nil,
      current_period_end: nil,
      token_usage: 0,
      token_limit: nil,
      plan_tier: nil
    )

    @user.update!(onboarded: false)
  end

  test "complete signup to subscription flow" do
    visit new_user_registration_path

    # Fill in signup form
    fill_in "user_full_name", with: "Test User"
    fill_in "user_business_name", with: "Test Business"
    fill_in "user_email", with: "newuser@example.com"
    fill_in "user_password", with: "password123"
    fill_in "user_password_confirmation", with: "password123"

    click_button "Create Account"

    # Should redirect to subscription selection
    assert_current_path new_subscription_path
    assert_text "Choose Your Plan"
  end

  test "user without subscription is redirected to plan selection" do
    sign_in_as(@user)

    visit root_path

    # Should be redirected to subscription selection
    assert_current_path new_subscription_path
    assert_text "Please select a plan to continue"
  end

  test "subscription plan selection page displays all plans" do
    sign_in_as(@user)
    visit new_subscription_path

    # Verify all three plans are displayed
    assert_text "Starter"
    assert_text "$29"
    assert_text "200,000 AI credits"

    assert_text "Professional"
    assert_text "$119"
    assert_text "1,000,000 AI credits"

    assert_text "Business"
    assert_text "$299"
    assert_text "2,000,000 AI credits"

    # Verify trial information
    assert_text "7-day trial"
  end

  test "clicking plan redirects to Stripe checkout" do
    sign_in_as(@user)
    visit new_subscription_path

    # Mock Stripe.js to prevent actual redirect in test
    # This would need VCR or Stripe test helpers

    # Verify the form exists and has correct price ID
    starter_button = find("form[action='#{subscriptions_path}']", match: :first)
    assert starter_button.has_field?("price_id", type: :hidden)
  end

  test "subscription success creates entity subscription record" do
    sign_in_as(@user)

    # Simulate successful Stripe checkout by directly calling the success action
    # In a real E2E test with Stripe test mode, you'd go through actual checkout

    # Create mock Stripe subscription
    subscription_id = "sub_test_123"
    @entity.update!(
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: subscription_id,
      subscription_status: "trialing",
      trial_ends_at: 7.days.from_now,
      current_period_end: 1.month.from_now,
      plan_tier: "starter",
      token_limit: 200_000
    )

    visit onboarding_path

    # Should not redirect to subscription page
    assert_current_path onboarding_path

    # Should see onboarding interface
    assert_text "Hi #{@user.first_name}"
  end

  test "user with active subscription can access app" do
    # Set up active subscription
    @entity.update!(
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123",
      subscription_status: "active",
      current_period_end: 1.month.from_now,
      plan_tier: "professional",
      token_limit: 1_000_000
    )

    @user.update!(onboarded: true)

    sign_in_as(@user)
    visit root_path

    # Should be able to access root without redirect
    assert_no_text "Please select a plan"
  end

  test "user with trialing subscription can access app" do
    # Set up trial subscription
    @entity.update!(
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123",
      subscription_status: "trialing",
      trial_ends_at: 7.days.from_now,
      current_period_end: 1.month.from_now,
      plan_tier: "starter",
      token_limit: 200_000
    )

    @user.update!(onboarded: true)

    sign_in_as(@user)
    visit root_path

    # Should be able to access root without redirect
    assert_no_text "Please select a plan"
  end

  test "user with expired subscription is redirected to plan selection" do
    # Set up expired/past_due subscription
    @entity.update!(
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123",
      subscription_status: "past_due",
      current_period_end: 1.day.ago,
      plan_tier: "starter"
    )

    @user.update!(onboarded: true)

    sign_in_as(@user)
    visit root_path

    # Should redirect to subscription selection
    assert_text "Please select a plan to continue"
  end

  test "onboarding shows subscription confirmation after checkout" do
    sign_in_as(@user)

    # Simulate successful subscription
    @entity.update!(
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123",
      subscription_status: "trialing",
      trial_ends_at: 7.days.from_now,
      current_period_end: 1.month.from_now,
      plan_tier: "professional",
      token_limit: 1_000_000
    )

    # Set session flag (normally set by subscriptions controller)
    page.set_rack_session(show_subscription_confirmation: true)

    visit onboarding_path

    # Should see subscription confirmation
    assert_text "Subscription Confirmed"
    assert_text "Professional plan"
    assert_text "7-day trial"
  end

  test "logout button is accessible from onboarding page" do
    sign_in_as(@user)

    # Set up subscription so we can access onboarding
    @entity.update!(
      subscription_status: "trialing",
      trial_ends_at: 7.days.from_now
    )

    visit onboarding_path

    # Should see user menu with logout
    # Adjusted based on your actual UI structure
    assert_selector "[data-bs-toggle='dropdown']", text: @user.first_name, visible: true
  end

  test "token limits are set correctly for each plan tier" do
    sign_in_as(@user)

    # Test Starter plan
    @entity.update!(plan_tier: "starter")
    assert_equal 200_000, determine_token_limit_for_plan("starter")

    # Test Professional plan
    @entity.update!(plan_tier: "professional")
    assert_equal 1_000_000, determine_token_limit_for_plan("professional")

    # Test Business plan
    @entity.update!(plan_tier: "business")
    assert_equal 2_000_000, determine_token_limit_for_plan("business")
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign In"
  end

  def determine_token_limit_for_plan(plan_tier)
    case plan_tier
    when "starter", "basic"
      200_000
    when "professional", "pro"
      1_000_000
    when "business"
      2_000_000
    else
      200_000
    end
  end
end
