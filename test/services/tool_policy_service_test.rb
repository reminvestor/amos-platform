# frozen_string_literal: true

require "test_helper"

class ToolPolicyServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @user = users(:one)
  end

  test "check returns requires_confirmation for write operations by default" do
    result = ToolPolicyService.check(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      args: { object_type: "contact" }
    )

    assert result[:allowed]
    assert result[:requires_confirmation]
    assert_equal "write", result[:action]
  end

  test "check returns no confirmation for read operations" do
    result = ToolPolicyService.check(
      entity: @entity,
      user: @user,
      tool_name: "get_data",
      args: { query: "contacts" }
    )

    assert result[:allowed]
    assert_not result[:requires_confirmation]
    assert_equal "read", result[:action]
  end

  test "check includes action description for sensitive tools" do
    result = ToolPolicyService.check(
      entity: @entity,
      user: @user,
      tool_name: "send_email",
      args: { recipient: "test@example.com", subject: "Hello" }
    )

    assert result[:requires_confirmation]
    assert result[:action_description].present?
    assert result[:action_description].include?("test@example.com")
  end

  test "get_policy returns default policy for known tools" do
    policy = ToolPolicyService.get_policy(@entity, "send_email")

    assert policy.present?
    assert policy[:requires_confirmation]
    assert_equal "execute", policy[:action]
    assert_equal "communication", policy[:category]
  end

  test "get_policy returns nil for unknown tools with no inference" do
    # Custom tool name that doesn't match any pattern
    policy = ToolPolicyService.get_policy(@entity, "unknown_custom_tool_xyz")
    assert_nil policy
  end

  test "get_policy infers read policy for get_* tools" do
    policy = ToolPolicyService.get_policy(@entity, "get_some_custom_data")

    assert policy.present?
    assert_not policy[:requires_confirmation]
    assert_equal "read", policy[:action]
    assert_equal :inferred, policy[:source]
  end

  test "recently_confirmed? returns false when not confirmed" do
    result = ToolPolicyService.recently_confirmed?(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      args: { test: true }
    )

    assert_not result
  end

  test "record_confirmation stores and recalls confirmation" do
    # Use a memory store for this test to ensure caching works
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    
    args = { object_type: "contact", name: "Test" }
    
    ToolPolicyService.record_confirmation(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      args: args
    )

    result = ToolPolicyService.recently_confirmed?(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      args: args
    )

    assert result
  ensure
    Rails.cache = original_cache
  end

  test "all_policies_for_entity returns combined defaults and custom" do
    policies = ToolPolicyService.all_policies_for_entity(@entity)

    assert policies.is_a?(Hash)
    assert policies["create_object"].present?
    assert policies["get_data"].present?
    assert policies["send_email"].present?
  end

  test "update_policy creates entity-specific override" do
    # Initially uses default
    initial = ToolPolicyService.get_policy(@entity, "create_object")
    assert initial[:requires_confirmation]

    # Create override to not require confirmation
    ToolPolicyService.update_policy(
      entity: @entity,
      tool_name: "create_object",
      requires_confirmation: false
    )

    # Now should use custom rule
    updated = ToolPolicyService.get_policy(@entity, "create_object")
    assert_not updated[:requires_confirmation]
    assert_equal :entity_rule, updated[:source]

    # Clean up
    PolicyRule.where(entity: @entity, resource_type: 'Tool', resource_id: 'create_object').destroy_all
  end

  test "check respects entity-specific override" do
    # Create override
    ToolPolicyService.update_policy(
      entity: @entity,
      tool_name: "create_object",
      requires_confirmation: false
    )

    result = ToolPolicyService.check(
      entity: @entity,
      user: @user,
      tool_name: "create_object",
      args: { object_type: "contact" }
    )

    assert result[:allowed]
    assert_not result[:requires_confirmation]

    # Clean up
    PolicyRule.where(entity: @entity, resource_type: 'Tool', resource_id: 'create_object').destroy_all
  end

  test "check includes untrusted sources when present" do
    data_sources = [
      { source: :email, trust_level: :untrusted },
      { source: :user_prompt, trust_level: :trusted }
    ]

    result = ToolPolicyService.check(
      entity: @entity,
      user: @user,
      tool_name: "send_email",
      args: { recipient: "test@example.com" },
      data_sources: data_sources
    )

    assert result[:requires_confirmation]
    assert result[:untrusted_sources].present?
    assert_equal 1, result[:untrusted_sources].length
    assert_equal :email, result[:untrusted_sources].first[:source]
  end
end
