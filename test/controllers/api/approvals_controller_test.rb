# frozen_string_literal: true

require "test_helper"

module Api
  class ApprovalsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @entity = entities(:one)
      @user.update!(entity: @entity, api_key: SecureRandom.hex(32))
    end

    # ====================================================================
    # Helper Methods
    # ====================================================================

    def auth_headers
      { "Authorization" => "Bearer #{@user.api_key}" }
    end

    # ====================================================================
    # REQUEST_APPROVAL Tests
    # ====================================================================

    test "should handle approval request with underscore route" do
      post api_request_approval_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("approved")
      assert response_body.key?("message")
      assert response_body.key?("request_id")
    end

    test "approval request returns approved status" do
      post api_request_approval_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal true, response_body["approved"]
    end

    test "approval request returns UUID request_id" do
      post api_request_approval_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      # UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      assert_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, response_body["request_id"])
    end

    test "approval request with params" do
      post api_request_approval_path, params: {
        action_type: "send_email",
        description: "Send email to 100 contacts"
      }, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_equal true, response_body["approved"]
    end

    # ====================================================================
    # GET_INSTRUCTIONS Tests
    # ====================================================================

    test "should get instructions" do
      post api_get_instructions_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert response_body.key?("instructions")
      assert response_body.key?("has_instructions")
    end

    test "get instructions returns no pending instructions by default" do
      post api_get_instructions_path, headers: auth_headers, as: :json

      assert_response :success

      response_body = JSON.parse(response.body)
      assert_nil response_body["instructions"]
      assert_equal false, response_body["has_instructions"]
    end
  end
end
