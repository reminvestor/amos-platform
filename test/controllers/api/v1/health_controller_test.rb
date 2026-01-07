# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class HealthControllerTest < ActionDispatch::IntegrationTest
      # ====================================================================
      # INDEX Tests (Health Check)
      # ====================================================================

      test "should get health status" do
        get api_v1_health_path, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "ok", response_body["status"]
        assert response_body.key?("timestamp")
      end

      test "health response includes request info" do
        get api_v1_health_path, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("request_info")
        assert response_body["request_info"].key?("protocol")
        assert response_body["request_info"].key?("ssl")
      end

      test "health response includes env info" do
        get api_v1_health_path, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("env_info")
        assert response_body["env_info"].key?("rails_env")
      end

      test "health check does not require authentication" do
        # Health checks should be accessible without auth for load balancers
        get api_v1_health_path, as: :json

        assert_response :success
      end

      test "health check returns valid timestamp format" do
        get api_v1_health_path, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        timestamp = response_body["timestamp"]

        # Should be ISO8601 format
        assert_nothing_raised do
          Time.iso8601(timestamp)
        end
      end
    end
  end
end
