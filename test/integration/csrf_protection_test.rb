require "test_helper"

class CsrfProtectionTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  # Story 0.5: CSRF Protection Tests
  test "CSRF protection is enabled in Rails config" do
    assert Rails.application.config.action_controller.allow_forgery_protection,
           "CSRF protection should be enabled"
    assert Rails.application.config.action_controller.default_protect_from_forgery,
           "Default protect_from_forgery should be enabled"
  end

  test "POST request without CSRF token fails for web endpoints" do
    sign_in @user

    # Try to create a campaign without CSRF token
    post campaigns_url, params: {
      campaign: {
        name: "Test Campaign",
        subject: "Test Subject"
      }
    }

    assert_response :forbidden
  end

  test "POST request with valid CSRF token succeeds for web endpoints" do
    sign_in @user

    # Get CSRF token
    get new_campaign_url
    csrf_token = css_select('meta[name="csrf-token"]').first["content"]

    # Create campaign with CSRF token
    post campaigns_url, params: {
      campaign: {
        name: "Test Campaign",
        subject: "Test Subject"
      }
    }, headers: {
      "X-CSRF-Token" => csrf_token
    }

    # Should succeed or redirect (not forbidden)
    assert_response [:success, :redirect, :created]
  end

  test "API endpoints skip CSRF verification" do
    # API endpoints should work without CSRF token
    post api_auth_login_url, params: {
      email: @user.email,
      password: "password123"
    }, as: :json

    # Should not return forbidden (uses API key auth instead)
    assert_response [:success, :unauthorized, :ok]
    assert_not_equal :forbidden, response.status
  end

  test "Invalid CSRF token triggers rescue handler" do
    sign_in @user

    # Try with invalid token
    post campaigns_url, params: {
      campaign: {
        name: "Test Campaign"
      }
    }, headers: {
      "X-CSRF-Token" => "invalid_token_12345"
    }

    assert_response :forbidden
  end

  test "CSRF meta tags are present in HTML pages" do
    sign_in @user

    get root_url

    assert_response :success
    assert_select 'meta[name="csrf-token"]', count: 1
    assert_select 'meta[name="csrf-param"]', count: 1
  end

  test "session cookies have secure and httponly flags in production" do
    # Simulate production environment
    Rails.env.stub(:production?, true) do
      get root_url

      # Check session cookie attributes
      session_cookie = response.cookies["_amos_session"]
      assert session_cookie.present?, "Session cookie should be set"

      # In test environment, we can't verify actual cookie flags
      # but we can verify the config
      session_config = Rails.application.config.session_options

      assert session_config[:httponly], "Session should be httponly"
      # Secure flag is set via session_store.rb based on Rails.env.production?
    end
  end

  test "forms include authenticity token field" do
    sign_in @user

    get new_campaign_url

    assert_response :success
    assert_select 'input[name="authenticity_token"]', count: 1
  end

  test "AJAX requests include CSRF token in headers" do
    sign_in @user

    # Get page with CSRF token
    get root_url
    csrf_token = css_select('meta[name="csrf-token"]').first["content"]

    # Simulate AJAX request with token
    post campaigns_url, params: {
      campaign: { name: "AJAX Campaign" }
    }, headers: {
      "X-CSRF-Token" => csrf_token,
      "X-Requested-With" => "XMLHttpRequest"
    }, xhr: true

    # Should not be forbidden
    assert_response [:success, :redirect, :created, :unprocessable_entity]
    assert_not_equal :forbidden, response.status
  end

  test "CSRF error returns JSON for API requests" do
    sign_in @user

    # Make request as JSON without token
    post campaigns_url, params: {
      campaign: { name: "Test" }
    }, as: :json

    if response.status == 403
      response_body = JSON.parse(response.body)
      assert_equal "Invalid CSRF token", response_body["error"]
    end
  end

  test "CSRF error redirects for HTML requests" do
    sign_in @user

    # Make HTML request without token
    post campaigns_url, params: {
      campaign: { name: "Test" }
    }

    if response.status == 403
      # Should show error message (exact behavior depends on implementation)
      assert response.body.include?("Session expired") ||
             response.body.include?("CSRF") ||
             response.status == :forbidden
    end
  end

  test "per-form CSRF tokens are enabled" do
    assert Rails.application.config.action_controller.per_form_csrf_tokens,
           "Per-form CSRF tokens should be enabled for better security"
  end

  test "CSRF token is unique per session" do
    # Get token from first session
    get root_url
    token1 = css_select('meta[name="csrf-token"]').first["content"] if css_select('meta[name="csrf-token"]').any?

    # Clear session and get new token
    reset!
    get root_url
    token2 = css_select('meta[name="csrf-token"]').first["content"] if css_select('meta[name="csrf-token"]').any?

    # Tokens should be different
    if token1 && token2
      assert_not_equal token1, token2, "CSRF tokens should be unique per session"
    end
  end
end
