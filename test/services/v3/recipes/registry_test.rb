# frozen_string_literal: true

require "test_helper"

class V3::Recipes::RegistryTest < ActiveSupport::TestCase
  setup do
    # Reset the registry cache for each test
    V3::Recipes::Registry.reset!
  end

  # ══════════════════════════════════════════════════════════════
  # RECIPE DISCOVERY
  # ══════════════════════════════════════════════════════════════

  test "discovers recipe classes automatically" do
    recipes = V3::Recipes::Registry.all
    assert recipes.length > 0, "Should discover at least one recipe"
  end

  test "all discovered recipes are subclasses of Base" do
    V3::Recipes::Registry.all.each do |recipe_class|
      assert recipe_class < V3::Recipes::Base, "#{recipe_class} should be a subclass of Base"
    end
  end

  # ══════════════════════════════════════════════════════════════
  # RECIPE MATCHING
  # ══════════════════════════════════════════════════════════════

  test "finds contact management recipe for contact goals" do
    recipe = V3::Recipes::Registry.find("create a contact")
    assert_not_nil recipe, "Should find a recipe for 'create a contact'"
    assert_equal "contact_management", recipe.recipe_name
  end

  test "finds email automation recipe for email automation goals" do
    recipe = V3::Recipes::Registry.find("welcome email automation")
    assert_not_nil recipe, "Should find a recipe for 'welcome email automation'"
    assert_equal "email_automation", recipe.recipe_name
  end

  test "finds landing page recipe for landing page goals" do
    recipe = V3::Recipes::Registry.find("build a landing page")
    assert_not_nil recipe, "Should find a recipe for 'build a landing page'"
    assert_equal "landing_page", recipe.recipe_name
  end

  test "finds campaign recipe for campaign goals" do
    recipe = V3::Recipes::Registry.find("create a campaign")
    assert_not_nil recipe, "Should find a recipe for 'create a campaign'"
    assert_equal "campaign", recipe.recipe_name
  end

  test "finds integration recipe for stripe goals" do
    recipe = V3::Recipes::Registry.find("stripe list_charges")
    assert_not_nil recipe, "Should find a recipe for 'stripe list_charges'"
    assert_equal "integration", recipe.recipe_name
  end

  test "finds delete recipe for delete goals" do
    recipe = V3::Recipes::Registry.find("delete a contact")
    assert_not_nil recipe, "Should find a recipe for 'delete a contact'"
    assert_equal "delete", recipe.recipe_name
  end

  test "finds update recipe for update goals" do
    recipe = V3::Recipes::Registry.find("update the contact")
    assert_not_nil recipe, "Should find a recipe for 'update the contact'"
    assert_equal "update", recipe.recipe_name
  end

  test "finds app build recipe for app goals" do
    recipe = V3::Recipes::Registry.find("build an app")
    assert_not_nil recipe, "Should find a recipe for 'build an app'"
    assert_equal "app_build", recipe.recipe_name
  end

  test "finds scheduled task recipe for scheduling goals" do
    recipe = V3::Recipes::Registry.find("create a scheduled task")
    assert_not_nil recipe, "Should find a recipe for 'create a scheduled task'"
    assert_equal "scheduled_task", recipe.recipe_name
  end

  test "returns nil for unmatched goals" do
    recipe = V3::Recipes::Registry.find("explain quantum physics")
    assert_nil recipe, "Should return nil for non-platform goals"
  end

  # ══════════════════════════════════════════════════════════════
  # PRIORITY ORDERING
  # ══════════════════════════════════════════════════════════════

  test "recipes are sorted by priority descending" do
    recipes = V3::Recipes::Registry.all
    priorities = recipes.map(&:priority)
    assert_equal priorities, priorities.sort.reverse, "Recipes should be sorted by priority (highest first)"
  end

  # ══════════════════════════════════════════════════════════════
  # STATS
  # ══════════════════════════════════════════════════════════════

  test "stats returns recipe count and list" do
    stats = V3::Recipes::Registry.stats
    assert stats[:total_recipes] > 0
    assert stats[:recipes].is_a?(Array)
    assert stats[:recipes].first[:name].present?
  end
end
