# frozen_string_literal: true

require 'test_helper'

class SettingsCanvasTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update_column(:entity_id, @entity.id) unless @user.entity_id == @entity.id
    sign_in @user

    @slug_suffix = SecureRandom.hex(4)
  end

  private

  def load_settings_canvas(tab: nil)
    canvas_data = tab ? { tab: tab } : {}
    post scout_load_canvas_path, params: {
      canvas_type: 'settings',
      canvas_data: canvas_data
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body['success'], "Expected load_canvas to succeed"
    body.dig('canvas', 'content') || ''
  end

  public

  # ═══════════════════════════════════════════════════════════════
  # Settings canvas - Skills & Plugins tab
  # ═══════════════════════════════════════════════════════════════

  test "settings canvas loads with skills tab present" do
    html = load_settings_canvas
    assert_match(/settings-tab-skills/, html,
      "Expected Skills & Plugins tab pane to be present in settings canvas")
  end

  test "settings canvas shows import skill form" do
    html = load_settings_canvas(tab: 'skills')

    assert_match(/Import a Skill/, html, "Expected skill import section heading")
    assert_match(/skill-paste-content/, html, "Expected paste textarea")
    assert_match(/skill-url-input/, html, "Expected URL input field")
    assert_match(/skill-file-input/, html, "Expected file upload input")
    assert_match(/settingsImportSkill/, html, "Expected import JS function")
  end

  test "settings canvas lists imported skills" do
    AgentPlugin.create!(
      name: "Imported Test Skill #{@slug_suffix}",
      slug: "imported_test_#{@slug_suffix}",
      role: "executor",
      description: "A test imported skill",
      status: "active",
      entity: @entity,
      user: @user,
      configuration: { 'skill_format' => 'claude_skill_md' }
    )

    html = load_settings_canvas(tab: 'skills')

    assert_match(/Imported Test Skill/, html,
      "Expected the imported skill name to appear")
    assert_match(/Imported Skills/, html,
      "Expected Imported Skills section heading")
  end

  test "settings canvas lists agent loadouts" do
    AgentPlugin.create!(
      name: "Custom Loadout #{@slug_suffix}",
      slug: "custom_loadout_#{@slug_suffix}",
      role: "executor",
      description: "A custom loadout",
      status: "active",
      entity: @entity,
      user: @user
    )

    html = load_settings_canvas(tab: 'skills')

    assert_match(/Custom Loadout/, html,
      "Expected the loadout name to appear")
    assert_match(/Agent Loadouts/, html,
      "Expected Agent Loadouts section heading")
  end

  test "settings canvas shows skill activate/deactivate and delete buttons" do
    AgentPlugin.create!(
      name: "Toggle Skill #{@slug_suffix}",
      slug: "toggle_skill_#{@slug_suffix}",
      role: "executor",
      status: "draft",
      entity: @entity,
      user: @user,
      configuration: { 'skill_format' => 'claude_skill_md' }
    )

    html = load_settings_canvas(tab: 'skills')

    assert_match(/settingsToggleSkillStatus/, html,
      "Expected skill toggle JS function")
    assert_match(/settingsDeleteSkill/, html,
      "Expected skill delete JS function")
  end

  test "settings canvas shows empty state when no skills imported" do
    # Clean out any skills for this entity
    AgentPlugin.where(entity: @entity).where("configuration->>'skill_format' = 'claude_skill_md'").delete_all

    html = load_settings_canvas(tab: 'skills')

    assert_match(/No imported skills yet/, html,
      "Expected empty state message for imported skills")
  end

  test "settings canvas shows import methods: paste, URL, and file upload tabs" do
    html = load_settings_canvas(tab: 'skills')

    assert_match(/skill-paste-tab/, html, "Expected paste sub-tab")
    assert_match(/skill-url-tab/, html, "Expected URL sub-tab")
    assert_match(/skill-file-tab/, html, "Expected file upload sub-tab")
  end

  # ═══════════════════════════════════════════════════════════════
  # Settings canvas - Member Collaboration toggle
  # ═══════════════════════════════════════════════════════════════

  test "settings canvas shows Member Collaboration toggle instead of Slack" do
    html = load_settings_canvas(tab: 'menu')

    assert_match(/Member Collaboration/, html,
      "Expected 'Member Collaboration' label")
    assert_match(/in-app messaging/, html,
      "Expected collaboration description mentioning in-app messaging")
    # Should NOT have old "Slack Notifications" label
    refute_match(/Slack Notifications/, html,
      "Should not show old 'Slack Notifications' label")
  end

  test "settings canvas shows collaboration toggle with messages-square icon" do
    html = load_settings_canvas(tab: 'menu')

    assert_match(/messages-square/, html,
      "Expected messages-square icon for collaboration toggle")
  end

  test "settings canvas collaboration toggle controls slack_notifications_enabled setting" do
    html = load_settings_canvas(tab: 'menu')

    assert_match(/slack_notifications_enabled/, html,
      "Expected toggle to still control slack_notifications_enabled setting under the hood")
  end

  test "settings canvas email notifications toggle has description" do
    html = load_settings_canvas(tab: 'menu')

    assert_match(/email alerts/, html,
      "Expected email notifications description")
  end

  # ═══════════════════════════════════════════════════════════════
  # Settings canvas - Tab structure
  # ═══════════════════════════════════════════════════════════════

  test "settings canvas includes all expected tabs" do
    html = load_settings_canvas

    assert_match(/settings-billing-tab/, html, "Expected billing tab button")
    assert_match(/settings-tools-tab/, html, "Expected tools tab button")
    assert_match(/settings-skills-tab/, html, "Expected skills tab button")
    assert_match(/settings-menu-tab/, html, "Expected menu config tab button")
  end

  test "settings canvas defaults to billing tab active" do
    html = load_settings_canvas

    # The billing tab pane should have "show active" class
    # HTML: <div class="tab-pane fade show active" id="settings-tab-billing" ...>
    assert_match(/settings-tab-billing/, html, "Expected billing tab pane present")
    # Verify billing tab pane is active (class contains "show active")
    billing_pane = html[/class="[^"]*show active[^"]*"[^>]*id="settings-tab-billing"|id="settings-tab-billing"[^>]*class="[^"]*show active[^"]*"/]
    assert billing_pane, "Expected billing tab pane to be active by default"
  end

  test "settings canvas activates skills tab when requested" do
    html = load_settings_canvas(tab: 'skills')

    assert_match(/settings-tab-skills/, html, "Expected skills tab pane present")
    skills_pane = html[/class="[^"]*show active[^"]*"[^>]*id="settings-tab-skills"|id="settings-tab-skills"[^>]*class="[^"]*show active[^"]*"/]
    assert skills_pane, "Expected skills tab pane to be active when tab=skills"
  end

  test "settings canvas activates menu tab when requested" do
    html = load_settings_canvas(tab: 'menu')

    assert_match(/settings-tab-menu/, html, "Expected menu tab pane present")
    menu_pane = html[/class="[^"]*show active[^"]*"[^>]*id="settings-tab-menu"|id="settings-tab-menu"[^>]*class="[^"]*show active[^"]*"/]
    assert menu_pane, "Expected menu config tab pane to be active when tab=menu"
  end
end
