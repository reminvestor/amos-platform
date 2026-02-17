require "application_system_test_case"

class LandingPageWorkflowTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    sign_in @user
  end

  test "creating a landing page through chat interface" do
    visit root_path

    # Navigate to chat
    click_on "Chat with AMOS"

    # Start landing page creation
    fill_in "message", with: "Create a landing page for my consulting business"
    click_button "Send"

    # AMOS should start the workflow
    assert_text "landing page", wait: 10

    # Respond to prompts (this will vary based on workflow)
    # This is a simplified example - actual implementation would need
    # to handle streaming responses and multiple prompts

    # Verify canvas loads
    assert_selector "#landing-page-canvas", wait: 15

    # Verify landing page was created
    assert LandingPage.where(entity: @entity).exists?
  end

  test "viewing landing page list" do
    landing_page = landing_pages(:one)

    visit landing_pages_path

    assert_text landing_page.title
    click_on landing_page.title

    # Should show landing page viewer
    assert_text "Preview"
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign In"
  end
end
