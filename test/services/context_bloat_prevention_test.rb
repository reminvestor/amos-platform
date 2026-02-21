# frozen_string_literal: true

require "test_helper"

class ContextBloatPreventionTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ═══════════════════════════════════════════════════════════════
  # SYSTEM PROMPT — NO DUPLICATION BETWEEN CORE_IDENTITY AND TOOL INSTRUCTIONS
  # ═══════════════════════════════════════════════════════════════

  test "build_tool_instructions does not duplicate Tool Selection section from CORE_IDENTITY" do
    builder = V3::SystemPromptBuilder.new(user: @user, entity: @entity)
    tool_instructions = builder.send(:build_tool_instructions)

    refute_match /## Tool Selection/i, tool_instructions,
      "Tool Selection is already in CORE_IDENTITY — should not be duplicated"
  end

  test "build_tool_instructions does not duplicate How to Respond section from CORE_IDENTITY" do
    builder = V3::SystemPromptBuilder.new(user: @user, entity: @entity)
    tool_instructions = builder.send(:build_tool_instructions)

    # CORE_IDENTITY has "## HOW YOU RESPOND" — tool_instructions should not repeat it
    refute_match /## How to Respond/i, tool_instructions,
      "How to Respond is already in CORE_IDENTITY — should not be duplicated"
  end

  test "CORE_IDENTITY contains tool descriptions" do
    identity = AmosIdentity::CORE_IDENTITY

    assert_match /platform_create/, identity
    assert_match /platform_update/, identity
    assert_match /platform_query/, identity
    assert_match /platform_execute/, identity
    assert_match /web_search/, identity
    assert_match /bash/, identity
    assert_match /browser_use/, identity
    assert_match /load_canvas/, identity
  end

  test "build_tool_instructions still contains unique content not in CORE_IDENTITY" do
    builder = V3::SystemPromptBuilder.new(user: @user, entity: @entity)
    tool_instructions = builder.send(:build_tool_instructions)

    assert_match /Tool Efficiency/, tool_instructions
    assert_match /Quick Asset Type Guide/, tool_instructions
    assert_match /Show Visual Assets/, tool_instructions
    assert_match /Freeform Canvas/, tool_instructions
  end

  test "full prompt does not contain duplicate tool listing sections" do
    builder = V3::SystemPromptBuilder.new(user: @user, entity: @entity)
    prompt = builder.build

    # Count occurrences of key tool descriptions
    # Each tool should appear in CORE_IDENTITY's "YOUR TOOLS" section
    # but NOT again in a separate "Tool Selection" section
    tool_selection_count = prompt.scan(/## Tool Selection/i).length
    assert_equal 0, tool_selection_count,
      "Should have 0 'Tool Selection' headings (tools listed in CORE_IDENTITY only)"
  end

  test "full prompt is smaller after deduplication" do
    builder = V3::SystemPromptBuilder.new(user: @user, entity: @entity)
    prompt = builder.build

    # The prompt should be well under 12K tokens (rough: 4 chars/token)
    estimated_tokens = prompt.length / 4
    assert estimated_tokens < 12_000,
      "Prompt should be under 12K tokens after dedup, got ~#{estimated_tokens} tokens (#{prompt.length} chars)"
  end

  # ═══════════════════════════════════════════════════════════════
  # SKILL CONTENT TRUNCATION
  # ═══════════════════════════════════════════════════════════════

  test "skill content under limit is not truncated" do
    short_content = "This is a short skill." * 10  # ~220 chars
    result = SkillLibraryService.send(:truncate_skill_content, short_content)

    assert_equal short_content, result
  end

  test "skill content over limit is truncated" do
    long_content = "Integration skill line.\n" * 200  # ~4,600 chars
    result = SkillLibraryService.send(:truncate_skill_content, long_content)

    assert result.length < long_content.length,
      "Should be truncated. Original: #{long_content.length}, Result: #{result.length}"
    assert result.length <= SkillLibraryService::MAX_SKILL_CONTENT_CHARS + 100,
      "Should be close to MAX_SKILL_CONTENT_CHARS (#{SkillLibraryService::MAX_SKILL_CONTENT_CHARS})"
    assert_match /truncated for brevity/, result
  end

  test "skill truncation breaks at newline boundary" do
    lines = (1..200).map { |i| "Line #{i}: Some skill content here" }
    long_content = lines.join("\n")
    result = SkillLibraryService.send(:truncate_skill_content, long_content)

    # Should not cut in the middle of a line (when possible)
    content_before_notice = result.split("_(Skill truncated").first.strip
    assert content_before_notice.end_with?("here"),
      "Should break at a line boundary, not mid-line"
  end

  test "nil and blank skill content is passed through" do
    assert_nil SkillLibraryService.send(:truncate_skill_content, nil)
    assert_equal "", SkillLibraryService.send(:truncate_skill_content, "")
  end

  test "build_skill_block applies truncation to each skill" do
    huge_skill = {
      name: "Huge Skill",
      content: "x" * 5000
    }

    block = SkillLibraryService.send(:build_skill_block, [huge_skill])

    assert block.length < 5000 + 200,
      "Block should be truncated. Got #{block.length} chars"
    assert_match /truncated for brevity/, block
  end

  test "MAX_SKILL_CONTENT_CHARS is defined and reasonable" do
    assert_equal 2000, SkillLibraryService::MAX_SKILL_CONTENT_CHARS
  end

  # ═══════════════════════════════════════════════════════════════
  # INTEGRATION CONTEXT — COMPACT SUMMARY
  # ═══════════════════════════════════════════════════════════════

  test "integration context is compact with no full schemas" do
    integration = Integration.create!(
      name: "Bloat Test Integration",
      slug: "bloat_test_#{SecureRandom.hex(4)}",
      is_active: true,
      auth_type: "api_key",
      api_base_url: "https://api.example.com",
      category: "custom"
    )
    connection = Connection.create!(
      user: @user,
      entity: @entity,
      integration: integration,
      name: "Test Connection",
      status: :connected
    )

    service = DynamicContextService.new(user: @user, entity: @entity)
    context = service.send(:build_integration_context)

    assert context.present?, "Should have context with active connection"
    refute_match /required:/, context,
      "Should not dump full required field lists"
    refute_match /optional:/, context,
      "Should not dump full optional field lists"
    refute_match /Example call:/i, context,
      "Should not include example calls — model can look up via platform_query"
    assert_match /platform_query.*integration_actions/i, context,
      "Should tell the model how to look up full details"
  ensure
    connection&.destroy
    integration&.destroy
  end

  test "integration context includes usage instructions" do
    integration = Integration.create!(
      name: "Usage Test Integration",
      slug: "usage_test_#{SecureRandom.hex(4)}",
      is_active: true,
      auth_type: "api_key",
      api_base_url: "https://api.example.com",
      category: "custom"
    )
    connection = Connection.create!(
      user: @user,
      entity: @entity,
      integration: integration,
      name: "Test Connection",
      status: :connected
    )

    service = DynamicContextService.new(user: @user, entity: @entity)
    context = service.send(:build_integration_context)

    assert context.present?, "Should have integration context with active connection"
    assert_match /CONNECTED INTEGRATIONS/, context
    assert_match /platform_execute/, context
    assert_match /platform_query.*integration_actions/, context
    assert_match /#{integration.name}/, context
  ensure
    connection&.destroy
    integration&.destroy
  end

  test "integration context returns nil when no connections" do
    other_entity = entities(:two)
    other_user = users(:two)
    service = DynamicContextService.new(user: other_user, entity: other_entity)

    Connection.where(entity: other_entity, user: other_user).destroy_all

    context = service.send(:build_integration_context)
    assert_nil context, "Should return nil when no connections exist"
  end

  # ═══════════════════════════════════════════════════════════════
  # OVERALL PROMPT SIZE BUDGET
  # ═══════════════════════════════════════════════════════════════

  test "system prompt with all sections stays under token budget" do
    builder = V3::SystemPromptBuilder.new(user: @user, entity: @entity)

    prompt = builder.build(
      current_canvas: "landing_page_editor",
      message: "help me edit my landing page"
    )

    estimated_tokens = prompt.length / 4
    assert estimated_tokens < 15_000,
      "Full prompt (with canvas + skills) should be under 15K tokens. " \
      "Got ~#{estimated_tokens} tokens (#{prompt.length} chars)"
  end

  test "system prompt without skills is lean" do
    builder = V3::SystemPromptBuilder.new(user: @user, entity: @entity)

    prompt = builder.build(message: "hello")

    # For a simple greeting with no skill injection, should be very lean
    estimated_tokens = prompt.length / 4
    assert estimated_tokens < 8_000,
      "Simple prompt (no skills) should be under 8K tokens. " \
      "Got ~#{estimated_tokens} tokens (#{prompt.length} chars)"
  end
end
