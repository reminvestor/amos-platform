# frozen_string_literal: true

require 'test_helper'

class AgentPluginsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update_column(:entity_id, @entity.id) unless @user.entity_id == @entity.id

    # Agent plugins routes are inside the app subdomain constraint.
    # SubdomainConfig.app_subdomains includes "" (empty) in test env.
    host! "example.com"

    # Stub asset helpers that may fail in test/CI env without compiled assets
    ActionView::Base.any_instance.stubs(:javascript_include_tag).returns("")

    sign_in @user

    @slug_suffix = SecureRandom.hex(4)

    # Create an imported skill (SKILL.md format)
    @skill = AgentPlugin.create!(
      name: "Test Skill",
      slug: "test_skill_#{@slug_suffix}",
      role: "executor",
      description: "An imported skill for testing",
      status: "draft",
      entity: @entity,
      user: @user,
      configuration: { 'skill_format' => 'claude_skill_md' }
    )

    # Create a standard loadout
    @loadout = AgentPlugin.create!(
      name: "Test Loadout",
      slug: "test_loadout_#{@slug_suffix}",
      role: "executor",
      description: "A custom loadout for testing",
      status: "active",
      entity: @entity,
      user: @user
    )
  end

  # ═══════════════════════════════════════════════════════════════
  # UPDATE - JSON responses for skill toggle from settings canvas
  # ═══════════════════════════════════════════════════════════════

  test "update via JSON activates a draft skill" do
    assert_equal "draft", @skill.status

    patch agent_plugin_path(@skill),
      params: { agent_plugin: { status: "active" } },
      as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body['success']
    assert_equal "active", body['status']
    assert_equal "active", @skill.reload.status
  end

  test "update via JSON deactivates an active skill" do
    @skill.update!(status: "active")

    patch agent_plugin_path(@skill),
      params: { agent_plugin: { status: "draft" } },
      as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body['success']
    assert_equal "draft", body['status']
    assert_equal "draft", @skill.reload.status
  end

  test "update via JSON can rename a skill" do
    patch agent_plugin_path(@skill),
      params: { agent_plugin: { name: "Renamed Skill" } },
      as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body['success']
    assert_equal "Renamed Skill", @skill.reload.name
  end

  test "update via HTML redirects to show page" do
    patch agent_plugin_path(@skill),
      params: { agent_plugin: { status: "active" } }

    assert_response :redirect
    assert_redirected_to agent_plugin_path(@skill)
    assert_equal "active", @skill.reload.status
  end

  # ═══════════════════════════════════════════════════════════════
  # DESTROY - JSON responses for skill delete from settings canvas
  # ═══════════════════════════════════════════════════════════════

  test "destroy via JSON deletes a skill and returns success" do
    skill_id = @skill.id

    assert_difference('AgentPlugin.count', -1) do
      delete agent_plugin_path(@skill), as: :json
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert body['success']
    assert_nil AgentPlugin.find_by(id: skill_id)
  end

  test "destroy via HTML redirects to index" do
    assert_difference('AgentPlugin.count', -1) do
      delete agent_plugin_path(@loadout)
    end

    assert_response :redirect
    assert_redirected_to agent_plugins_path
  end

  # ═══════════════════════════════════════════════════════════════
  # INDEX - lists skills and loadouts
  # ═══════════════════════════════════════════════════════════════

  test "index page loads successfully" do
    get agent_plugins_path
    assert_response :success
  end

  test "index shows both skills and loadouts" do
    get agent_plugins_path
    assert_response :success
    assert_match @skill.name, response.body
    assert_match @loadout.name, response.body
  end

  # ═══════════════════════════════════════════════════════════════
  # SCOPING - cannot access other entity's plugins
  # ═══════════════════════════════════════════════════════════════

  test "cannot update another entity's skill via JSON" do
    other_entity = Entity.create!(name: "Other Entity #{SecureRandom.hex(4)}", subdomain: "other#{SecureRandom.hex(4)}")
    other_skill = AgentPlugin.create!(
      name: "Other Skill",
      slug: "other_skill_#{@slug_suffix}",
      role: "executor",
      status: "draft",
      entity: other_entity
    )

    patch agent_plugin_path(other_skill),
      params: { agent_plugin: { status: "active" } },
      as: :json

    # Should get 404 because set_agent scopes by current_entity
    assert_response :not_found
    assert_equal "draft", other_skill.reload.status, "Other entity's skill should not be modified"
  end

  test "cannot delete another entity's skill via JSON" do
    other_entity = Entity.create!(name: "Other Entity #{SecureRandom.hex(4)}", subdomain: "otherx#{SecureRandom.hex(4)}")
    other_skill = AgentPlugin.create!(
      name: "Other Skill Delete",
      slug: "other_skill_del_#{@slug_suffix}",
      role: "executor",
      status: "draft",
      entity: other_entity
    )

    assert_no_difference('AgentPlugin.count') do
      delete agent_plugin_path(other_skill), as: :json
    end

    # Should get 404 because set_agent scopes by current_entity
    assert_response :not_found
  end
end
