require "application_system_test_case"

class ScoutFileUploadTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)
    @user.update!(entity: @entity, onboarded: true)
    @entity.update!(subscription_status: 'active')
  end

  test "user can attach and upload a file in Scout chat" do
    sign_in_as(@user)

    # Navigate to Scout
    visit "/scout"

    # Wait for Scout to load
    assert_selector ".chat-input", visible: true

    # Click the attach button
    attach_button = find(".attach-btn")
    assert attach_button.visible?, "Attach button should be visible"

    # Attach a test file
    input_file = find("input#file-input", visible: false)
    test_file = create_test_image

    input_file.send_keys(test_file)

    # Wait for file to be displayed
    sleep 1

    # Verify file appears in attached files container
    assert_selector ".attached-file", visible: true, text: File.basename(test_file)

    # Verify file icon is rendered (Lucide icon)
    assert_selector ".attached-file [data-lucide]", visible: true

    # Add a message
    fill_in "message-input", with: "Please analyze this file"

    # Submit form (this should trigger file upload)
    click_button "send-button"

    # Storage choice modal should appear
    assert_selector "#document-storage-modal", visible: true

    # Select storage choice (default to long-term)
    find(".storage-option", visible: true).click

    # Wait for confirm button and click it
    click_button "confirm-storage-choice"

    # Wait for request to be processed
    sleep 2

    # Verify file was uploaded by checking for user message in chat
    assert_selector ".chat-message.user-message", text: "Please analyze this file"

    # Verify no error messages
    assert_no_selector ".alert-danger"

  ensure
    # Clean up test file (test_file may be nil if test failed before assignment)
    File.delete(test_file) if test_file && File.exist?(test_file)
  end

  test "file upload fails gracefully when no message provided" do
    sign_in_as(@user)

    visit "/scout"

    assert_selector ".chat-input", visible: true

    # Attach a file
    input_file = find("input#file-input", visible: false)
    test_file = create_test_image
    input_file.send_keys(test_file)

    sleep 1
    assert_selector ".attached-file"

    # Try to send without a message (should work with default message)
    click_button "send-button"

    # Modal should appear
    assert_selector "#document-storage-modal", visible: true

    # Complete upload
    find(".storage-option").click
    click_button "confirm-storage-choice"

    sleep 2

    # Should have a user message (either our message or a default)
    assert_selector ".chat-message.user-message"

  ensure
    File.delete(test_file) if test_file && File.exist?(test_file)
  end

  test "multiple files can be attached and uploaded" do
    sign_in_as(@user)

    visit "/scout"

    assert_selector ".chat-input", visible: true

    # Create multiple test files
    test_files = 2.times.map { |i| create_test_image("test_#{i}") }

    # Attach first file
    input_file = find("input#file-input", visible: false)
    input_file.send_keys(test_files[0])
    sleep 0.5

    # Verify first file is shown
    assert_selector ".attached-file", text: File.basename(test_files[0])

    # Attach second file
    input_file.send_keys(test_files[1])
    sleep 0.5

    # Verify both files are shown
    assert_selector ".attached-file", count: 2

    # Submit
    fill_in "message-input", with: "Process these files"
    click_button "send-button"

    # Complete modal
    assert_selector "#document-storage-modal", visible: true
    find(".storage-option").click
    click_button "confirm-storage-choice"

    sleep 2

    # Verify user message was sent
    assert_selector ".chat-message.user-message", text: "Process these files"

  ensure
    Array(test_files).each { |f| File.delete(f) if f && File.exist?(f) }
  end

  test "file can be removed from attachments" do
    sign_in_as(@user)

    visit "/scout"

    assert_selector ".chat-input", visible: true

    # Attach a file
    input_file = find("input#file-input", visible: false)
    test_file = create_test_image
    input_file.send_keys(test_file)

    sleep 1
    assert_selector ".attached-file"

    # Click remove button (×)
    find(".attached-file .remove").click

    sleep 0.5

    # File should be removed
    assert_no_selector ".attached-file"

    # Attached files container should be hidden
    assert_no_selector ".attached-files", visible: true

  ensure
    File.delete(test_file) if test_file && File.exist?(test_file)
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign In"

    # Wait for Scout link to appear
    assert_selector "a[href='/scout']"
  end

  def create_test_image(name = "test_image")
    require 'tmpdir'
    require 'base64'

    # Create a minimal 1x1 PNG
    png_data = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )

    temp_file = File.join(Dir.tmpdir, "#{name}_#{Time.now.to_i}.png")
    File.write(temp_file, png_data)
    temp_file
  end
end
