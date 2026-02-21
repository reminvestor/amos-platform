# frozen_string_literal: true

require "test_helper"

class ScoutModelSelectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update_column(:entity_id, @entity.id) unless @user.entity_id == @entity.id
    sign_in @user
  end

  # ═══════════════════════════════════════════════════════════════
  # SET MODEL MODE
  # ═══════════════════════════════════════════════════════════════

  test "set_model_mode with auto stores nil model" do
    post "/scout/set_model_mode", params: { mode: "auto" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "auto", body["mode"]
    assert_nil body["model"]
  end

  test "set_model_mode with economy stores qwen model" do
    post "/scout/set_model_mode", params: { mode: "economy", model: "qwen3-next-80b" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "economy", body["mode"]
    assert_equal "qwen3-next-80b", body["model"]
  end

  test "set_model_mode with light stores haiku model" do
    post "/scout/set_model_mode", params: { mode: "light", model: "claude-haiku-4-5" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "light", body["mode"]
    assert_equal "claude-haiku-4-5", body["model"]
  end

  test "set_model_mode with medium stores sonnet model" do
    post "/scout/set_model_mode", params: { mode: "medium", model: "claude-sonnet-4-6" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "medium", body["mode"]
    assert_equal "claude-sonnet-4-6", body["model"]
  end

  test "set_model_mode with deep stores opus model" do
    post "/scout/set_model_mode", params: { mode: "deep", model: "claude-opus-4-6" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "deep", body["mode"]
    assert_equal "claude-opus-4-6", body["model"]
  end

  test "set_model_mode falls back to MODE_TO_MODEL when model param missing" do
    post "/scout/set_model_mode", params: { mode: "deep" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "deep", body["mode"]
    assert_equal "claude-opus-4-6", body["model"]
  end

  test "set_model_mode rejects invalid mode" do
    post "/scout/set_model_mode", params: { mode: "turbo" }, as: :json

    assert_response :bad_request
    body = JSON.parse(response.body)
    refute body["success"]
    assert_match /Invalid mode/, body["error"]
  end

  # ═══════════════════════════════════════════════════════════════
  # LEGACY MODE MAPPING
  # ═══════════════════════════════════════════════════════════════

  test "set_model_mode maps legacy fast to light" do
    post "/scout/set_model_mode", params: { mode: "fast" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "light", body["mode"]
    assert_equal "claude-haiku-4-5", body["model"]
  end

  test "set_model_mode maps legacy balanced to medium" do
    post "/scout/set_model_mode", params: { mode: "balanced" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "medium", body["mode"]
    assert_equal "claude-sonnet-4-6", body["model"]
  end

  test "set_model_mode maps legacy powerful to deep" do
    post "/scout/set_model_mode", params: { mode: "powerful" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "deep", body["mode"]
    assert_equal "claude-opus-4-6", body["model"]
  end

  test "set_model_mode maps legacy cheap to economy" do
    post "/scout/set_model_mode", params: { mode: "cheap" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "economy", body["mode"]
    assert_equal "qwen3-next-80b", body["model"]
  end

  # ═══════════════════════════════════════════════════════════════
  # GET MODEL MODE
  # ═══════════════════════════════════════════════════════════════

  test "get_model_mode returns auto by default" do
    get "/scout/model_mode", as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "auto", body["current_mode"]
    assert_nil body["current_model"]
  end

  test "get_model_mode returns previously set mode" do
    post "/scout/set_model_mode", params: { mode: "deep", model: "claude-opus-4-6" }, as: :json
    assert_response :success

    get "/scout/model_mode", as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "deep", body["current_mode"]
    assert_equal "claude-opus-4-6", body["current_model"]
  end

  test "get_model_mode lists all available modes" do
    get "/scout/model_mode", as: :json

    assert_response :success
    body = JSON.parse(response.body)
    modes = body["available_modes"].map { |m| m["key"] }
    assert_includes modes, "auto"
    assert_includes modes, "economy"
    assert_includes modes, "light"
    assert_includes modes, "medium"
    assert_includes modes, "deep"
  end

  # ═══════════════════════════════════════════════════════════════
  # SESSION PERSISTENCE ACROSS REQUESTS
  # ═══════════════════════════════════════════════════════════════

  test "model selection persists across multiple mode changes" do
    post "/scout/set_model_mode", params: { mode: "deep", model: "claude-opus-4-6" }, as: :json
    assert_response :success

    get "/scout/model_mode", as: :json
    body = JSON.parse(response.body)
    assert_equal "deep", body["current_mode"]
    assert_equal "claude-opus-4-6", body["current_model"]

    post "/scout/set_model_mode", params: { mode: "auto" }, as: :json
    assert_response :success

    get "/scout/model_mode", as: :json
    body = JSON.parse(response.body)
    assert_equal "auto", body["current_mode"]
    assert_nil body["current_model"]
  end

  # ═══════════════════════════════════════════════════════════════
  # LEGACY SET_PREMIUM_MODEL ENDPOINT
  # ═══════════════════════════════════════════════════════════════

  test "set_premium_model with valid model maps to correct mode" do
    post "/scout/set_premium_model", params: { model: "claude-opus-4-6" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "claude-opus-4-6", body["model"]
    assert_equal "deep", body["mode"]
  end

  test "set_premium_model with blank model resets to auto" do
    post "/scout/set_premium_model", params: { model: nil }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_equal "auto", body["mode"]
  end

  test "set_premium_model with invalid model returns error" do
    post "/scout/set_premium_model", params: { model: "gpt-4-turbo" }, as: :json

    assert_response :bad_request
    body = JSON.parse(response.body)
    refute body["success"]
  end

  test "set_premium_model with sonnet maps to medium" do
    post "/scout/set_premium_model", params: { model: "claude-sonnet-4-6" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "medium", body["mode"]
  end

  test "set_premium_model with haiku maps to light" do
    post "/scout/set_premium_model", params: { model: "claude-haiku-4-5" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "light", body["mode"]
  end
end
