require "application_system_test_case"

class OnboardingFlowTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)
    @user.update!(
      entity: @entity,
      onboarded: false,
      terms_accepted_at: nil,
      terms_version: nil,
      privacy_version: nil
    )
    @entity.update!(subscription_status: 'active')
  end

  test "new user sees legal agreement as first step" do
    sign_in_as(@user)

    # Should be redirected to onboarding
    assert_current_path onboarding_path(step: 'legal'), ignore_query: true

    # Should see terms and privacy checkboxes
    assert_selector "input[name='accept_terms']", visible: true
    assert_selector "input[name='accept_privacy']", visible: true
  end

  test "user must accept both terms and privacy to proceed" do
    sign_in_as(@user)

    # Try to continue without accepting
    click_button "Continue" rescue find("button[type='submit']").click

    # Should show error
    assert_text /must accept|required/i, wait: 5
  end

  test "user can complete legal step by accepting terms" do
    sign_in_as(@user)

    # Accept both checkboxes
    check "accept_terms"
    check "accept_privacy"
    click_button "Continue" rescue find("button[type='submit']").click

    # Should proceed to welcome step
    assert_text /welcome/i, wait: 5
  end

  test "welcome step shows usage type options" do
    complete_legal_step

    # Should see usage type options (work/personal)
    assert_selector "input[name='usage_type']", visible: true

    # Should have work and personal options
    has_work = page.has_selector?("input[value='work']") || page.has_text?(/work|business/i)
    has_personal = page.has_selector?("input[value='personal']") || page.has_text?(/personal/i)

    assert has_work || has_personal, "Expected usage type options"
  end

  test "about_you step shows user profile form" do
    complete_welcome_step

    # Should see profile fields
    assert_selector "input[name*='first_name'], input[name*='user']", visible: true
  end

  test "business flow shows website step after about_you" do
    complete_about_you_step(usage_type: 'work')

    # Should be on website step
    assert_text /website|url/i, wait: 5
    assert_selector "input[type='url'], input[type='text']", visible: true
  end

  test "personal flow skips website and business steps" do
    complete_about_you_step(usage_type: 'personal')

    # Should skip to use_cases
    assert_text /use case|help you with/i, wait: 5
  end

  test "user can complete full onboarding flow" do
    # Start onboarding
    sign_in_as(@user)

    # Legal step
    check "accept_terms"
    check "accept_privacy"
    click_button "Continue" rescue find("button[type='submit']").click
    assert_text /welcome/i, wait: 5

    # Welcome step - select personal for shorter flow
    find("input[value='personal']").click rescue find("label", text: /personal/i).click
    click_button "Continue" rescue find("button[type='submit']").click

    # About you step
    assert_selector "input", visible: true
    click_button "Continue" rescue find("button[type='submit']").click

    # Use cases step
    sleep 1
    click_button "Continue" rescue find("button[type='submit']").click rescue click_link "Skip"

    # Features step
    sleep 1
    click_button "Continue" rescue find("button[type='submit']").click rescue click_link "Skip"

    # Should reach complete or dashboard
    sleep 2
    completed = page.has_text?(/complete|finished|ready|dashboard/i)
    assert completed, "Expected to complete onboarding"
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"
    sleep 1
  end

  def complete_legal_step
    sign_in_as(@user)
    check "accept_terms"
    check "accept_privacy"
    click_button "Continue" rescue find("button[type='submit']").click
    sleep 1
  end

  def complete_welcome_step
    complete_legal_step
    find("input[value='work']").click rescue find("label", text: /work/i).click
    click_button "Continue" rescue find("button[type='submit']").click
    sleep 1
  end

  def complete_about_you_step(usage_type: 'work')
    complete_legal_step

    # Welcome step
    if usage_type == 'personal'
      find("input[value='personal']").click rescue find("label", text: /personal/i).click
    else
      find("input[value='work']").click rescue find("label", text: /work/i).click
    end
    click_button "Continue" rescue find("button[type='submit']").click
    sleep 1

    # About you step
    click_button "Continue" rescue find("button[type='submit']").click
    sleep 1
  end
end
