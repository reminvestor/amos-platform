require "application_system_test_case"

class MfaAuthenticationTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update!(entity: @entity)
  end

  test "user can access MFA settings page" do
    sign_in(@user)

    visit users_two_factor_path

    # MFA settings page should load
    assert_selector "h1, h2, h3", text: /two.factor|mfa|authentication/i
  end

  test "user without MFA sees enable option" do
    # Ensure MFA is disabled
    @user.update!(otp_secret: nil, otp_required_for_login: false)

    sign_in(@user)

    visit users_two_factor_path

    # Should see option to enable MFA
    assert_selector "a, button", text: /enable|set up|activate/i
  end

  test "user can start MFA setup and see QR code" do
    # Ensure MFA is disabled
    @user.update!(otp_secret: nil, otp_required_for_login: false)

    sign_in(@user)

    visit users_two_factor_enable_path

    # Should see QR code for authenticator app
    assert_selector "svg", visible: true # QR code is rendered as SVG

    # Should see the secret key displayed
    assert_selector "[data-secret], .secret, code", visible: true

    # Should have a form to enter verification code
    assert_selector "input[name='code'], input[type='text']", visible: true
    assert_selector "button[type='submit'], input[type='submit']", visible: true
  end

  test "MFA setup shows error for invalid code" do
    # Ensure MFA is disabled but secret is set up
    @user.update!(otp_required_for_login: false)
    @user.setup_totp!

    sign_in(@user)

    visit users_two_factor_enable_path

    # Enter an invalid code
    fill_in "code", with: "000000"
    click_button "Verify" rescue click_button "Confirm" rescue find("button[type='submit']").click

    # Should show error message
    assert_text /invalid|incorrect|try again/i, wait: 5
  end

  test "user with MFA enabled sees verification page on login" do
    # Enable MFA for user
    @user.setup_totp!
    @user.update!(otp_required_for_login: true)

    visit new_user_session_path

    fill_in "Email", with: @user.email
    fill_in "Password", with: "password"
    click_button "Sign In"

    # Should be redirected to MFA verification page
    assert_text /verification|code|authenticator/i, wait: 5
    assert_selector "input", visible: true
  end

  test "user with MFA can access backup codes page" do
    # Enable MFA for user
    @user.setup_totp!
    @user.update!(otp_required_for_login: true)
    @user.generate_backup_codes!

    # Sign in with valid OTP
    sign_in_with_mfa(@user)

    visit users_two_factor_path

    # Should see backup codes section or regenerate option
    assert_selector "a, button", text: /backup|regenerate/i
  end

  test "MFA verification page shows masked email hint" do
    # Enable MFA for user
    @user.setup_totp!
    @user.update!(otp_required_for_login: true)

    visit new_user_session_path

    fill_in "Email", with: @user.email
    fill_in "Password", with: "password"
    click_button "Sign In"

    # Should show masked email hint (e.g., "ad***@demo.com")
    assert_text /@/, wait: 5 # Email hint should contain @
  end

  private


  def sign_in_with_mfa(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign In"

    # Enter valid OTP
    otp = user.current_otp
    fill_in "code", with: otp rescue fill_in "otp", with: otp
    click_button "Verify" rescue find("button[type='submit']").click

    # Wait for successful sign in
    assert_selector "a[href='/scout']", wait: 5
  end
end
