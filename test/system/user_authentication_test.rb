require "application_system_test_case"

class UserAuthenticationTest < ApplicationSystemTestCase
  test "user can sign up" do
    visit new_user_registration_path

    fill_in "First name", with: "Test"
    fill_in "Last name", with: "User"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    select "Marketer", from: "Role"

    click_button "Create Account"

    # Should be redirected to onboarding
    assert_current_path onboarding_path
    assert_text "Welcome"
  end

  test "user can sign in" do
    user = users(:one)

    visit new_user_session_path

    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"

    # Should see dashboard or onboarding
    assert_no_text "Invalid Email or password"
  end

  test "user can sign out" do
    user = users(:one)
    sign_in_as(user)

    click_on "Sign out" # Adjust based on your UI

    assert_current_path root_path
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"
  end
end
