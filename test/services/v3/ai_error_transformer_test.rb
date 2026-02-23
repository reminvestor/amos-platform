# frozen_string_literal: true

require "test_helper"

class V3::AiErrorTransformerTest < ActiveSupport::TestCase
  # ══════════════════════════════════════════════════════════════
  # RECORD INVALID — validation errors with schema enrichment
  # ══════════════════════════════════════════════════════════════

  test "transforms RecordInvalid with schema info for known type" do
    record = EmailTemplate.new
    record.valid?
    error = ActiveRecord::RecordInvalid.new(record)

    result = V3::AiErrorTransformer.transform(error, type: "email_template", data: { name: "Welcome" })

    assert_equal false, result[:success]
    assert_equal "validation", result[:error_type]
    assert_equal "email_template", result[:object_type]
    assert_includes result[:required_fields], "name"
    assert_includes result[:required_fields], "subject"
    assert_includes result[:required_fields], "body"
    assert_includes result[:missing_fields], "subject"
    assert_includes result[:missing_fields], "body"
    assert result[:suggestion].present?
  end

  test "transforms RecordInvalid for unknown type without crashing" do
    record = EmailTemplate.new
    record.valid?
    error = ActiveRecord::RecordInvalid.new(record)

    result = V3::AiErrorTransformer.transform(error, type: "unknown_thing")

    assert_equal false, result[:success]
    assert_equal "validation", result[:error_type]
    assert result[:error].include?("Validation failed")
  end

  # ══════════════════════════════════════════════════════════════
  # RECORD NOT FOUND
  # ══════════════════════════════════════════════════════════════

  test "transforms RecordNotFound with suggestion" do
    error = ActiveRecord::RecordNotFound.new("Couldn't find Contact with 'id'=999")

    result = V3::AiErrorTransformer.transform(error, type: "contact")

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error_type]
    assert result[:suggestion].include?("platform_query")
  end

  # ══════════════════════════════════════════════════════════════
  # UNIQUE VIOLATIONS
  # ══════════════════════════════════════════════════════════════

  test "transforms RecordNotUnique with duplicate info" do
    error = ActiveRecord::RecordNotUnique.new("PG::UniqueViolation: Key (email)=(test@example.com) already exists")

    result = V3::AiErrorTransformer.transform(error, type: "contact")

    assert_equal false, result[:success]
    assert_equal "duplicate", result[:error_type]
    assert result[:suggestion].include?("platform_query")
  end

  # ══════════════════════════════════════════════════════════════
  # FOREIGN KEY VIOLATIONS
  # ══════════════════════════════════════════════════════════════

  test "transforms PG ForeignKeyViolation with table info" do
    error = PG::ForeignKeyViolation.new("update or delete on table \"contacts\" violates foreign key constraint on table \"contact_groups_contacts\"")

    result = V3::AiErrorTransformer.transform(error, type: "contact")

    assert_equal false, result[:success]
    assert_equal "foreign_key_violation", result[:error_type]
    assert result[:suggestion].include?("dependent records")
  end

  # ══════════════════════════════════════════════════════════════
  # UNDEFINED COLUMN
  # ══════════════════════════════════════════════════════════════

  test "transforms PG UndefinedColumn with valid fields for known type" do
    error = PG::UndefinedColumn.new("column contacts.nonexistent does not exist")

    result = V3::AiErrorTransformer.transform(error, type: "contact")

    assert_equal false, result[:success]
    assert_equal "invalid_field", result[:error_type]
    assert result[:valid_fields].present?, "Should include valid fields from ScoutDataRegistry"
    assert result[:suggestion].include?("not valid")
  end

  # ══════════════════════════════════════════════════════════════
  # TIMEOUT
  # ══════════════════════════════════════════════════════════════

  test "transforms Timeout::Error" do
    error = Timeout::Error.new("execution expired")

    result = V3::AiErrorTransformer.transform(error, tool: "platform_create")

    assert_equal false, result[:success]
    assert_equal "timeout", result[:error_type]
    assert result[:suggestion].include?("timed out") || result[:suggestion].include?("Try again")
  end

  # ══════════════════════════════════════════════════════════════
  # GENERIC ERRORS
  # ══════════════════════════════════════════════════════════════

  test "transforms generic errors cleanly without backtrace" do
    error = RuntimeError.new("something went wrong internally")

    result = V3::AiErrorTransformer.transform(error)

    assert_equal false, result[:success]
    assert_equal "internal_error", result[:error_type]
    assert_nil result[:backtrace], "Should never expose backtrace to AI"
    assert result[:suggestion].present?
  end

  test "truncates very long error messages" do
    error = RuntimeError.new("x" * 500)

    result = V3::AiErrorTransformer.transform(error)

    assert result[:error].length <= 303, "Should truncate long messages"
  end

  # ══════════════════════════════════════════════════════════════
  # SCHEMA ENRICHMENT HELPERS
  # ══════════════════════════════════════════════════════════════

  test "enrich_with_schema adds field info to error messages" do
    enriched = V3::AiErrorTransformer.enrich_with_schema("Name can't be blank", "email_template")

    assert enriched.include?("name")
    assert enriched.include?("subject")
    assert enriched.include?("body")
    assert enriched.include?("Required fields")
  end

  test "enrich_with_schema returns original message for unknown type" do
    original = "Something failed"
    result = V3::AiErrorTransformer.enrich_with_schema(original, "nonexistent_type")

    assert_equal original, result
  end

  test "schema_hint returns structured schema data" do
    hint = V3::AiErrorTransformer.schema_hint("contact")

    assert hint.present?
    assert_includes hint[:required_fields], "email"
    assert_includes hint[:required_fields], "first_name"
    assert hint[:optional_fields].include?("phone") || hint[:optional_fields].include?("company")
    assert hint[:notes].present?
  end

  test "schema_hint returns nil for unknown type" do
    assert_nil V3::AiErrorTransformer.schema_hint("nonexistent_type")
  end

  # ══════════════════════════════════════════════════════════════
  # ARGUMENT & JSON ERRORS
  # ══════════════════════════════════════════════════════════════

  test "transforms ArgumentError" do
    error = ArgumentError.new("wrong number of arguments (given 2, expected 1)")

    result = V3::AiErrorTransformer.transform(error)

    assert_equal false, result[:success]
    assert_equal "invalid_argument", result[:error_type]
    assert result[:suggestion].include?("parameter")
  end

  test "transforms JSON::ParserError" do
    error = JSON::ParserError.new("unexpected token")

    result = V3::AiErrorTransformer.transform(error)

    assert_equal false, result[:success]
    assert_equal "json_parse_error", result[:error_type]
  end

  # ══════════════════════════════════════════════════════════════
  # CONTEXT PROPAGATION
  # ══════════════════════════════════════════════════════════════

  test "passes through context fields" do
    error = RuntimeError.new("test")

    result = V3::AiErrorTransformer.transform(error, type: "campaign", tool: "platform_create")

    assert_equal false, result[:success]
    # Schema info should be included for known types
    assert result[:required_fields]&.include?("name") || result[:suggestion]&.include?("name"),
           "Should include schema info for known types"
  end
end
