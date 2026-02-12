require "test_helper"

class Api::AuthControllerSecurityTest < ActionDispatch::IntegrationTest
  # Story 0.1: Account Lockout Tests (API Level)
  test "login returns locked status after 5 failed attempts" do
    user = users(:one)

    # Simulate 5 failed login attempts
    5.times { user.increment_failed_login! }

    post api_auth_login_url, params: {
      email: user.email,
      password: "wrongpassword"
    }, as: :json

    assert_response :locked
    assert_equal "Account temporarily locked due to multiple failed login attempts. Please try again in 30 minutes.",
                 JSON.parse(response.body)["message"]
  end

  test "successful login resets failed attempts counter" do
    # Create user with known password
    user = User.create!(
      email: 'resettest@example.com',
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      first_name: 'Test',
      last_name: 'User',
      entity: entities(:one)
    )

    # Simulate some failed attempts
    3.times { user.increment_failed_login! }
    assert_equal 3, user.reload.failed_login_attempts

    # Successful login
    post api_auth_login_url, params: {
      email: user.email,
      password: "TestPassword123!"
    }, as: :json

    assert_response :success
    assert_equal 0, user.reload.failed_login_attempts
    assert_nil user.last_failed_login_at
  end

  test "failed login increments failed attempts counter" do
    user = users(:one)
    initial_attempts = user.failed_login_attempts || 0

    post api_auth_login_url, params: {
      email: user.email,
      password: "wrongpassword"
    }, as: :json

    assert_response :unauthorized
    assert_equal initial_attempts + 1, user.reload.failed_login_attempts
    assert_not_nil user.last_failed_login_at
  end

  # Story 0.2: User Enumeration Prevention Tests
  test "registration returns generic error for existing email" do
    existing_user = users(:one)

    post api_auth_register_url, params: {
      email: existing_user.email,
      password: "NewPassword123!",
      password_confirmation: "NewPassword123!",
      first_name: "Test",
      last_name: "User"
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "Unable to create account. Please check your information and try again.",
                 JSON.parse(response.body)["message"]
  end

  test "registration returns generic error for password validation failure" do
    post api_auth_register_url, params: {
      email: "newuser@example.com",
      password: "weak",
      password_confirmation: "weak",
      first_name: "Test",
      last_name: "User"
    }, as: :json

    assert_response :unprocessable_entity
    # Should NOT reveal specific password requirements
    assert_equal "Unable to create account. Please check your information and try again.",
                 JSON.parse(response.body)["message"]
  end

  test "login returns same error for non-existent user and wrong password" do
    # Non-existent user
    post api_auth_login_url, params: {
      email: "nonexistent@example.com",
      password: "anypassword"
    }, as: :json

    assert_response :unauthorized
    nonexistent_error = JSON.parse(response.body)["message"]

    # Existing user with wrong password
    post api_auth_login_url, params: {
      email: users(:one).email,
      password: "wrongpassword"
    }, as: :json

    assert_response :unauthorized
    wrong_password_error = JSON.parse(response.body)["message"]

    # Errors must be identical
    assert_equal nonexistent_error, wrong_password_error
    assert_equal "Invalid email or password", nonexistent_error
  end

  # Story 0.4: API Key Expiration Tests (API Level)
  test "login returns api_key with expiration timestamp" do
    # Create user with known password
    user = User.create!(
      email: 'expirytest@example.com',
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      first_name: 'Test',
      last_name: 'User',
      entity: entities(:one)
    )

    post api_auth_login_url, params: {
      email: user.email,
      password: "TestPassword123!"
    }, as: :json

    assert_response :success
    response_data = JSON.parse(response.body)

    assert response_data["api_key"].present?
    assert response_data["api_key_expires_at"].present?
    assert response_data["refresh_token"].present?
    assert response_data["refresh_token_expires_at"].present?
  end

  test "expired api_key returns unauthorized with expired flag" do
    user = users(:one)
    user.generate_api_key!
    user.update!(api_key_expires_at: 1.day.ago)

    get "/api/v1/campaigns", headers: {
      "Authorization" => "Bearer #{user.api_key}"
    }, as: :json

    assert_response :unauthorized
    response_data = JSON.parse(response.body)
    assert response_data["message"].present?, "Should have error message"
  end

  test "refresh_token endpoint generates new tokens" do
    user = users(:one)
    user.generate_api_key!
    user.generate_refresh_token!
    old_api_key = user.api_key
    old_refresh_token = user.refresh_token

    post "/api/auth/refresh_token", params: {
      refresh_token: old_refresh_token
    }, as: :json

    assert_response :success
    response_data = JSON.parse(response.body)

    assert response_data["api_key"].present?
    assert response_data["refresh_token"].present?

    user.reload
    assert_not_equal old_api_key, user.api_key
    assert_not_equal old_refresh_token, user.refresh_token
  end

  test "refresh_token endpoint rejects invalid token" do
    post "/api/auth/refresh_token", params: {
      refresh_token: "invalid_token_12345"
    }, as: :json

    assert_response :unauthorized
    assert_equal "Invalid or expired refresh token", JSON.parse(response.body)["message"]
  end

  test "refresh_token endpoint rejects expired token" do
    user = users(:one)
    user.generate_api_key!
    user.generate_refresh_token!
    user.update!(refresh_token_expires_at: 1.day.ago)

    post "/api/auth/refresh_token", params: {
      refresh_token: user.refresh_token
    }, as: :json

    assert_response :unauthorized
    assert_equal "Invalid or expired refresh token", JSON.parse(response.body)["message"]
  end

  test "api_key is encrypted in database" do
    user = users(:one)
    user.generate_api_key!

    # Read raw database value
    raw_value = ActiveRecord::Base.connection.execute(
      "SELECT api_key FROM users WHERE id = #{user.id}"
    ).first["api_key"]

    # Encrypted value should not match plaintext
    assert_not_equal user.api_key, raw_value
    # Encrypted value should be present (not nil)
    assert raw_value.present?
  end
end
