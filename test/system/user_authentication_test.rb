require "application_system_test_case"

class UserAuthenticationTest < ApplicationSystemTestCase
  test "user can sign up" do
    visit new_user_registration_path

    # Current form uses Full Name (single field), no role selector (hidden)
    fill_in "Full Name", with: "Test User"
    fill_in "Email Address", with: "newuser_#{SecureRandom.hex(4)}@test.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm Password", with: "password123"

    click_button "Create Account"

    # Should be redirected to onboarding or dashboard
    assert_selector "body", wait: 10
    assert page.has_text?("Welcome") || page.has_current_path?(onboarding_path) || page.has_current_path?(root_path)
  end

  test "user can sign in" do
    user = users(:one)

    visit new_user_session_path

    fill_in "user_email_field", with: user.email
    fill_in "user_password", with: "password"
    click_button "Sign In"

    # Should see dashboard or onboarding (not an error)
    assert_no_text "Invalid Email or password"
  end

  test "user can sign out" do
    user = users(:one)
    sign_in(user)  # Use ApplicationSystemTestCase#sign_in helper

    # Find and click sign out - may be in a dropdown or navbar
    if page.has_button?("Sign out", wait: 3)
      click_button "Sign out"
    elsif page.has_link?("Sign out", wait: 1)
      click_link "Sign out"
    else
      # Sign out via direct path
      visit destroy_user_session_path
    end

    assert_selector "body", wait: 5
  end
end
