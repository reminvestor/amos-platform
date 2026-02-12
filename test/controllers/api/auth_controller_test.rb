require "test_helper"

module Api
  class AuthControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @entity = entities(:one)
      @user.update!(entity: @entity)
      @user.generate_api_key!
    end

    # ====================================================================
    # LOGIN Tests
    # ====================================================================

    test "should login with valid credentials" do
      # Set password explicitly for test (fixture has bcrypt hash)
      @user.update!(password: "Password123!")

      post api_auth_login_path, params: {
        email: @user.email,
        password: "Password123!"
      }, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("user")
      assert response_body.key?("api_key")
      assert response_body.key?("token")
    end

    test "login response includes user details" do
      @user.update!(password: "Password123!")

      post api_auth_login_path, params: {
        email: @user.email,
        password: "Password123!"
      }, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      user_data = response_body["user"]

      assert_equal @user.id, user_data["id"]
      assert_equal @user.email, user_data["email"]
      assert_equal @user.first_name, user_data["first_name"]
      assert_equal @user.last_name, user_data["last_name"]
      assert user_data.key?("entity_id")
      assert user_data.key?("entity_name")
      assert user_data.key?("role")
    end

    test "login response includes entity name" do
      @user.update!(password: "Password123!")

      post api_auth_login_path, params: {
        email: @user.email,
        password: "Password123!"
      }, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal @entity.name, response_body["user"]["entity_name"]
    end

    test "should reject login with invalid password" do
      post api_auth_login_path, params: {
        email: @user.email,
        password: "wrongpassword"
      }, as: :json

      assert_response :unauthorized

      response_body = JSON.parse(response.body)
      assert response_body.key?("message")
    end

    test "should reject login with non-existent email" do
      post api_auth_login_path, params: {
        email: "nonexistent@test.com",
        password: "Password123!"
      }, as: :json

      assert_response :unauthorized
    end

    test "should reject login with blank email" do
      post api_auth_login_path, params: {
        email: "",
        password: "Password123!"
      }, as: :json

      assert_response :unauthorized
    end

    test "should reject login with blank password" do
      post api_auth_login_path, params: {
        email: @user.email,
        password: ""
      }, as: :json

      assert_response :unauthorized
    end

    # ====================================================================
    # TOKEN REFRESH Tests
    # ====================================================================

    test "should refresh token for authenticated user" do
      @user.generate_refresh_token!

      post api_auth_refresh_token_path,
        params: { refresh_token: @user.refresh_token },
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("api_key")
      assert response_body.key?("refresh_token")
    end

    test "should reject token refresh without refresh token" do
      post api_auth_refresh_token_path, as: :json

      assert_response :bad_request
    end

    test "should reject token refresh with invalid token" do
      post api_auth_refresh_token_path,
        params: { refresh_token: "invalid_refresh_token" },
        as: :json

      assert_response :unauthorized
    end

    # ====================================================================
    # ME Endpoint Tests (Mobile App Auth Check)
    # ====================================================================

    test "should get current user with valid token" do
      get api_auth_me_path,
        headers: { "Authorization" => "Bearer #{@user.api_key}" },
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("user")
      assert_equal @user.id, response_body["user"]["id"]
      assert_equal @user.email, response_body["user"]["email"]
    end

    test "me endpoint returns user details" do
      get api_auth_me_path,
        headers: { "Authorization" => "Bearer #{@user.api_key}" },
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      user_data = response_body["user"]

      assert_equal @user.first_name, user_data["first_name"]
      assert_equal @user.last_name, user_data["last_name"]
      assert_equal @user.entity_id, user_data["entity_id"]
      assert_equal @entity.name, user_data["entity_name"]
      assert_equal @user.role, user_data["role"]
    end

    test "me endpoint returns combined name" do
      get api_auth_me_path,
        headers: { "Authorization" => "Bearer #{@user.api_key}" },
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      expected_name = "#{@user.first_name} #{@user.last_name}".strip
      assert_equal expected_name, response_body["user"]["name"]
    end

    test "me endpoint requires authentication" do
      get api_auth_me_path, as: :json

      assert_response :unauthorized
    end

    test "me endpoint rejects invalid token" do
      get api_auth_me_path,
        headers: { "Authorization" => "Bearer invalid_token" },
        as: :json

      assert_response :unauthorized
    end

    test "me endpoint rejects expired/revoked token" do
      old_api_key = @user.api_key
      @user.update!(api_key: SecureRandom.hex(32))  # Regenerate token

      # Clear the cache since we changed the token
      Rails.cache.delete("api_user:#{old_api_key}")

      get api_auth_me_path,
        headers: { "Authorization" => "Bearer #{old_api_key}" },
        as: :json

      assert_response :unauthorized
    end
  end
end
