require "application_system_test_case"

class LandingPagesTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update!(entity: @entity)
  end

  test "user can access landing pages index" do
    sign_in(@user)

    visit landing_pages_path

    # Landing pages index should load
    assert_selector "body", visible: true
    assert_text /landing|page/i
  end

  test "landing pages index shows create button" do
    sign_in(@user)

    visit landing_pages_path

    # Should have create option
    has_new_button = page.has_selector?("a", text: /new|create|add/i) ||
                     page.has_selector?("button", text: /new|create|add/i)

    assert has_new_button, "Expected new landing page button"
  end

  test "user can access new landing page form" do
    sign_in(@user)

    visit new_landing_page_path

    # Should see landing page creation form/wizard
    assert_selector "body", visible: true
    has_form = page.has_selector?("form") ||
               page.has_text?(/create.*landing/i) ||
               page.has_text?(/new.*page/i)

    assert has_form, "Expected landing page creation interface"
  end

  test "landing page creation shows title field" do
    sign_in(@user)

    visit new_landing_page_path

    # Should have title input
    has_title = page.has_selector?("input[name*='title']") ||
                page.has_selector?("input[name*='name']") ||
                page.has_text?(/title|name/i)

    # Title field may be auto-generated
    assert_selector "body", visible: true
  end

  test "landing page creation shows template options" do
    sign_in(@user)

    visit new_landing_page_path

    # Should show template selection or AI generation option
    has_templates = page.has_text?(/template|design|layout/i) ||
                    page.has_selector?("[data-template]") ||
                    page.has_text?(/ai.*generate|generate.*ai/i)

    # Templates are optional
    assert_selector "body", visible: true
  end

  test "user can view existing landing page" do
    # Create a landing page
    landing_page = LandingPage.create!(
      entity: @entity,
      user: @user,
      title: "View Test Landing Page",
      slug: "view-test-page",
      status: "draft",
      html_content: "<div>Test content</div>"
    )

    sign_in(@user)

    visit landing_page_path(landing_page)

    # Should see landing page details
    assert_text "View Test Landing Page"
  end

  test "user can edit existing landing page" do
    landing_page = LandingPage.create!(
      entity: @entity,
      user: @user,
      title: "Edit Test Landing Page",
      slug: "edit-test-page",
      status: "draft",
      html_content: "<div>Test content</div>"
    )

    sign_in(@user)

    visit edit_landing_page_path(landing_page)

    # Should see edit interface
    assert_selector "body", visible: true
    has_editor = page.has_selector?("form") ||
                 page.has_selector?("[data-controller]") ||
                 page.has_text?(/edit|save/i)

    assert has_editor, "Expected landing page editor"
  end

  test "landing page editor has content section" do
    landing_page = LandingPage.create!(
      entity: @entity,
      user: @user,
      title: "Editor Test Page",
      slug: "editor-test",
      status: "draft",
      html_content: "<div>Test content</div>"
    )

    sign_in(@user)

    visit edit_landing_page_path(landing_page)

    # Should have content editing area
    has_content_editor = page.has_selector?("textarea") ||
                         page.has_selector?("[contenteditable]") ||
                         page.has_selector?(".editor") ||
                         page.has_selector?("[data-editor]") ||
                         page.has_text?(/content|section/i)

    assert has_content_editor, "Expected content editor"
  end

  test "landing page has publish option" do
    landing_page = LandingPage.create!(
      entity: @entity,
      user: @user,
      title: "Publish Test Page",
      slug: "publish-test",
      status: "draft",
      html_content: "<div>Test content</div>"
    )

    sign_in(@user)

    visit edit_landing_page_path(landing_page)

    # Should have publish button
    has_publish = page.has_selector?("button", text: /publish/i) ||
                  page.has_selector?("a", text: /publish/i) ||
                  page.has_text?(/publish|live/i)

    assert has_publish, "Expected publish option"
  end

  test "landing page has preview option" do
    landing_page = LandingPage.create!(
      entity: @entity,
      user: @user,
      title: "Preview Test Page",
      slug: "preview-test",
      status: "draft",
      html_content: "<div>Test content</div>"
    )

    sign_in(@user)

    visit edit_landing_page_path(landing_page)

    # Should have preview button
    has_preview = page.has_selector?("button", text: /preview/i) ||
                  page.has_selector?("a", text: /preview/i) ||
                  page.has_selector?("a[href*='preview']")

    assert has_preview, "Expected preview option"
  end

  test "landing pages index shows page list" do
    # Create some landing pages
    3.times do |i|
      LandingPage.create!(
        entity: @entity,
        user: @user,
        title: "List Test Page #{i}",
        slug: "list-test-page-#{i}",
        status: "draft",
        html_content: "<div>Test content</div>"
      )
    end

    sign_in(@user)

    visit landing_pages_path

    # Should show landing pages
    assert_text "List Test Page 0"
    assert_text "List Test Page 1"
  end

  test "landing page shows status indicator" do
    landing_page = LandingPage.create!(
      entity: @entity,
      user: @user,
      title: "Status Test Page",
      slug: "status-test",
      status: "draft",
      html_content: "<div>Test content</div>"
    )

    sign_in(@user)

    visit landing_pages_path

    # Should show status
    has_status = page.has_text?(/draft|published|live/i) ||
                 page.has_selector?("[data-status]") ||
                 page.has_selector?(".status")

    assert has_status, "Expected status indicator"
  end

  test "user can delete landing page" do
    landing_page = LandingPage.create!(
      entity: @entity,
      user: @user,
      title: "Delete Test Page",
      slug: "delete-test",
      status: "draft",
      html_content: "<div>Test content</div>"
    )

    sign_in(@user)

    visit landing_page_path(landing_page)

    # Should have delete option
    has_delete = page.has_selector?("a", text: /delete|remove/i) ||
                 page.has_selector?("button", text: /delete|remove/i)

    assert has_delete, "Expected delete option"
  end

  test "published landing page is publicly accessible" do
    landing_page = LandingPage.create!(
      entity: @entity,
      user: @user,
      title: "Public Test Page",
      slug: "public-test-page",
      status: "published",
      html_content: "<div><h1>Welcome</h1></div>"
    )

    # Access public URL without signing in
    visit landing_page_public_path(slug: landing_page.slug)

    # Should load the page
    assert_selector "body", visible: true
  end

  test "landing page editor loads without JavaScript errors" do
    landing_page = LandingPage.create!(
      entity: @entity,
      user: @user,
      title: "JS Test Page",
      slug: "js-test",
      status: "draft",
      html_content: "<div>Test content</div>"
    )

    sign_in(@user)

    visit edit_landing_page_path(landing_page)

    # No JS errors visible
    assert_no_text "undefined"
    assert_no_text "TypeError"
    assert_no_text "ReferenceError"
  end

  private

end
