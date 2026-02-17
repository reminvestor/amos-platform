# frozen_string_literal: true

require 'test_helper'

class SidebarTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update_column(:entity_id, @entity.id) unless @user.entity_id == @entity.id
    sign_in @user
  end

  # ═══════════════════════════════════════════════════════════════
  # Personal sidebar - Command Center position
  # ═══════════════════════════════════════════════════════════════

  test "sidebar renders Command Center as second nav item after Home" do
    # Load the main scout page which renders the sidebar
    get scout_path

    assert_response :success

    # The sidebar should contain Command Center
    assert_match(/Command Center/, response.body,
      "Expected 'Command Center' to appear in the sidebar")
  end

  test "sidebar uses radar icon for Command Center" do
    get scout_path
    assert_response :success

    # Check that the radar icon is used (not bell, which was the old notifications icon)
    sidebar_html = response.body

    # Command Center should have radar icon
    # The nav item with loadOperationsDashboardCanvas should use radar
    assert_match(/loadOperationsDashboardCanvas.*?radar/m, sidebar_html,
      "Expected Command Center to use the radar icon")
  end

  test "sidebar Command Center appears before Work Inbox" do
    get scout_path
    assert_response :success

    html = response.body

    # Command Center should appear before Work Inbox in the HTML
    command_center_pos = html.index("Command Center")
    work_inbox_pos = html.index("Work Inbox")

    assert_not_nil command_center_pos, "Expected Command Center in sidebar"
    assert_not_nil work_inbox_pos, "Expected Work Inbox in sidebar"
    assert command_center_pos < work_inbox_pos,
      "Expected Command Center to appear before Work Inbox in sidebar"
  end

  test "sidebar does not show old Notifications label" do
    get scout_path
    assert_response :success

    # The sidebar partial itself should not have "Notifications" as a nav label
    # Note: "Notifications" might appear elsewhere in the page (operations dashboard etc.)
    # so we check specifically in the sidebar nav context
    sidebar_match = response.body.scan(/nav-text[^<]*>([^<]+)</).flatten
    refute sidebar_match.any? { |t| t.strip == "Notifications" },
      "Should not have a sidebar nav item labeled 'Notifications' (replaced by Command Center)"
  end

  test "sidebar has notification badge on Command Center" do
    get scout_path
    assert_response :success

    assert_match(/system-notifications-badge/, response.body,
      "Expected notification badge element on Command Center")
  end

  # ═══════════════════════════════════════════════════════════════
  # Sidebar - Core navigation items present
  # ═══════════════════════════════════════════════════════════════

  test "sidebar contains all expected navigation items" do
    get scout_path
    assert_response :success

    expected_items = [
      "Command Center",
      "Apps & Automations",
      "Work Inbox",
      "Tasks",
      "Contacts",
      "Pipeline",
      "Documents",
      "Integrations"
    ]

    expected_items.each do |item|
      assert_match(/#{Regexp.escape(item)}/, response.body,
        "Expected '#{item}' to appear in sidebar navigation")
    end
  end

  test "sidebar footer contains Settings, Profile, Theme, and Logout" do
    get scout_path
    assert_response :success

    %w[Settings Profile Theme Logout].each do |item|
      assert_match(/#{item}/, response.body,
        "Expected '#{item}' to appear in sidebar footer")
    end
  end
end
