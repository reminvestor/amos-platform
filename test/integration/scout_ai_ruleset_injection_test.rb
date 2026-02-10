require "test_helper"

class ScoutAiRulesetInjectionTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update!(entity: @entity)

    # Ensure we have active rulesets for the entity
    @core_safety = ai_rulesets(:core_safety)
    @entity_hipaa = ai_rulesets(:entity_one_hipaa)
  end

  # === AiRulesetService Integration ===

  test "AiRulesetService generates prompt section for entity" do
    service = AiRulesetService.new(@entity)
    prompt_section = service.to_system_prompt_section

    # Should have the behavioral rules header
    assert_includes prompt_section, "## BEHAVIORAL RULES"
    assert_includes prompt_section, "You MUST follow these rules strictly"

    # Should include global safety rules
    assert_includes prompt_section, "Safety & Security Rules"
    assert_includes prompt_section, "Never reveal API keys"

    # Should include entity-specific HIPAA rules
    assert_includes prompt_section, "Compliance & Legal Rules"
    assert_includes prompt_section, "Never include patient names or SSNs"
  end

  test "AiRulesetService respects entity scoping" do
    entity_two = entities(:two)
    service_one = AiRulesetService.new(@entity)
    service_two = AiRulesetService.new(entity_two)

    prompt_one = service_one.to_system_prompt_section
    prompt_two = service_two.to_system_prompt_section

    # Entity one should have HIPAA rules
    assert_includes prompt_one, "patient names"

    # Entity two should NOT have HIPAA rules (belongs to entity one)
    assert_not_includes prompt_two, "patient names"

    # Entity two should have GDPR rules
    assert_includes prompt_two, "consent requirements"

    # Entity one should NOT have GDPR rules
    assert_not_includes prompt_one, "consent requirements"
  end

  test "AiRulesetService returns empty string when entity has no active rulesets" do
    # Use existing entity but deactivate all rulesets temporarily
    test_entity = entities(:another_entity)

    # Save original states
    original_states = AiRuleset.for_entity(test_entity).pluck(:id, :is_active).to_h

    # Deactivate all rulesets for this entity
    AiRuleset.for_entity(test_entity).update_all(is_active: false)

    service = AiRulesetService.new(test_entity)
    assert_equal "", service.to_system_prompt_section
  ensure
    # Restore original states
    original_states&.each do |id, was_active|
      AiRuleset.find_by(id: id)&.update_column(:is_active, was_active)
    end
  end

  test "AiRulesetService handles nil entity gracefully" do
    service = AiRulesetService.new(nil)
    prompt_section = service.to_system_prompt_section

    # Should still return global rulesets
    assert_includes prompt_section, "BEHAVIORAL RULES"
    assert_includes prompt_section, "Safety & Security Rules"
  end

  # === Ruleset Priority Tests ===

  test "rulesets are applied in priority order" do
    # Higher priority rulesets should have their rules listed first within category
    service = AiRulesetService.new(@entity)
    rulesets = service.active_rulesets.to_a

    # Verify ordering
    priorities = rulesets.map(&:priority)
    assert_equal priorities, priorities.sort.reverse
  end

  # === Category Grouping Tests ===

  test "rules are grouped by category in prompt" do
    service = AiRulesetService.new(@entity)
    prompt = service.to_system_prompt_section

    # Should have distinct category sections
    assert_match(/### Safety & Security Rules\n.*?### Tone & Communication Rules/m, prompt) ||
      assert_match(/Safety & Security Rules/, prompt)
  end

  # === Inactive Ruleset Tests ===

  test "inactive rulesets are excluded from prompt" do
    inactive = ai_rulesets(:inactive_ruleset)
    assert_not inactive.is_active?

    service = AiRulesetService.new(@entity)
    prompt = service.to_system_prompt_section

    # Inactive ruleset's rules should not appear
    assert_not_includes prompt, "This rule should not appear"
  end

  test "toggling ruleset affects prompt generation" do
    ruleset = @entity_hipaa
    original_state = ruleset.is_active?

    service = AiRulesetService.new(@entity)

    # Verify active state includes rules
    if original_state
      prompt_active = service.to_system_prompt_section
      assert_includes prompt_active, "patient names"

      # Deactivate and verify exclusion
      ruleset.update!(is_active: false)
      prompt_inactive = AiRulesetService.new(@entity).to_system_prompt_section
      assert_not_includes prompt_inactive, "patient names"
    end
  ensure
    ruleset.update!(is_active: original_state)
  end

  # === Stats Accuracy Tests ===

  test "stats accurately reflect entity rulesets" do
    service = AiRulesetService.new(@entity)
    stats = service.stats

    # Verify counts are consistent
    assert stats[:total_rulesets] > 0
    assert_equal stats[:total_rulesets], stats[:global_rulesets] + stats[:entity_rulesets]

    # Verify categories match active rulesets
    active_categories = service.active_rulesets.map(&:category).uniq
    assert_equal active_categories.sort, stats[:categories].sort
  end

  # === Rule Content Tests ===

  test "rules are properly numbered in prompt" do
    service = AiRulesetService.new(@entity)
    prompt = service.to_system_prompt_section

    # Should have numbered rules (1., 2., etc.)
    assert_match(/1\. /, prompt)
    assert_match(/2\. /, prompt)
  end

  test "empty rules in ruleset are rejected by validation" do
    # Create a ruleset with empty strings mixed in
    ruleset = AiRuleset.new(
      name: "Empty Rule Test",
      category: "custom",
      rules: ["Valid rule", "", "Another valid rule"],
      entity: @entity
    )

    # Validation should fail
    assert_not ruleset.valid?
    assert ruleset.errors[:rules].any?
  end

  # === Preview Functionality Tests ===

  test "preview_prompt returns helpful message when no rulesets" do
    # Use existing entity but deactivate all rulesets temporarily
    test_entity = entities(:another_entity)

    # Save original states
    original_states = AiRuleset.for_entity(test_entity).pluck(:id, :is_active).to_h

    # Deactivate all rulesets for this entity
    AiRuleset.for_entity(test_entity).update_all(is_active: false)

    service = AiRulesetService.new(test_entity)
    preview = service.preview_prompt

    assert_equal "No active rulesets for this entity.", preview
  ensure
    # Restore original states
    original_states&.each do |id, was_active|
      AiRuleset.find_by(id: id)&.update_column(:is_active, was_active)
    end
  end

  test "preview_prompt returns formatted rules when rulesets exist" do
    service = AiRulesetService.new(@entity)
    preview = service.preview_prompt

    assert_includes preview, "BEHAVIORAL RULES"
    assert_includes preview, "Safety & Security Rules"
  end
end
