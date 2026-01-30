require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Don't parallelize system tests - they need exclusive browser access
  parallelize(workers: 1)

  # Configure headless Chrome with proper CI environment flags
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    # Add Chrome options for stable headless operation in CI environments
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-gpu')
    options.add_argument('--disable-dev-shm-usage') # Disable /dev/shm to avoid memory issues
    options.add_argument('--disable-software-rasterizer')
    options.add_argument('--disable-extensions')
    options.add_argument('--disable-plugins')

    # Increase timeouts for slower CI environments
    options.add_argument('--disable-blink-features=AutomationControlled')
  end

  # Helper method for signing in users
  def sign_in(user)
    visit new_user_session_path

    # Use field IDs since labels may not be properly associated
    fill_in "user_email_field", with: user.email
    fill_in "user_password", with: "password"
    click_button "Sign In"

    # Verify sign in was successful - check for dashboard elements or success message
    # The app redirects to Scout/dashboard on success without flash message
    assert_selector "body", wait: 10
    has_flash = page.has_text?("Signed in successfully")
    has_dashboard = page.has_text?("AMOS") || page.has_selector?(".chat-input")
    assert has_flash || has_dashboard, "Expected successful sign in"
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
