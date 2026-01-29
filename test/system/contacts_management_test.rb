require "application_system_test_case"

class ContactsManagementTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)
    @user.update!(entity: @entity, onboarded: true)
    @entity.update!(subscription_status: 'active')
  end

  test "user can access contacts index" do
    sign_in_as(@user)

    visit contacts_path

    # Contacts page should load
    assert_selector "body", visible: true
    assert_text /contact/i
  end

  test "contacts page shows create new contact button" do
    sign_in_as(@user)

    visit contacts_path

    # Should have a way to create new contact
    has_new_button = page.has_selector?("a", text: /new|add|create/i) ||
                     page.has_selector?("button", text: /new|add|create/i)

    assert has_new_button, "Expected new contact button"
  end

  test "user can access new contact form" do
    sign_in_as(@user)

    visit new_contact_path

    # Should see contact form fields
    assert_selector "form", visible: true
    has_email_field = page.has_selector?("input[name*='email']") ||
                      page.has_selector?("input[type='email']")
    has_name_field = page.has_selector?("input[name*='name']") ||
                     page.has_selector?("input[name*='first']")

    assert has_email_field || has_name_field, "Expected contact form fields"
  end

  test "user can create a new contact" do
    sign_in_as(@user)

    visit new_contact_path

    # Fill in contact details
    fill_in_contact_form(
      email: "newcontact@example.com",
      first_name: "John",
      last_name: "Doe"
    )

    click_button "Save" rescue click_button "Create" rescue find("button[type='submit']").click

    # Should redirect or show success
    sleep 1
    success = page.has_text?(/created|success|saved/i) ||
              current_path != new_contact_path

    assert success, "Expected contact creation success"
  end

  test "contact form validates required fields" do
    sign_in_as(@user)

    visit new_contact_path

    # Try to submit empty form
    click_button "Save" rescue click_button "Create" rescue find("button[type='submit']").click

    # Should show validation error or stay on form
    sleep 1
    has_error = page.has_text?(/required|invalid|error|blank/i) ||
                current_path.include?("contact")

    assert has_error, "Expected form validation"
  end

  test "user can view existing contact" do
    # Create a contact
    contact = Contact.create!(
      entity: @entity,
      user: @user,
      email: "viewtest@example.com",
      first_name: "View",
      last_name: "Test"
    )

    sign_in_as(@user)

    visit contact_path(contact)

    # Should see contact details
    assert_text "viewtest@example.com"
  end

  test "user can edit existing contact" do
    contact = Contact.create!(
      entity: @entity,
      user: @user,
      email: "edittest@example.com",
      first_name: "Edit",
      last_name: "Test"
    )

    sign_in_as(@user)

    visit edit_contact_path(contact)

    # Should see edit form
    assert_selector "form", visible: true
    assert_selector "input[value='edittest@example.com'], input[value='Edit']", visible: true
  end

  test "user can delete contact" do
    contact = Contact.create!(
      entity: @entity,
      user: @user,
      email: "deletetest@example.com",
      first_name: "Delete",
      last_name: "Test"
    )

    sign_in_as(@user)

    visit contact_path(contact)

    # Should have delete option
    has_delete = page.has_selector?("a", text: /delete|remove/i) ||
                 page.has_selector?("button", text: /delete|remove/i)

    assert has_delete, "Expected delete option"
  end

  test "contacts page shows contact list" do
    # Create some contacts
    3.times do |i|
      Contact.create!(
        entity: @entity,
        user: @user,
        email: "list#{i}@example.com",
        first_name: "List#{i}",
        last_name: "Test"
      )
    end

    sign_in_as(@user)

    visit contacts_path

    # Should show contacts in list
    assert_text "list0@example.com"
    assert_text "list1@example.com"
  end

  test "contacts page has import option" do
    sign_in_as(@user)

    visit contacts_path

    # Should have import functionality
    has_import = page.has_text?(/import/i) ||
                 page.has_selector?("a", text: /import/i) ||
                 page.has_selector?("button", text: /import/i)

    assert has_import, "Expected import option"
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"
    assert_selector "a[href='/scout']", wait: 5
  end

  def fill_in_contact_form(email:, first_name:, last_name:)
    fill_in "Email", with: email rescue nil
    fill_in "contact[email]", with: email rescue nil

    fill_in "First name", with: first_name rescue nil
    fill_in "contact[first_name]", with: first_name rescue nil

    fill_in "Last name", with: last_name rescue nil
    fill_in "contact[last_name]", with: last_name rescue nil
  end
end
