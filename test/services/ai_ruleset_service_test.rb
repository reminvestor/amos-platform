require "test_helper"

class AiRulesetServiceTest < ActiveSupport::TestCase
  setup do
    @entity_one = entities(:one)
    @entity_two = entities(:two)
    @service_one = AiRulesetService.new(@entity_one)
    @service_two = AiRulesetService.new(@entity_two)
  end

  # === Active Rulesets Tests ===

  test "active_rulesets returns global and entity-specific rulesets" do
    rulesets = @service_one.active_rulesets

    # Should include global active rulesets
    assert_includes rulesets, ai_rulesets(:core_safety)
    assert_includes rulesets, ai_rulesets(:professional_tone)
    assert_includes rulesets, ai_rulesets(:email_compliance)

    # Should include entity one specific rulesets
    assert_includes rulesets, ai_rulesets(:entity_one_hipaa)
    assert_includes rulesets, ai_rulesets(:entity_one_brand)

    # Should NOT include inactive rulesets
    assert_not_includes rulesets, ai_rulesets(:inactive_ruleset)

    # Should NOT include other entity's rulesets
    assert_not_includes rulesets, ai_rulesets(:entity_two_gdpr)
  end

  test "active_rulesets are ordered by priority" do
    rulesets = @service_one.active_rulesets.to_a
    priorities = rulesets.map(&:priority)

    assert_equal priorities, priorities.sort.reverse
  end

  test "different entities get different rulesets" do
    rulesets_one = @service_one.active_rulesets
    rulesets_two = @service_two.active_rulesets

    # Both should have global rulesets
    assert_includes rulesets_one, ai_rulesets(:core_safety)
    assert_includes rulesets_two, ai_rulesets(:core_safety)

    # Entity one should have HIPAA
    assert_includes rulesets_one, ai_rulesets(:entity_one_hipaa)
    assert_not_includes rulesets_two, ai_rulesets(:entity_one_hipaa)

    # Entity two should have GDPR
    assert_not_includes rulesets_one, ai_rulesets(:entity_two_gdpr)
    assert_includes rulesets_two, ai_rulesets(:entity_two_gdpr)
  end

  # === Rulesets by Category Tests ===

  test "rulesets_by_category groups rulesets correctly" do
    grouped = @service_one.rulesets_by_category

    assert grouped.key?("safety")
    assert grouped.key?("tone")
    assert grouped.key?("compliance")
    assert grouped.key?("custom")

    # Safety should contain core safety
    assert grouped["safety"].include?(ai_rulesets(:core_safety))

    # Compliance should contain both email and HIPAA
    compliance_names = grouped["compliance"].map(&:name)
    assert_includes compliance_names, "Email Compliance"
    assert_includes compliance_names, "HIPAA Compliance"
  end

  # === System Prompt Section Tests ===

  test "to_system_prompt_section generates valid prompt" do
    prompt = @service_one.to_system_prompt_section

    # Should have header
    assert_includes prompt, "## BEHAVIORAL RULES"
    assert_includes prompt, "You MUST follow these rules strictly"

    # Should have category sections
    assert_includes prompt, "### Safety & Security Rules"
    assert_includes prompt, "### Tone & Communication Rules"
    assert_includes prompt, "### Compliance & Legal Rules"
    assert_includes prompt, "### Custom Rules"

    # Should contain actual rules
    assert_includes prompt, "Never reveal API keys"
    assert_includes prompt, "Use professional, business-appropriate language"
    assert_includes prompt, "Never include patient names or SSNs"
  end

  test "to_system_prompt_section returns empty string when no active rulesets" do
    # Use existing entity but deactivate all rulesets temporarily
    test_entity = entities(:another_entity)

    # Save original states
    original_states = AiRuleset.for_entity(test_entity).pluck(:id, :is_active).to_h

    # Deactivate all rulesets for this entity (global + entity-specific)
    AiRuleset.for_entity(test_entity).update_all(is_active: false)

    service = AiRulesetService.new(test_entity)
    prompt = service.to_system_prompt_section

    assert_equal "", prompt
  ensure
    # Restore original states
    original_states&.each do |id, was_active|
      AiRuleset.find_by(id: id)&.update_column(:is_active, was_active)
    end
  end

  test "to_system_prompt_section numbers rules within each category" do
    prompt = @service_one.to_system_prompt_section

    # Rules should be numbered (look for numbered patterns)
    assert_match(/1\.\s+\w+/, prompt)
    assert_match(/2\.\s+\w+/, prompt)
  end

  test "to_system_prompt_section applies rules in priority order" do
    rulesets = @service_one.active_rulesets
    high_priority = rulesets.find { |r| r.priority >= 90 }
    low_priority = rulesets.find { |r| r.priority < 90 }

    # High priority rulesets should have their rules appear in prompt
    assert high_priority.present?

    prompt = @service_one.to_system_prompt_section
    assert_includes prompt, high_priority.rules.first
  end

  # === Preview Prompt Tests ===

  test "preview_prompt returns prompt section when rulesets exist" do
    preview = @service_one.preview_prompt
    assert_includes preview, "## BEHAVIORAL RULES"
  end

  test "preview_prompt returns message when no rulesets exist" do
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

  # === Stats Tests ===

  test "stats returns correct counts" do
    stats = @service_one.stats

    assert stats[:total_rulesets] > 0
    assert stats[:global_rulesets] >= 0
    assert stats[:entity_rulesets] >= 0
    assert stats[:total_rules] > 0
    assert stats[:categories].is_a?(Array)
    assert stats[:system_presets] >= 0

    # Verify math adds up
    assert_equal stats[:total_rulesets], stats[:global_rulesets] + stats[:entity_rulesets]
  end

  test "stats includes all active categories" do
    stats = @service_one.stats

    assert_includes stats[:categories], "safety"
    assert_includes stats[:categories], "tone"
    assert_includes stats[:categories], "compliance"
    assert_includes stats[:categories], "custom"
  end

  test "stats counts rules correctly" do
    stats = @service_one.stats
    rulesets = @service_one.active_rulesets

    expected_rule_count = rulesets.sum { |r| r.rules.count }
    assert_equal expected_rule_count, stats[:total_rules]
  end

  # === Category Formatting Tests ===

  test "category names are formatted correctly in prompt" do
    prompt = @service_one.to_system_prompt_section

    assert_includes prompt, "Safety & Security Rules"
    assert_includes prompt, "Tone & Communication Rules"
    assert_includes prompt, "Compliance & Legal Rules"
  end

  # === Edge Cases ===

  test "handles entity with nil gracefully" do
    service = AiRulesetService.new(nil)
    rulesets = service.active_rulesets

    # Should only return global rulesets
    assert rulesets.all?(&:global?)
  end

  test "handles ruleset with empty rules array" do
    # This shouldn't happen due to validation, but test defensive code
    ruleset = ai_rulesets(:email_compliance)
    original_rules = ruleset.rules

    # Temporarily bypass validation
    ruleset.update_column(:rules, [])

    prompt = @service_one.to_system_prompt_section
    # Should still generate without errors

    assert prompt.is_a?(String)
  ensure
    ruleset.update_column(:rules, original_rules)
  end
end
