require "test_helper"

class Admin::AiRulesetsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = users(:admin)  # User with admin role
    @non_admin = users(:marketer_user)  # User without admin role

    @core_safety = ai_rulesets(:core_safety)
    @email_compliance = ai_rulesets(:email_compliance)
    @entity_one_hipaa = ai_rulesets(:entity_one_hipaa)

    # Sign in as admin user - Admin::BaseController will handle admin session
    sign_in @admin
  end

  # === Access Control Tests ===

  test "should require admin access" do
    sign_out @admin
    sign_in @non_admin

    get admin_ai_rulesets_path
    assert_redirected_to chat_mode_path
  end

  test "should redirect non-authenticated users" do
    sign_out @admin
    get admin_ai_rulesets_path
    assert_redirected_to new_user_session_path
  end

  # === Index Action Tests ===

  test "index is accessible to admin" do
    get admin_ai_rulesets_path
    assert_response :success
  end

  test "index displays all rulesets" do
    get admin_ai_rulesets_path
    assert_response :success
    assert_select "table"
  end

  test "index filters by category" do
    get admin_ai_rulesets_path(category: "safety")
    assert_response :success
  end

  test "index filters by status active" do
    get admin_ai_rulesets_path(status: "active")
    assert_response :success
  end

  test "index filters by status inactive" do
    get admin_ai_rulesets_path(status: "inactive")
    assert_response :success
  end

  test "index filters by scope global" do
    get admin_ai_rulesets_path(scope: "global")
    assert_response :success
  end

  test "index filters by scope entity" do
    get admin_ai_rulesets_path(scope: "entity")
    assert_response :success
  end

  test "index filters by scope system" do
    get admin_ai_rulesets_path(scope: "system")
    assert_response :success
  end

  # === Show Action Tests ===

  test "show displays ruleset details" do
    get admin_ai_ruleset_path(@core_safety)
    assert_response :success
  end

  test "show generates preview prompt" do
    get admin_ai_ruleset_path(@core_safety)
    assert_response :success
  end

  # === New Action Tests ===

  test "new displays form" do
    get new_admin_ai_ruleset_path
    assert_response :success
    assert_select "form"
  end

  # === Create Action Tests ===

  test "create with valid params" do
    assert_difference "AiRuleset.count", 1 do
      post admin_ai_rulesets_path, params: {
        ai_ruleset: {
          name: "New Test Ruleset",
          description: "Test description",
          category: "custom",
          rules: "Rule 1\nRule 2\nRule 3",
          is_active: true,
          priority: 50
        }
      }
    end

    assert_redirected_to admin_ai_ruleset_path(AiRuleset.last)
    assert_match /successfully created/, flash[:notice]

    ruleset = AiRuleset.last
    assert_equal "New Test Ruleset", ruleset.name
    assert_equal ["Rule 1", "Rule 2", "Rule 3"], ruleset.rules
    assert_equal "custom", ruleset.category
    assert ruleset.is_active?
    assert_equal 50, ruleset.priority
  end

  test "create with entity assignment" do
    entity = entities(:one)
    assert_difference "AiRuleset.count", 1 do
      post admin_ai_rulesets_path, params: {
        ai_ruleset: {
          name: "Entity Specific",
          category: "custom",
          rules: "Rule 1",
          entity_id: entity.id
        }
      }
    end

    ruleset = AiRuleset.last
    assert_equal entity, ruleset.entity
    assert_not ruleset.global?
  end

  test "create with invalid params renders new" do
    assert_no_difference "AiRuleset.count" do
      post admin_ai_rulesets_path, params: {
        ai_ruleset: {
          name: "",  # Invalid - blank name
          category: "custom",
          rules: "Rule 1"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create parses rules from newline-separated string" do
    post admin_ai_rulesets_path, params: {
      ai_ruleset: {
        name: "Multiline Rules",
        category: "safety",
        rules: "First rule\nSecond rule\n\nThird rule with blank above"
      }
    }

    ruleset = AiRuleset.last
    assert_equal 3, ruleset.rules.count
    assert_equal "First rule", ruleset.rules[0]
    assert_equal "Second rule", ruleset.rules[1]
    assert_equal "Third rule with blank above", ruleset.rules[2]
  end

  # === Edit Action Tests ===

  test "edit displays form with existing values" do
    get edit_admin_ai_ruleset_path(@email_compliance)
    assert_response :success
    assert_select "form"
  end

  # === Update Action Tests ===

  test "update with valid params" do
    patch admin_ai_ruleset_path(@email_compliance), params: {
      ai_ruleset: {
        name: "Updated Email Compliance",
        rules: "Updated Rule 1\nUpdated Rule 2"
      }
    }

    assert_redirected_to admin_ai_ruleset_path(@email_compliance)
    assert_match /successfully updated/, flash[:notice]

    @email_compliance.reload
    assert_equal "Updated Email Compliance", @email_compliance.name
    assert_equal ["Updated Rule 1", "Updated Rule 2"], @email_compliance.rules
  end

  test "update with invalid params renders edit" do
    patch admin_ai_ruleset_path(@email_compliance), params: {
      ai_ruleset: {
        name: "",  # Invalid
        category: "invalid_category"
      }
    }

    assert_response :unprocessable_entity
  end

  # === Destroy Action Tests ===

  test "destroy non-system ruleset" do
    assert_difference "AiRuleset.count", -1 do
      delete admin_ai_ruleset_path(@email_compliance)
    end

    assert_redirected_to admin_ai_rulesets_path
    assert_match /successfully deleted/, flash[:notice]
  end

  test "destroy system preset is prevented" do
    assert @core_safety.is_system?

    assert_no_difference "AiRuleset.count" do
      delete admin_ai_ruleset_path(@core_safety)
    end

    assert_redirected_to admin_ai_rulesets_path
    assert_match /cannot be deleted/, flash[:alert]
  end

  # === Toggle Action Tests ===

  test "toggle enables disabled ruleset" do
    inactive = ai_rulesets(:inactive_ruleset)
    assert_not inactive.is_active?

    patch toggle_admin_ai_ruleset_path(inactive)

    inactive.reload
    assert inactive.is_active?
    assert_redirected_to admin_ai_rulesets_path
    assert_match /enabled/, flash[:notice]
  end

  test "toggle disables enabled ruleset" do
    assert @email_compliance.is_active?

    patch toggle_admin_ai_ruleset_path(@email_compliance)

    @email_compliance.reload
    assert_not @email_compliance.is_active?
    assert_redirected_to admin_ai_rulesets_path
    assert_match /disabled/, flash[:notice]
  end

  # === Clone Action Tests ===

  test "clone creates copy of ruleset" do
    assert_difference "AiRuleset.count", 1 do
      post clone_admin_ai_ruleset_path(@email_compliance)
    end

    assert_redirected_to admin_ai_ruleset_path(AiRuleset.last)
    assert_match /cloned successfully/, flash[:notice]

    cloned = AiRuleset.last
    assert_equal "#{@email_compliance.name} (Copy)", cloned.name
    assert_equal @email_compliance.rules, cloned.rules
    assert_equal @email_compliance.category, cloned.category
    assert_not cloned.is_system?  # Clones are never system presets
  end

  test "clone to specific entity" do
    target_entity = entities(:two)

    assert_difference "AiRuleset.count", 1 do
      post clone_admin_ai_ruleset_path(@email_compliance), params: {
        target_entity_id: target_entity.id
      }
    end

    cloned = AiRuleset.last
    assert_equal target_entity, cloned.entity
    assert_not cloned.global?
  end

  test "clone system preset removes system flag" do
    assert @core_safety.is_system?

    assert_difference "AiRuleset.count", 1 do
      post clone_admin_ai_ruleset_path(@core_safety)
    end

    cloned = AiRuleset.last
    assert_not cloned.is_system?
    assert_equal @core_safety.category, cloned.category
    assert_equal @core_safety.rules, cloned.rules
  end

  # === Edge Cases ===

  test "handles ruleset not found" do
    get admin_ai_ruleset_path(99999)
    assert_response :not_found
  rescue ActiveRecord::RecordNotFound
    # Expected behavior
  end
end
