# frozen_string_literal: true

require "test_helper"

class V3::Tools::PlatformUpdateToolTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)
    @tool = V3::Tools::PlatformUpdateTool.new(user: @user, entity: @entity)
  end

  # ══════════════════════════════════════════════════════════════
  # METADATA
  # ══════════════════════════════════════════════════════════════

  test "metadata has correct name" do
    metadata = V3::Tools::PlatformUpdateTool.metadata
    assert_equal "platform_update", metadata[:name]
    assert_equal "v3_core", metadata[:category]
  end

  test "description mentions schema and custom fields" do
    desc = V3::Tools::PlatformUpdateTool.metadata[:description]
    assert desc.include?("schema"), "Should mention schema for custom fields"
    assert desc.include?("add_field"), "Should mention add_field"
  end

  # ══════════════════════════════════════════════════════════════
  # VALIDATION
  # ══════════════════════════════════════════════════════════════

  test "returns error for missing type" do
    result = @tool.execute({ "id" => 1, "data" => { "name" => "test" } })
    assert_equal false, result[:success]
  end

  test "returns error for missing id" do
    result = @tool.execute({ "type" => "contact", "data" => { "name" => "test" } })
    assert_equal false, result[:success]
  end

  test "returns error for missing data" do
    result = @tool.execute({ "type" => "contact", "id" => 1 })
    assert_equal false, result[:success]
  end

  # ══════════════════════════════════════════════════════════════
  # CUSTOM FIELDS (schema type)
  # ══════════════════════════════════════════════════════════════

  test "add custom field to Contact" do
    result = @tool.execute({
      "type" => "schema",
      "id" => "contact",
      "data" => { "add_field" => { "name" => "test_industry", "field_type" => "string" } }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert result[:field_id].present?

    field = CustomFieldDefinition.find_by(id: result[:field_id])
    assert field, "CustomFieldDefinition should exist"
    assert_equal "Contact", field.model_type
    assert_equal "test_industry", field.field_name
    assert_equal "string", field.field_type
  ensure
    CustomFieldDefinition.where(entity: @entity, field_name: "test_industry").destroy_all
  end

  test "remove custom field" do
    field = CustomFieldDefinition.create!(
      entity: @entity, model_type: "Contact", field_name: "to_remove",
      field_type: "string", active: true
    )

    result = @tool.execute({
      "type" => "schema",
      "id" => "contact",
      "data" => { "remove_field" => "to_remove" }
    })

    assert result[:success] != false
    field.reload
    assert_not field.active?, "Field should be deactivated"
  ensure
    CustomFieldDefinition.where(entity: @entity, field_name: "to_remove").destroy_all
  end

  test "list custom fields" do
    CustomFieldDefinition.create!(
      entity: @entity, model_type: "Contact", field_name: "list_test",
      field_type: "string", active: true
    )

    result = @tool.execute({
      "type" => "schema",
      "id" => "contact",
      "data" => { "list_fields" => true }
    })

    assert result[:success] != false
    assert result[:fields].is_a?(Array)
    assert result[:fields].any? { |f| f[:name] == "list_test" }
  ensure
    CustomFieldDefinition.where(entity: @entity, field_name: "list_test").destroy_all
  end

  test "rejects custom field on unsupported model" do
    result = @tool.execute({
      "type" => "schema",
      "id" => "user",
      "data" => { "add_field" => { "name" => "bad", "field_type" => "string" } }
    })

    assert_equal false, result[:success]
    assert_match(/Cannot add custom fields/i, result[:error])
  end

  test "handles duplicate custom field idempotently" do
    CustomFieldDefinition.create!(
      entity: @entity, model_type: "Contact", field_name: "dupe_field",
      field_type: "string", active: true
    )

    # Same type → idempotent success
    result = @tool.execute({
      "type" => "schema",
      "id" => "contact",
      "data" => { "add_field" => { "name" => "dupe_field", "field_type" => "string" } }
    })

    assert result[:success] != false, "Same-type duplicate should be idempotent success"
    assert result[:already_exists], "Should flag already_exists"

    # Different type → error
    result2 = @tool.execute({
      "type" => "schema",
      "id" => "contact",
      "data" => { "add_field" => { "name" => "dupe_field", "field_type" => "integer" } }
    })

    assert_equal false, result2[:success]
    assert_match(/already exists/i, result2[:error])
  ensure
    CustomFieldDefinition.where(entity: @entity, field_name: "dupe_field").destroy_all
  end
end
