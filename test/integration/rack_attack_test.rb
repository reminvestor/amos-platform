require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    # Clear any existing throttles before each test
    Rack::Attack.cache.store.clear
  end

  teardown do
    # Clear throttles after each test
    Rack::Attack.cache.store.clear
  end

  # Story 0.1: API Login Rate Limiting Tests
  test "throttles API login after 5 attempts per email" do
    email = "test@example.com"

    # First 5 attempts should succeed (or return normal errors)
    5.times do
      post api_auth_login_url, params: {
        email: email,
        password: "wrongpassword"
      }, as: :json

      assert_response :unauthorized
    end

    # 6th attempt should be throttled
    post api_auth_login_url, params: {
      email: email,
      password: "wrongpassword"
    }, as: :json

    assert_response :too_many_requests
    assert_equal "Rate limit exceeded. Please try again later.",
                 JSON.parse(response.body)["error"]
  end

  test "throttles API login after 10 attempts per IP" do
    # Use different emails to bypass email-based throttle
    10.times do |i|
      post api_auth_login_url, params: {
        email: "user#{i}@example.com",
        password: "wrongpassword"
      }, as: :json

      assert_response :unauthorized
    end

    # 11th attempt from same IP should be throttled
    post api_auth_login_url, params: {
      email: "user11@example.com",
      password: "wrongpassword"
    }, as: :json

    assert_response :too_many_requests
  end

  test "throttles API registration after 3 attempts per IP" do
    # First 3 registration attempts
    3.times do |i|
      post api_auth_register_url, params: {
        email: "newuser#{i}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        first_name: "Test",
        last_name: "User"
      }, as: :json

      # Response can be success or error, we don't care for this test
      assert_response [:success, :created, :unprocessable_entity]
    end

    # 4th attempt should be throttled
    post api_auth_register_url, params: {
      email: "newuser4@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      first_name: "Test",
      last_name: "User"
    }, as: :json

    assert_response :too_many_requests
    assert_equal "Rate limit exceeded. Please try again later.",
                 JSON.parse(response.body)["error"]
  end

  test "throttled response includes Retry-After header" do
    email = "throttle-test@example.com"

    # Trigger throttle by exceeding limit
    6.times do
      post api_auth_login_url, params: {
        email: email,
        password: "wrongpassword"
      }, as: :json
    end

    assert_response :too_many_requests
    assert response.headers["Retry-After"].present?
  end

  test "different emails don't interfere with each other's rate limits" do
    email1 = "user1@example.com"
    email2 = "user2@example.com"

    # Max out email1's attempts
    5.times do
      post api_auth_login_url, params: {
        email: email1,
        password: "wrongpassword"
      }, as: :json
    end

    # email2 should still work (not throttled)
    post api_auth_login_url, params: {
      email: email2,
      password: "wrongpassword"
    }, as: :json

    assert_response :unauthorized  # Not throttled, just wrong password
  end

  test "API key usage has higher rate limit than login" do
    user = users(:one)
    user.generate_api_key!

    # Should be able to make 300 requests in 5 minutes
    # We'll test 20 to keep test fast
    20.times do
      get api_campaigns_url, headers: {
        "Authorization" => "Bearer #{user.api_key}"
      }, as: :json

      assert_response [:success, :ok, :not_found]  # Any non-throttled response
    end
  end

  test "throttle resets after period expires" do
    email = "reset-test@example.com"

    # Trigger throttle
    6.times do
      post api_auth_login_url, params: {
        email: email,
        password: "wrongpassword"
      }, as: :json
    end

    assert_response :too_many_requests

    # Simulate time passing (15 minutes)
    travel 16.minutes do
      # Should be able to login again
      post api_auth_login_url, params: {
        email: email,
        password: "wrongpassword"
      }, as: :json

      assert_response :unauthorized  # Normal error, not throttled
    end
  end
end
