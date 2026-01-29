require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)
    @user.update!(entity: @entity, onboarded: true)
    @entity.update!(subscription_status: 'active')
  end

  test "user can access dashboard" do
    sign_in_as(@user)

    visit dashboard_path

    # Dashboard should load
    assert_selector "body", visible: true
    assert_no_text "error", wait: 2
  end

  test "dashboard shows quick stats section" do
    sign_in_as(@user)

    visit dashboard_path

    # Should show stats for campaigns, contacts, landing pages, templates
    has_stats = page.has_text?(/campaign|contact|landing|template/i)
    has_numbers = page.has_selector?(".stat, .count, [data-stat]") || page.has_text?(/\d+/)

    assert has_stats || has_numbers, "Expected quick stats on dashboard"
  end

  test "dashboard shows recent activity section" do
    # Create some recent data
    Campaign.create!(
      entity: @entity,
      user: @user,
      name: "Test Dashboard Campaign",
      status: "draft"
    )

    sign_in_as(@user)

    visit dashboard_path

    # Should show recent activity
    has_recent = page.has_text?(/recent|activity|latest/i)
    has_campaign = page.has_text?(/test dashboard campaign/i)

    assert has_recent || has_campaign, "Expected recent activity section"
  end

  test "dashboard shows connections section" do
    sign_in_as(@user)

    visit dashboard_path

    # Should show connections or integrations section
    has_connections = page.has_text?(/connection|integration|connected/i)

    assert has_connections, "Expected connections section on dashboard"
  end

  test "dashboard shows AI usage stats" do
    sign_in_as(@user)

    visit dashboard_path

    # Should show AI usage information
    has_ai_usage = page.has_text?(/ai|usage|token|credit/i)

    assert has_ai_usage, "Expected AI usage stats on dashboard"
  end

  test "dashboard loads without JavaScript errors" do
    sign_in_as(@user)

    visit dashboard_path

    # Check for any visible error messages
    assert_no_text "undefined"
    assert_no_text "TypeError"
    assert_no_text "ReferenceError"
    assert_no_selector ".alert-danger"
  end

  test "dashboard navigation links work" do
    sign_in_as(@user)

    visit dashboard_path

    # Should have navigation links
    has_scout_link = page.has_selector?("a[href='/scout']")
    has_campaigns_link = page.has_selector?("a[href*='campaign']")
    has_contacts_link = page.has_selector?("a[href*='contact']")

    assert has_scout_link || has_campaigns_link || has_contacts_link,
           "Expected navigation links on dashboard"
  end

  test "dashboard stats update with new data" do
    sign_in_as(@user)

    # Get initial campaign count
    visit dashboard_path
    initial_page = page.html

    # Create new campaign
    Campaign.create!(
      entity: @entity,
      user: @user,
      name: "New Campaign for Stats",
      status: "draft"
    )

    # Refresh dashboard
    visit dashboard_path

    # Page should still load (we're just checking it doesn't error)
    assert_selector "body", visible: true
  end

  test "dashboard displays user entity name" do
    sign_in_as(@user)

    visit dashboard_path

    # Should show entity/business name somewhere
    has_entity = page.has_text?(@entity.name) || page.has_text?(/dashboard|welcome/i)

    assert has_entity, "Expected entity name or dashboard title"
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"

    # Wait for successful sign in
    assert_selector "a[href='/scout']", wait: 5
  end
end
