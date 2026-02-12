# frozen_string_literal: true

require "test_helper"

class DebugControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @user.update!(entity: @entity)
  end

  # --- Authentication ---

  test "debug index requires authentication" do
    get "/debug"
    assert_response :redirect
  end

  test "debug index accessible when authenticated" do
    sign_in @user
    get "/debug"
    assert_response :success
  end

  # --- Status endpoint ---

  test "debug status accessible without authentication" do
    get "/debug/status"
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_equal "User not signed in", body["message"]
  end

  test "debug status returns user info when authenticated" do
    sign_in @user
    get "/debug/status"
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal @user.id, body["user_id"]
    assert body.key?("timestamp")
  end

  test "debug status includes onboarding and entity info" do
    sign_in @user
    get "/debug/status"

    body = JSON.parse(response.body)
    assert body.key?("onboarded")
    assert body.key?("has_business_profile")
  end

  test "debug status returns timestamp in ISO 8601 format" do
    get "/debug/status"

    body = JSON.parse(response.body)
    assert body.key?("timestamp")
    assert_nothing_raised { Time.iso8601(body["timestamp"]) }
  end

  test "debug status unauthenticated response includes request metadata" do
    get "/debug/status"

    body = JSON.parse(response.body)
    assert body.key?("subdomain")
    assert body.key?("domain")
    assert body.key?("path")
  end
end
