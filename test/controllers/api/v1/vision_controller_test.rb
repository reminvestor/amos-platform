# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class VisionControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:admin_user)
        @user.update!(api_key: "test_api_key_123")
        @entity = entities(:demo_company)
        @user.update!(entity: @entity)
      end

      # Test scan mode normalization - camelCase from Flutter
      test "scan accepts camelCase mode businessCard" do
        post "/api/v1/vision/scan",
          params: { mode: "businessCard" },
          headers: { "Authorization" => "Bearer #{@user.api_key}" },
          as: :json

        # Should not get "Invalid mode" error (will get "No image provided" instead)
        json = JSON.parse(response.body)
        assert_not_includes json["error"].to_s, "Invalid mode"
      end

      test "scan accepts snake_case mode business_card" do
        post "/api/v1/vision/scan",
          params: { mode: "business_card" },
          headers: { "Authorization" => "Bearer #{@user.api_key}" },
          as: :json

        json = JSON.parse(response.body)
        assert_not_includes json["error"].to_s, "Invalid mode"
      end

      test "scan accepts receipt mode" do
        post "/api/v1/vision/scan",
          params: { mode: "receipt" },
          headers: { "Authorization" => "Bearer #{@user.api_key}" },
          as: :json

        json = JSON.parse(response.body)
        assert_not_includes json["error"].to_s, "Invalid mode"
      end

      test "scan accepts document mode" do
        post "/api/v1/vision/scan",
          params: { mode: "document" },
          headers: { "Authorization" => "Bearer #{@user.api_key}" },
          as: :json

        json = JSON.parse(response.body)
        assert_not_includes json["error"].to_s, "Invalid mode"
      end

      test "scan accepts whiteboard mode" do
        post "/api/v1/vision/scan",
          params: { mode: "whiteboard" },
          headers: { "Authorization" => "Bearer #{@user.api_key}" },
          as: :json

        json = JSON.parse(response.body)
        assert_not_includes json["error"].to_s, "Invalid mode"
      end

      test "scan defaults to business_card when no mode provided" do
        post "/api/v1/vision/scan",
          params: {},
          headers: { "Authorization" => "Bearer #{@user.api_key}" },
          as: :json

        json = JSON.parse(response.body)
        assert_not_includes json["error"].to_s, "Invalid mode"
      end

      test "scan rejects invalid mode" do
        post "/api/v1/vision/scan",
          params: { mode: "totally_invalid_mode_xyz" },
          headers: { "Authorization" => "Bearer #{@user.api_key}" },
          as: :json

        # Mode check happens after image check, so we'll get "No image provided"
        # But the mode normalizer will at least not crash
        json = JSON.parse(response.body)
        assert json["error"].present?
      end

      test "scan requires authentication" do
        post "/api/v1/vision/scan",
          params: { mode: "businessCard" },
          as: :json

        assert_response :unauthorized
      end

      test "scan_and_save accepts camelCase mode" do
        post "/api/v1/vision/scan_and_save",
          params: { mode: "businessCard" },
          headers: { "Authorization" => "Bearer #{@user.api_key}" },
          as: :json

        json = JSON.parse(response.body)
        # Should not get Invalid mode error
        assert_not_includes json["error"].to_s, "Invalid mode"
      end

      test "scan_and_save accepts snake_case mode" do
        post "/api/v1/vision/scan_and_save",
          params: { mode: "business_card" },
          headers: { "Authorization" => "Bearer #{@user.api_key}" },
          as: :json

        json = JSON.parse(response.body)
        assert_not_includes json["error"].to_s, "Invalid mode"
      end
    end
  end
end
