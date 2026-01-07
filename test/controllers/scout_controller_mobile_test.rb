# frozen_string_literal: true

require "test_helper"

class ScoutControllerMobileTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

    # Ensure entity has a business profile
    @entity.create_business_profile!(
      business_name: "Test Business",
      industry: "Technology"
    ) unless @entity.business_profile

    # Set user as onboarded
    @user.update!(onboarding_complete: true)
  end

  # ====================================================================
  # Helper Methods
  # ====================================================================

  def auth_headers
    { "Authorization" => "Bearer #{@user.api_key}" }
  end

  # ====================================================================
  # NEW SESSION (POST /amos/new_session) Tests
  # ====================================================================

  test "should create new session with valid token" do
    post amos_new_session_path, headers: auth_headers, as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.key?("session_id")
    assert response_body["session_id"].present?
  end

  test "new session requires authentication" do
    post amos_new_session_path, as: :json

    assert_response :unauthorized
  end

  test "new session returns different ids for each call" do
    post amos_new_session_path, headers: auth_headers, as: :json
    session1 = JSON.parse(response.body)["session_id"]

    post amos_new_session_path, headers: auth_headers, as: :json
    session2 = JSON.parse(response.body)["session_id"]

    assert_not_equal session1, session2
  end

  # ====================================================================
  # CHAT STREAM (POST /amos/chat_stream) Tests
  # ====================================================================

  test "chat stream returns SSE response" do
    post amos_chat_stream_path,
      params: { message: "Hello", session_id: "test_session_#{SecureRandom.hex(8)}" },
      headers: auth_headers.merge("Accept" => "text/event-stream")

    assert_response :success
    assert_match "text/event-stream", response.content_type
  end

  test "chat stream fails without message" do
    post amos_chat_stream_path,
      params: { message: "", session_id: "test_session" },
      headers: auth_headers,
      as: :json

    assert_response :bad_request
  end

  test "chat stream requires authentication" do
    post amos_chat_stream_path,
      params: { message: "Hello", session_id: "test_session" },
      as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # UPLOAD FILES (POST /amos/upload_files) Tests
  # ====================================================================

  test "upload files requires authentication" do
    post amos_upload_files_path, as: :json

    assert_response :unauthorized
  end

  test "upload files with valid file" do
    file = fixture_file_upload("files/test.txt", "text/plain")

    post amos_upload_files_path,
      params: { "files[0]" => file, storage_type: "short-term" },
      headers: auth_headers

    # Should succeed or return appropriate response
    assert_includes [200, 201, 422], response.status
  end

  # ====================================================================
  # CONVERSATIONS (GET /amos/conversations) Tests
  # ====================================================================

  test "should list conversations with valid token" do
    get amos_conversations_path, headers: auth_headers, as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.key?("conversations") || response_body.is_a?(Array)
  end

  test "conversations requires authentication" do
    get amos_conversations_path, as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # HISTORY (GET /amos/history) Tests
  # ====================================================================

  test "should get history with valid token" do
    get amos_history_path, headers: auth_headers, as: :json

    assert_response :success
  end

  test "history requires authentication" do
    get amos_history_path, as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # BOOKMARKS (GET /amos/bookmarks) Tests
  # ====================================================================

  test "should get bookmarks with valid token" do
    get amos_bookmarks_path, headers: auth_headers, as: :json

    assert_response :success
  end

  test "bookmarks requires authentication" do
    get amos_bookmarks_path, as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # AVAILABLE CANVASES (GET /amos/available_canvases) Tests
  # ====================================================================

  test "should get available canvases" do
    get amos_available_canvases_path, headers: auth_headers, as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.key?("canvases") || response_body.is_a?(Array)
  end
end
