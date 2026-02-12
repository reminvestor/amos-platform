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
    skip "Requires compiled assets (application.js) — skipped in CI" if ENV["CI"]
    sign_in @user
    get "/debug"
    assert_response :success
  end

  # --- Status endpoint (requires authentication) ---

  test "debug status redirects when not authenticated" do
    get "/debug/status"
    assert_response :redirect
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
    sign_in @user
    get "/debug/status"

    body = JSON.parse(response.body)
    assert body.key?("timestamp")
    assert_nothing_raised { Time.iso8601(body["timestamp"]) }
  end
end
