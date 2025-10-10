require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  # Helper method for signing in users
  def sign_in(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"

    # Verify sign in was successful
    assert_text "Signed in successfully", wait: 5
  end

  # Helper to wait for streaming responses to complete
  def wait_for_stream_complete(timeout: 30)
    # Wait for any streaming indicators to disappear
    assert_no_selector ".streaming-indicator", wait: timeout
  rescue Capybara::ElementNotFound
    # No streaming indicator found, which is fine
    true
  end

  # Helper to wait for AI response
  def wait_for_ai_response(text, timeout: 10)
    assert_text text, wait: timeout
  end

  # Helper to send message in AMOS chat
  def send_chat_message(message)
    fill_in "message-input", with: message
    click_button "send-button"
  end
end
