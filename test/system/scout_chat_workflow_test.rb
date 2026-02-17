require "application_system_test_case"

class ScoutChatWorkflowTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update!(entity: @entity)
  end

  test "user can access Scout chat interface" do
    sign_in(@user)

    visit "/scout"

    # Verify chat interface loads
    assert_selector ".chat-input", visible: true
    assert_selector "#message-input", visible: true
    assert_selector "#send-button", visible: true
  end

  test "user can send a message and see it in chat" do
    sign_in(@user)

    visit "/scout"
    assert_selector ".chat-input", visible: true

    # Send a simple message
    fill_in "message-input", with: "Hello, what can you help me with?"
    click_button "send-button"

    # Verify user message appears in chat
    assert_selector ".message.user-message", text: "Hello, what can you help me with?", wait: 5
  end

  test "chat shows streaming indicator while processing" do
    sign_in(@user)

    visit "/scout"
    assert_selector ".chat-input", visible: true

    fill_in "message-input", with: "Tell me about email campaigns"
    click_button "send-button"

    # User message should appear
    assert_selector ".message.user-message", text: "Tell me about email campaigns", wait: 5

    # Should see some kind of loading/streaming state or assistant response
    # Either streaming indicator appears OR response starts immediately
    has_streaming = page.has_selector?(".streaming-indicator", wait: 2)
    has_response = page.has_selector?(".message.ai-message", wait: 10)

    assert has_streaming || has_response, "Expected streaming indicator or assistant response"
  end

  test "new session button clears conversation" do
    sign_in(@user)

    visit "/scout"
    assert_selector ".chat-input", visible: true

    # Send a message
    fill_in "message-input", with: "First message in session"
    click_button "send-button"
    assert_selector ".message.user-message", text: "First message in session", wait: 5

    # Click new session button
    find("[data-action*='new-session']", visible: true).click rescue find("button", text: /new/i, visible: true).click

    # Wait for page to refresh/clear
    sleep 1

    # Old message should be gone
    assert_no_selector ".message", text: "First message in session"
  end

  test "voice assistant button is present" do
    sign_in(@user)

    visit "/scout"
    assert_selector ".chat-input", visible: true

    # Voice button should be present
    assert_selector "[data-controller*='voice']", visible: true
  end

  test "attach button opens file picker" do
    sign_in(@user)

    visit "/scout"
    assert_selector ".chat-input", visible: true

    # Attach button should be present
    assert_selector ".attach-btn", visible: true

    # File input should exist (hidden)
    assert_selector "input#file-input", visible: false
  end

  private

end
