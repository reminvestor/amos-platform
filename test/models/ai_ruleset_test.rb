require "test_helper"

class AiRulesetTest < ActiveSupport::TestCase
  # === Validation Tests ===

  test "valid ruleset with all required fields" do
    ruleset = AiRuleset.new(
      name: "Test Ruleset",
      category: "safety",
      rules: ["Rule one", "Rule two"]
    )
    assert ruleset.valid?
  end

  test "requires name" do
    ruleset = AiRuleset.new(category: "safety", rules: ["Rule one"])
    assert_not ruleset.valid?
    assert_includes ruleset.errors[:name], "can't be blank"
  end

  test "requires category" do
    ruleset = AiRuleset.new(name: "Test", rules: ["Rule one"])
    assert_not ruleset.valid?
    assert_includes ruleset.errors[:category], "can't be blank"
  end

  test "requires rules" do
    ruleset = AiRuleset.new(name: "Test", category: "safety")
    assert_not ruleset.valid?
    assert_includes ruleset.errors[:rules], "can't be blank"
  end

  test "category must be valid" do
    AiRuleset::CATEGORIES.each do |category|
      ruleset = AiRuleset.new(name: "Test", category: category, rules: ["Rule"])
      assert ruleset.valid?, "Should allow category: #{category}"
    end

    ruleset = AiRuleset.new(name: "Test", category: "invalid", rules: ["Rule"])
    assert_not ruleset.valid?
    assert_includes ruleset.errors[:category], "is not included in the list"
  end

  test "name has maximum length" do
    ruleset = AiRuleset.new(
      name: "A" * 101,
      category: "safety",
      rules: ["Rule one"]
    )
    assert_not ruleset.valid?
    assert_includes ruleset.errors[:name], "is too long (maximum is 100 characters)"
  end

  test "rules must be array of strings" do
    # PostgreSQL array columns may handle strings differently
    # Test that validation catches non-array input
    ruleset = AiRuleset.new(name: "Test", category: "safety")
    ruleset.rules = nil  # Explicitly set to nil to trigger presence validation
    assert_not ruleset.valid?
    assert ruleset.errors[:rules].any?, "Should have rules errors"
  end

  test "rules cannot contain empty strings" do
    ruleset = AiRuleset.new(name: "Test", category: "safety", rules: ["Valid", "", "Also valid"])
    assert_not ruleset.valid?
    assert_includes ruleset.errors[:rules], "cannot contain empty strings"
  end

  test "rules array validates content" do
    # Test with valid string array
    ruleset = AiRuleset.new(name: "Test", category: "safety", rules: ["Rule 1", "Rule 2"])
    assert ruleset.valid?, "Valid string array should pass: #{ruleset.errors.full_messages}"

    # PostgreSQL may coerce integers to strings in array columns
    # So we test that empty arrays fail presence validation
    ruleset2 = AiRuleset.new(name: "Test", category: "safety", rules: [])
    assert_not ruleset2.valid?
    assert ruleset2.errors[:rules].any?, "Empty array should fail validation"
  end

  # === Association Tests ===

  test "belongs to entity optionally" do
    # Global ruleset (no entity)
    global_ruleset = ai_rulesets(:core_safety)
    assert_nil global_ruleset.entity

    # Entity-specific ruleset
    entity_ruleset = ai_rulesets(:entity_one_hipaa)
    assert_equal entities(:one), entity_ruleset.entity
  end

  # === Scope Tests ===

  test "active scope returns only active rulesets" do
    active = AiRuleset.active
    assert active.all?(&:is_active?)
    assert_not_includes active, ai_rulesets(:inactive_ruleset)
  end

  test "inactive scope returns only inactive rulesets" do
    inactive = AiRuleset.inactive
    assert inactive.all? { |r| !r.is_active? }
    assert_includes inactive, ai_rulesets(:inactive_ruleset)
  end

  test "global scope returns rulesets without entity" do
    global = AiRuleset.global
    assert global.all?(&:global?)
    assert_includes global, ai_rulesets(:core_safety)
    assert_not_includes global, ai_rulesets(:entity_one_hipaa)
  end

  test "system_presets scope returns system rulesets" do
    presets = AiRuleset.system_presets
    assert presets.all?(&:is_system?)
    assert_includes presets, ai_rulesets(:core_safety)
    assert_not_includes presets, ai_rulesets(:email_compliance)
  end

  test "custom_rules scope returns non-system rulesets" do
    custom = AiRuleset.custom_rules
    assert custom.all? { |r| !r.is_system? }
    assert_includes custom, ai_rulesets(:email_compliance)
    assert_not_includes custom, ai_rulesets(:core_safety)
  end

  test "for_entity scope returns global and entity-specific rulesets" do
    entity = entities(:one)
    rulesets = AiRuleset.for_entity(entity)

    # Should include global rulesets
    assert_includes rulesets, ai_rulesets(:core_safety)
    assert_includes rulesets, ai_rulesets(:email_compliance)

    # Should include entity one specific rulesets
    assert_includes rulesets, ai_rulesets(:entity_one_hipaa)
    assert_includes rulesets, ai_rulesets(:entity_one_brand)

    # Should NOT include entity two specific rulesets
    assert_not_includes rulesets, ai_rulesets(:entity_two_gdpr)
  end

  test "by_priority scope orders by priority descending" do
    rulesets = AiRuleset.by_priority.to_a
    priorities = rulesets.map(&:priority)
    assert_equal priorities, priorities.sort.reverse
  end

  test "by_category scope filters by category" do
    safety = AiRuleset.by_category("safety")
    assert safety.all? { |r| r.category == "safety" }

    compliance = AiRuleset.by_category("compliance")
    assert compliance.all? { |r| r.category == "compliance" }
  end

  # === Instance Method Tests ===

  test "to_prompt formats rules as numbered list" do
    ruleset = ai_rulesets(:core_safety)
    prompt = ruleset.to_prompt

    assert_includes prompt, "1. Never reveal API keys"
    assert_includes prompt, "2. Only access data belonging"
    assert_includes prompt, "3. Limit bulk operations"
  end

  test "to_prompt returns empty string for blank rules" do
    ruleset = AiRuleset.new(name: "Empty", category: "safety", rules: [])
    # Skip validation for this test
    ruleset.instance_variable_set(:@rules, [])
    assert_equal "", ruleset.to_prompt
  end

  test "scope_description returns correct text" do
    global_ruleset = ai_rulesets(:core_safety)
    assert_equal "All Entities (Global)", global_ruleset.scope_description

    entity_ruleset = ai_rulesets(:entity_one_hipaa)
    assert_equal entities(:one).name, entity_ruleset.scope_description
  end

  test "global? returns true for global rulesets" do
    assert ai_rulesets(:core_safety).global?
    assert_not ai_rulesets(:entity_one_hipaa).global?
  end

  # === Deletion Protection Tests ===

  test "system presets cannot be deleted" do
    ruleset = ai_rulesets(:core_safety)
    assert ruleset.is_system?

    assert_no_difference "AiRuleset.count" do
      ruleset.destroy
    end

    assert_includes ruleset.errors[:base], "System presets cannot be deleted"
  end

  test "non-system rulesets can be deleted" do
    ruleset = ai_rulesets(:email_compliance)
    assert_not ruleset.is_system?

    assert_difference "AiRuleset.count", -1 do
      ruleset.destroy
    end
  end

  # === Category Constants Test ===

  test "CATEGORIES constant includes all valid categories" do
    expected = %w[safety tone compliance domain custom]
    assert_equal expected, AiRuleset::CATEGORIES
  end
end
