# frozen_string_literal: true

require "test_helper"

module Api
  class MfaControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @entity = entities(:one)
      @user.update!(entity: @entity, password: "Password123!")
      @user.generate_api_key!
    end

    # ====================================================================
    # Helper Methods
    # ====================================================================

    def auth_headers
      { "Authorization" => "Bearer #{@user.api_key}" }
    end

    # ====================================================================
    # STATUS Tests
    # ====================================================================

    test "should get MFA status with valid token" do
      get api_status_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("mfa_enabled")
      assert response_body.key?("backup_codes_remaining")
      assert response_body.key?("email_otp_enabled")
    end

    test "MFA status shows disabled when not enabled" do
      @user.update!(otp_required_for_login: false, otp_secret: nil)

      get api_status_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal false, response_body["mfa_enabled"]
    end

    test "status requires authentication" do
      get api_status_path, as: :json

      assert_response :unauthorized
    end

    test "status rejects invalid token" do
      get api_status_path,
        headers: { "Authorization" => "Bearer invalid_token" },
        as: :json

      assert_response :unauthorized
    end

    # ====================================================================
    # ENABLE Tests
    # ====================================================================

    test "should enable MFA setup with valid token" do
      @user.update!(otp_required_for_login: false, otp_secret: nil)

      post api_enable_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("secret")
      assert response_body.key?("otp_uri")
      assert response_body.key?("message")
    end

    test "enable returns otpauth URI format" do
      @user.update!(otp_required_for_login: false, otp_secret: nil)

      post api_enable_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body["otp_uri"].start_with?("otpauth://totp/")
    end

    test "enable fails if MFA already enabled" do
      @user.update!(otp_required_for_login: true, otp_secret: ROTP::Base32.random)

      post api_enable_path, headers: auth_headers, as: :json

      assert_response :unprocessable_entity

      response_body = JSON.parse(response.body)
      assert response_body["message"].include?("already enabled")
    end

    test "enable requires authentication" do
      post api_enable_path, as: :json

      assert_response :unauthorized
    end

    # ====================================================================
    # CONFIRM Tests
    # ====================================================================

    test "should confirm MFA with valid code" do
      # Setup MFA
      secret = ROTP::Base32.random
      @user.update!(otp_required_for_login: false, otp_secret: secret)

      # Generate valid TOTP code
      totp = ROTP::TOTP.new(secret)
      valid_code = totp.now

      post api_confirm_path, params: { code: valid_code }, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal true, response_body["success"]
      assert response_body.key?("backup_codes")
      assert_equal true, response_body["mfa_enabled"]

      @user.reload
      assert @user.mfa_enabled?
    end

    test "confirm fails without code" do
      post api_confirm_path, headers: auth_headers, as: :json

      assert_response :unprocessable_entity

      response_body = JSON.parse(response.body)
      assert response_body["message"].include?("required")
    end

    test "confirm fails with invalid code" do
      secret = ROTP::Base32.random
      @user.update!(otp_required_for_login: false, otp_secret: secret)

      post api_confirm_path, params: { code: "000000" }, headers: auth_headers, as: :json

      assert_response :unprocessable_entity

      response_body = JSON.parse(response.body)
      assert_equal false, response_body["success"]
    end

    test "confirm requires authentication" do
      post api_confirm_path, params: { code: "123456" }, as: :json

      assert_response :unauthorized
    end

    # ====================================================================
    # DISABLE Tests
    # ====================================================================

    test "should disable MFA with valid password" do
      @user.update!(otp_required_for_login: true, otp_secret: ROTP::Base32.random)

      delete api_disable_path, params: { password: "Password123!" }, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal true, response_body["success"]

      @user.reload
      assert_not @user.mfa_enabled?
    end

    test "disable fails without password" do
      delete api_disable_path, headers: auth_headers, as: :json

      assert_response :unprocessable_entity

      response_body = JSON.parse(response.body)
      assert response_body["message"].include?("Password is required")
    end

    test "disable fails with incorrect password" do
      @user.update!(otp_required_for_login: true, otp_secret: ROTP::Base32.random)

      delete api_disable_path, params: { password: "wrongpassword" }, headers: auth_headers, as: :json

      assert_response :unauthorized

      response_body = JSON.parse(response.body)
      assert_equal false, response_body["success"]
    end

    test "disable requires authentication" do
      delete api_disable_path, params: { password: "Password123!" }, as: :json

      assert_response :unauthorized
    end

    # ====================================================================
    # REGENERATE_BACKUP_CODES Tests
    # ====================================================================

    test "should regenerate backup codes with valid password" do
      @user.update!(otp_required_for_login: true, otp_secret: ROTP::Base32.random, otp_backup_codes: ["code1", "code2"])

      post api_regenerate_backup_codes_path, params: { password: "Password123!" }, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal true, response_body["success"]
      assert response_body.key?("backup_codes")
      assert response_body["backup_codes"].is_a?(Array)
    end

    test "regenerate fails if MFA not enabled" do
      @user.update!(otp_required_for_login: false, otp_secret: nil)

      post api_regenerate_backup_codes_path, params: { password: "Password123!" }, headers: auth_headers, as: :json

      assert_response :unprocessable_entity

      response_body = JSON.parse(response.body)
      assert response_body["message"].include?("not enabled")
    end

    test "regenerate fails without password" do
      @user.update!(otp_required_for_login: true, otp_secret: ROTP::Base32.random)

      post api_regenerate_backup_codes_path, headers: auth_headers, as: :json

      assert_response :unprocessable_entity

      response_body = JSON.parse(response.body)
      assert response_body["message"].include?("Password is required")
    end

    test "regenerate fails with incorrect password" do
      @user.update!(otp_required_for_login: true, otp_secret: ROTP::Base32.random)

      post api_regenerate_backup_codes_path, params: { password: "wrongpassword" }, headers: auth_headers, as: :json

      assert_response :unauthorized
    end

    test "regenerate requires authentication" do
      post api_regenerate_backup_codes_path, params: { password: "Password123!" }, as: :json

      assert_response :unauthorized
    end
  end
end
