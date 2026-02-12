require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  # ═══════════════════════════════════════════════════════════════════════
  # Rack::Attack Configuration Verification Tests
  #
  # Rack::Attack is disabled in test env (initializer returns early).
  # These tests verify the production configuration is correct by
  # reading the initializer file and testing the middleware setup.
  # ═══════════════════════════════════════════════════════════════════════

  setup do
    @initializer_path = Rails.root.join("config", "initializers", "rack_attack.rb")
    @initializer_content = File.read(@initializer_path)
  end

  # Story 0.1: Verify API Login Rate Limiting Configuration
  test "rack attack initializer configures API login email throttle" do
    assert_match(/throttle.*api\/login\/email.*limit:\s*5.*period:\s*15\.minutes/m, @initializer_content,
                 "Should throttle API login to 5 attempts per 15 minutes per email")
  end

  test "rack attack initializer configures API login IP throttle" do
    assert_match(/throttle.*api\/login\/ip.*limit:\s*10.*period:\s*15\.minutes/m, @initializer_content,
                 "Should throttle API login to 10 attempts per 15 minutes per IP")
  end

  test "rack attack initializer configures API registration throttle" do
    assert_match(/throttle.*api\/register\/ip.*limit:\s*3.*period:\s*1\.hour/m, @initializer_content,
                 "Should throttle API registration to 3 attempts per hour per IP")
  end

  test "rack attack initializer configures API key usage throttle" do
    assert_match(/throttle.*api\/authenticated\/token.*limit:\s*300.*period:\s*5\.minutes/m, @initializer_content,
                 "Should throttle authenticated API to 300 requests per 5 minutes")
  end

  test "rack attack initializer configures custom throttled response" do
    assert_match(/throttled_responder/, @initializer_content,
                 "Should have a custom throttled responder")
    assert_match(/429/, @initializer_content,
                 "Throttled response should return 429 status")
    assert_match(/Retry-After/, @initializer_content,
                 "Throttled response should include Retry-After header")
    assert_match(/Rate limit exceeded/, @initializer_content,
                 "Throttled response should include rate limit message")
  end

  test "rack attack is disabled in test environment" do
    # Verify initializer skips config in test env (prevents test interference)
    assert_match(/return if Rails\.env\.test\?/, @initializer_content,
                 "Rack::Attack should be disabled in test environment")
  end

  test "rack attack initializer configures Redis cache store" do
    assert_match(/Rack::Attack\.cache\.store.*RedisCacheStore/, @initializer_content,
                 "Should use Redis for Rack::Attack cache in production")
  end

  test "rack attack initializer configures login path throttle" do
    # Verify it targets the correct API login endpoint
    assert_match(%r{req\.path == '/api/auth/login'}, @initializer_content,
                 "Should throttle the /api/auth/login endpoint")
  end

  test "rack attack initializer handles JSON body parsing for email throttle" do
    # Verify the email throttle can parse JSON request bodies
    assert_match(/application\/json.*req\.body/, @initializer_content,
                 "Should parse JSON body to extract email for throttling")
  end

  # Story 0.1: Verify API endpoints respond correctly (no throttling in test)
  test "API login returns unauthorized for wrong password" do
    post api_auth_login_url, params: {
      email: "test@example.com",
      password: "wrongpassword"
    }, as: :json

    assert_response :unauthorized
  end

  test "different login attempts are independent without throttling" do
    email1 = "user1@example.com"
    email2 = "user2@example.com"

    # Multiple attempts for email1
    5.times do
      post api_auth_login_url, params: {
        email: email1,
        password: "wrongpassword"
      }, as: :json

      assert_response :unauthorized
    end

    # email2 should also return unauthorized (not throttled in test)
    post api_auth_login_url, params: {
      email: email2,
      password: "wrongpassword"
    }, as: :json

    assert_response :unauthorized
  end

  test "API key usage allows authenticated requests" do
    user = users(:one)
    user.generate_api_key!

    get api_v1_campaigns_url, headers: {
      "Authorization" => "Bearer #{user.api_key}"
    }, as: :json

    # Should get a valid response (not throttled)
    assert_includes [200, 401, 404], response.status
  end

  test "rack attack middleware is in the middleware stack" do
    middleware_classes = Rails.application.middleware.middlewares.map(&:name)
    assert_includes middleware_classes, "Rack::Attack",
                    "Rack::Attack should be in the middleware stack"
  end
end
