# frozen_string_literal: true

require "test_helper"

class V3::SystemPromptBuilderTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @builder = V3::SystemPromptBuilder.new(user: @user, entity: @entity)
  end

  test "builds a system prompt" do
    prompt = @builder.build

    assert prompt.is_a?(String)
    assert prompt.length > 100, "Prompt should be substantial, got #{prompt.length} chars"
  end

  test "includes core identity" do
    prompt = @builder.build

    # Should include AMOS identity
    assert_match /Amos|AMOS|Orchestrator/i, prompt
  end

  test "includes V3 tool instructions" do
    prompt = @builder.build

    assert_match /platform_query/, prompt
    assert_match /platform_create/, prompt
    assert_match /platform_update/, prompt
    assert_match /platform_execute/, prompt
    assert_match /discover/, prompt
    assert_match /bash/, prompt
  end

  test "includes user context" do
    prompt = @builder.build

    assert_match /Current User/i, prompt
  end

  test "includes datetime" do
    prompt = @builder.build

    # Should have a date
    assert_match /\d{4}/, prompt  # Year
  end

  test "includes canvas context when provided" do
    prompt = @builder.build(current_canvas: "landing_page_editor")

    assert_match /landing page/i, prompt
  end

  test "works without canvas" do
    prompt = @builder.build(current_canvas: nil)

    assert prompt.is_a?(String)
    assert prompt.length > 0
  end

  test "accepts intent mode" do
    prompt = @builder.build(intent_mode: :create)

    assert prompt.is_a?(String)
  end

  test "does not reference deprecated concepts" do
    prompt = @builder.build(message: "help me build something")

    assert_no_match /design_studio/, prompt
    assert_no_match /plan_design/, prompt
    assert_no_match /build_design/, prompt
    assert_no_match /workflow_designer/, prompt
    assert_no_match /app_designer/, prompt
  end

  test "mentions automation not workflow for creation" do
    prompt = @builder.build
    # Should mention automation as the creation concept
    assert_match /automation/i, prompt
  end

  test "mentions browser_use tool" do
    prompt = @builder.build
    assert_match /browser_use/, prompt
  end

  test "prompt is under 15K tokens (rough estimate)" do
    prompt = @builder.build(
      current_canvas: "dashboard",
      message: "show me my contacts"
    )

    # Rough estimate: 4 chars per token
    estimated_tokens = prompt.length / 4
    assert estimated_tokens < 15_000,
      "Prompt too large: ~#{estimated_tokens} tokens (#{prompt.length} chars)"
  end
end
