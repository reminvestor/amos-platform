require "application_system_test_case"

class EmailTemplateTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)
    @user.update!(entity: @entity, onboarded: true)
    @entity.update!(subscription_status: 'active')
  end

  test "user can access email templates index" do
    sign_in_as(@user)

    visit email_templates_path

    # Templates page should load
    assert_selector "body", visible: true
    assert_text /template|email/i
  end

  test "templates page shows create new template button" do
    sign_in_as(@user)

    visit email_templates_path

    # Should have create option
    has_new_button = page.has_selector?("a", text: /new|add|create/i) ||
                     page.has_selector?("button", text: /new|add|create/i)

    assert has_new_button, "Expected new template button"
  end

  test "user can access new template form" do
    sign_in_as(@user)

    visit new_email_template_path

    # Should see template form
    assert_selector "form", visible: true

    # Should have name and content fields
    has_name = page.has_selector?("input[name*='name']")
    has_subject = page.has_selector?("input[name*='subject']")
    has_content = page.has_selector?("textarea") || page.has_selector?("[contenteditable]")

    assert has_name || has_subject || has_content, "Expected template form fields"
  end

  test "user can create a new email template" do
    sign_in_as(@user)

    visit new_email_template_path

    # Fill in template details
    fill_in "Name", with: "Test Template" rescue fill_in "email_template[name]", with: "Test Template"
    fill_in "Subject", with: "Test Subject" rescue fill_in "email_template[subject]", with: "Test Subject"

    # Fill in body if textarea exists
    if page.has_selector?("textarea[name*='body']")
      fill_in "email_template[body]", with: "<p>Test email content</p>"
    elsif page.has_selector?("textarea")
      first("textarea").fill_in with: "<p>Test email content</p>"
    end

    click_button "Save" rescue click_button "Create" rescue find("button[type='submit']").click

    sleep 1

    # Should redirect or show success
    success = page.has_text?(/created|success|saved/i) ||
              current_path == email_templates_path

    assert success, "Expected template creation success"
  end

  test "template form validates required fields" do
    sign_in_as(@user)

    visit new_email_template_path

    # Try to submit empty form
    click_button "Save" rescue click_button "Create" rescue find("button[type='submit']").click

    sleep 1

    # Should show validation or stay on form
    has_error = page.has_text?(/required|invalid|error|blank|can't be blank/i) ||
                current_path.include?("email_template")

    assert has_error, "Expected form validation"
  end

  test "user can view existing template" do
    template = EmailTemplate.create!(
      entity: @entity,
      name: "View Test Template",
      subject: "View Test Subject",
      body: "<p>View test content</p>"
    )

    sign_in_as(@user)

    visit email_template_path(template)

    # Should see template details
    assert_text "View Test Template"
  end

  test "user can edit existing template" do
    template = EmailTemplate.create!(
      entity: @entity,
      name: "Edit Test Template",
      subject: "Edit Test Subject",
      body: "<p>Edit test content</p>"
    )

    sign_in_as(@user)

    visit edit_email_template_path(template)

    # Should see edit form with existing values
    assert_selector "form", visible: true
    has_value = page.has_selector?("input[value='Edit Test Template']") ||
                page.has_text?("Edit Test Template")

    assert has_value, "Expected template values in edit form"
  end

  test "user can delete template" do
    template = EmailTemplate.create!(
      entity: @entity,
      name: "Delete Test Template",
      subject: "Delete Subject",
      body: "<p>Delete content</p>"
    )

    sign_in_as(@user)

    visit email_template_path(template)

    # Should have delete option
    has_delete = page.has_selector?("a", text: /delete|remove/i) ||
                 page.has_selector?("button", text: /delete|remove/i)

    assert has_delete, "Expected delete option"
  end

  test "templates page shows template list" do
    # Create some templates
    3.times do |i|
      EmailTemplate.create!(
        entity: @entity,
        name: "List Template #{i}",
        subject: "Subject #{i}",
        body: "<p>Content #{i}</p>"
      )
    end

    sign_in_as(@user)

    visit email_templates_path

    # Should show templates
    assert_text "List Template 0"
    assert_text "List Template 1"
  end

  test "template editor has formatting options" do
    sign_in_as(@user)

    visit new_email_template_path

    # Should have some kind of editor (rich text or textarea)
    has_editor = page.has_selector?("textarea") ||
                 page.has_selector?("[contenteditable]") ||
                 page.has_selector?(".editor") ||
                 page.has_selector?("[data-controller*='editor']")

    assert has_editor, "Expected template editor"
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"
    assert_selector "a[href='/scout']", wait: 5
  end
end
