require "test_helper"

module Api
  class AuthControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @entity = entities(:one)
      @user.update!(entity: @entity, api_key: SecureRandom.hex(32))
    end

    # ====================================================================
    # LOGIN Tests
    # ====================================================================

    test "should login with valid credentials" do
      post api_auth_login_path, params: {
        email: @user.email,
        password: "password123"
      }, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("user")
      assert response_body.key?("api_key")
      assert response_body.key?("token")
    end

    test "login response includes user details" do
      post api_auth_login_path, params: {
        email: @user.email,
        password: "password123"
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
      post api_auth_login_path, params: {
        email: @user.email,
        password: "password123"
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
        password: "password123"
      }, as: :json

      assert_response :unauthorized
    end

    test "should reject login with blank email" do
      post api_auth_login_path, params: {
        email: "",
        password: "password123"
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
      post api_auth_refresh_token_path,
        headers: { "Authorization" => "Bearer #{@user.api_key}" },
        as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("token")
    end

    test "should reject token refresh without authentication" do
      post api_auth_refresh_token_path, as: :json

      assert_response :unauthorized
    end

    test "should reject token refresh with invalid token" do
      post api_auth_refresh_token_path,
        headers: { "Authorization" => "Bearer invalid_token" },
        as: :json

      assert_response :unauthorized
    end
  end
end
