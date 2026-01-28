# frozen_string_literal: true

require "test_helper"

class HubControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

    # Create entity_user if needed (for entity.owner or entity.users.first)
    EntityUser.find_or_create_by!(entity: @entity, user: @user) do |eu|
      eu.role = 'owner'
    end

    # Create a team channel - automatically creates default thread via after_create callback
    @channel = TeamChannel.create!(
      entity: @entity,
      name: "general-#{SecureRandom.hex(4)}",
      channel_type: "general",
      description: "General discussion"
    )

    # Get the auto-created thread and add test data
    @thread = @channel.main_thread

    # Add user as participant if not already
    unless @thread.hub_participants.exists?(participant: @user)
      @participant = HubParticipant.create!(
        hub_thread: @thread,
        participant: @user,
        role: 'member',
        joined_at: Time.current
      )
    end

    # Create a test message
    @message = HubMessage.create!(
      hub_thread: @thread,
      sender: @user,
      content: "Hello, world!",
      message_type: 'text'
    )
  end

  teardown do
    # Clean up in correct order to avoid foreign key issues
    HubMessage.where(hub_thread_id: @thread&.id).delete_all if @thread
    HubParticipant.where(hub_thread_id: @thread&.id).delete_all if @thread
    @thread&.delete
    @channel&.delete
  end

  # ====================================================================
  # Helper Methods
  # ====================================================================

  def auth_headers
    { "Authorization" => "Bearer #{@user.api_key}" }
  end

  # ====================================================================
  # CHANNELS (GET /hub/channels) Tests
  # ====================================================================

  test "should get channels list with valid token" do
    get hub_channels_path, headers: auth_headers, as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.is_a?(Array)
  end

  test "channels list returns expected fields" do
    get hub_channels_path, headers: auth_headers, as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.any?

    channel = response_body.first
    assert channel.key?("id")
    assert channel.key?("name")
    assert channel.key?("channel_type")
  end

  test "channels list requires authentication" do
    get hub_channels_path, as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # CHANNEL MESSAGES (GET /hub/channels/:id/messages) Tests
  # ====================================================================

  test "should get channel messages with valid token" do
    get "/hub/channels/#{@channel.id}/messages", headers: auth_headers, as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.key?("channel")
    assert response_body.key?("thread_id")
    assert response_body.key?("messages")
  end

  test "channel messages includes message content" do
    get "/hub/channels/#{@channel.id}/messages", headers: auth_headers, as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    messages = response_body["messages"]

    assert messages.any?
    message = messages.find { |m| m["content"] == "Hello, world!" }
    assert_not_nil message
  end

  test "channel messages requires authentication" do
    get "/hub/channels/#{@channel.id}/messages", as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # SEND CHANNEL MESSAGE (POST /hub/channels/:id/messages) Tests
  # ====================================================================

  test "should send message to channel" do
    assert_difference("HubMessage.count", 1) do
      post "/hub/channels/#{@channel.id}/messages",
        params: { content: "Test message", message_type: "text" },
        headers: auth_headers,
        as: :json
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body["success"]
    assert_equal "Test message", response_body["message"]["content"]
  end

  test "send message fails without content" do
    post "/hub/channels/#{@channel.id}/messages",
      params: { content: "", message_type: "text" },
      headers: auth_headers,
      as: :json

    assert_response :unprocessable_entity
  end

  test "send message requires authentication" do
    post "/hub/channels/#{@channel.id}/messages",
      params: { content: "Test", message_type: "text" },
      as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # CREATE CHANNEL (POST /hub/channels) Tests
  # ====================================================================

  test "should create channel with valid data" do
    assert_difference("TeamChannel.count", 1) do
      post hub_channels_path,
        params: { channel: { name: "new-channel-#{SecureRandom.hex(4)}", description: "A new channel", channel_type: "project" } },
        headers: auth_headers,
        as: :json
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body["success"]
  end

  test "create channel requires authentication" do
    post hub_channels_path,
      params: { channel: { name: "test", channel_type: "general" } },
      as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # DELETE CHANNEL (DELETE /hub/channels/:id) Tests
  # ====================================================================

  test "should delete non-default channel" do
    new_channel = TeamChannel.create!(
      entity: @entity,
      name: "temp-channel-#{SecureRandom.hex(4)}",
      channel_type: "project"
    )

    delete "/hub/channels/#{new_channel.id}",
      headers: auth_headers,
      as: :json

    assert_response :success
  end

  test "cannot delete only general channel" do
    # Ensure this is the only general channel
    TeamChannel.where(entity: @entity, channel_type: 'general').where.not(id: @channel.id).destroy_all

    assert_no_difference("TeamChannel.count") do
      delete "/hub/channels/#{@channel.id}",
        headers: auth_headers,
        as: :json
    end

    assert_response :unprocessable_entity
  end

  # ====================================================================
  # DMS (GET /hub/dms) Tests
  # ====================================================================

  test "should get DM threads list" do
    get hub_dms_path, headers: auth_headers, as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.is_a?(Array)
  end

  test "DMs list requires authentication" do
    get hub_dms_path, as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # CREATE DM (POST /hub/dms) Tests
  # ====================================================================

  test "should create DM with another user" do
    other_user = users(:two)
    other_user.update!(entity: @entity)
    EntityUser.find_or_create_by!(entity: @entity, user: other_user) do |eu|
      eu.role = 'member'
    end

    post hub_dms_path,
      params: { participant_type: "User", participant_id: other_user.id },
      headers: auth_headers,
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body["success"]
    assert response_body.key?("thread")
  end

  test "create DM with initial message" do
    other_user = users(:two)
    other_user.update!(entity: @entity)
    EntityUser.find_or_create_by!(entity: @entity, user: other_user) do |eu|
      eu.role = 'member'
    end

    post hub_dms_path,
      params: {
        participant_type: "User",
        participant_id: other_user.id,
        message: "Hey there!"
      },
      headers: auth_headers,
      as: :json

    assert_response :success
  end

  test "create DM fails with non-existent user" do
    post hub_dms_path,
      params: { participant_type: "User", participant_id: 999999 },
      headers: auth_headers,
      as: :json

    assert_response :not_found
  end

  # ====================================================================
  # PRESENCE (GET /hub/presence) Tests
  # ====================================================================

  test "should get presence data" do
    get hub_presence_path, headers: auth_headers, as: :json

    assert_response :success
  end

  # ====================================================================
  # UPDATE PRESENCE (POST /hub/presence) Tests
  # ====================================================================

  test "should update presence status" do
    post hub_presence_path,
      params: { status: "online", message: "Working on project" },
      headers: auth_headers,
      as: :json

    assert_response :success
  end

  # ====================================================================
  # HEARTBEAT (POST /hub/heartbeat) Tests
  # ====================================================================

  test "should send heartbeat" do
    post hub_heartbeat_path, headers: auth_headers, as: :json

    assert_response :success
  end

  test "heartbeat requires authentication" do
    post hub_heartbeat_path, as: :json

    assert_response :unauthorized
  end

  # ====================================================================
  # ARCHIVE THREAD (POST /hub/thread/:id/archive) Tests
  # ====================================================================

  test "should archive DM thread" do
    # Create a DM thread for testing
    other_user = users(:two)
    other_user.update!(entity: @entity)
    EntityUser.find_or_create_by!(entity: @entity, user: other_user) do |eu|
      eu.role = 'member'
    end

    dm_thread = HubThread.find_or_create_dm(
      entity: @entity,
      participants: [@user, other_user]
    )

    assert_equal 'active', dm_thread.status

    post "/hub/thread/#{dm_thread.id}/archive",
      headers: auth_headers,
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body["success"]
    assert_equal "archived", response_body["status"]

    dm_thread.reload
    assert_equal 'archived', dm_thread.status
  end

  test "archive thread requires authentication" do
    post "/hub/thread/#{@thread.id}/archive", as: :json

    assert_response :unauthorized
  end

  test "archive thread requires participant" do
    # Create a thread where user is NOT a participant
    other_user = users(:two)
    other_user.update!(entity: @entity, api_key: SecureRandom.hex(32))
    EntityUser.find_or_create_by!(entity: @entity, user: other_user) do |eu|
      eu.role = 'member'
    end

    third_user = User.create!(
      email: "third-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      entity: @entity
    )
    EntityUser.find_or_create_by!(entity: @entity, user: third_user) do |eu|
      eu.role = 'member'
    end

    dm_thread = HubThread.find_or_create_dm(
      entity: @entity,
      participants: [other_user, third_user]
    )

    post "/hub/thread/#{dm_thread.id}/archive",
      headers: auth_headers,
      as: :json

    assert_response :forbidden
  end

  # ====================================================================
  # UNARCHIVE THREAD (POST /hub/thread/:id/unarchive) Tests
  # ====================================================================

  test "should unarchive DM thread" do
    # Create and archive a DM thread
    other_user = users(:two)
    other_user.update!(entity: @entity)
    EntityUser.find_or_create_by!(entity: @entity, user: other_user) do |eu|
      eu.role = 'member'
    end

    dm_thread = HubThread.find_or_create_dm(
      entity: @entity,
      participants: [@user, other_user]
    )
    dm_thread.archive!
    assert_equal 'archived', dm_thread.status

    post "/hub/thread/#{dm_thread.id}/unarchive",
      headers: auth_headers,
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body["success"]
    assert_equal "active", response_body["status"]

    dm_thread.reload
    assert_equal 'active', dm_thread.status
  end

  test "unarchive thread requires authentication" do
    post "/hub/thread/#{@thread.id}/unarchive", as: :json

    assert_response :unauthorized
  end

  test "unarchive thread requires participant" do
    # Create a thread where user is NOT a participant
    other_user = users(:two)
    other_user.update!(entity: @entity, api_key: SecureRandom.hex(32))
    EntityUser.find_or_create_by!(entity: @entity, user: other_user) do |eu|
      eu.role = 'member'
    end

    third_user = User.create!(
      email: "third-unarchive-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      entity: @entity
    )
    EntityUser.find_or_create_by!(entity: @entity, user: third_user) do |eu|
      eu.role = 'member'
    end

    dm_thread = HubThread.find_or_create_dm(
      entity: @entity,
      participants: [other_user, third_user]
    )
    dm_thread.archive!

    post "/hub/thread/#{dm_thread.id}/unarchive",
      headers: auth_headers,
      as: :json

    assert_response :forbidden
  end

  test "archived threads are not returned in DMs list" do
    # Create two DM threads
    other_user = users(:two)
    other_user.update!(entity: @entity)
    EntityUser.find_or_create_by!(entity: @entity, user: other_user) do |eu|
      eu.role = 'member'
    end

    dm_thread = HubThread.find_or_create_dm(
      entity: @entity,
      participants: [@user, other_user]
    )

    # Get DMs before archiving
    get hub_dms_path, headers: auth_headers, as: :json
    assert_response :success
    dms_before = JSON.parse(response.body)
    initial_count = dms_before.count { |dm| dm["id"] == dm_thread.id }

    # Archive the thread
    dm_thread.archive!

    # Get DMs after archiving
    get hub_dms_path, headers: auth_headers, as: :json
    assert_response :success
    dms_after = JSON.parse(response.body)
    final_count = dms_after.count { |dm| dm["id"] == dm_thread.id }

    # The archived thread should not appear in the list
    assert_equal 0, final_count, "Archived thread should not appear in DMs list"
  end
end
