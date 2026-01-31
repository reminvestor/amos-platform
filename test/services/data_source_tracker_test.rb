# frozen_string_literal: true

require "test_helper"

class DataSourceTrackerTest < ActiveSupport::TestCase
  test "tags data with trusted source" do
    tagged = DataSourceTracker.tag("user input", source: :user_prompt)
    
    assert tagged[:_tagged]
    assert_equal "user input", tagged[:value]
    assert_equal :user_prompt, tagged[:source]
    assert_equal :trusted, tagged[:trust_level]
  end

  test "tags data with untrusted source" do
    tagged = DataSourceTracker.tag({ email: "test@example.com" }, source: :email)
    
    assert tagged[:_tagged]
    assert_equal :email, tagged[:source]
    assert_equal :untrusted, tagged[:trust_level]
  end

  test "trusted? returns true for trusted data" do
    tagged = DataSourceTracker.tag("data", source: :user_prompt)
    assert DataSourceTracker.trusted?(tagged)
  end

  test "trusted? returns false for untrusted data" do
    tagged = DataSourceTracker.tag("data", source: :email)
    assert_not DataSourceTracker.trusted?(tagged)
  end

  test "untrusted? returns true for untrusted data" do
    tagged = DataSourceTracker.tag("data", source: :tool_result)
    assert DataSourceTracker.untrusted?(tagged)
  end

  test "derived? returns true for derived data" do
    tagged = DataSourceTracker.tag("data", source: :extracted)
    assert DataSourceTracker.derived?(tagged)
  end

  test "tagged? returns false for untagged data" do
    assert_not DataSourceTracker.tagged?("plain string")
    assert_not DataSourceTracker.tagged?({ foo: "bar" })
  end

  test "unwrap extracts value from tagged data" do
    tagged = DataSourceTracker.tag({ key: "value" }, source: :user_prompt)
    assert_equal({ key: "value" }, DataSourceTracker.unwrap(tagged))
  end

  test "unwrap returns untagged data as-is" do
    assert_equal "plain", DataSourceTracker.unwrap("plain")
  end

  test "tag_tool_result tags known untrusted tools correctly" do
    result = { data: [1, 2, 3] }
    tagged = DataSourceTracker.tag_tool_result("get_data", result)
    
    assert_equal :untrusted, tagged[:trust_level]
    assert_equal :tool_result, tagged[:source]
  end

  test "tag_tool_result tags unknown tools as system" do
    result = { canvas: "test" }
    tagged = DataSourceTracker.tag_tool_result("create_freeform_canvas", result)
    
    assert_equal :trusted, tagged[:trust_level]
    assert_equal :system, tagged[:source]
  end

  test "sensitive_tool? identifies sensitive tools" do
    assert DataSourceTracker.sensitive_tool?("send_email")
    assert DataSourceTracker.sensitive_tool?("create_object")
    assert_not DataSourceTracker.sensitive_tool?("get_data")
  end

  test "collect_sources finds all tagged data in nested structure" do
    data = {
      user_input: DataSourceTracker.tag("hello", source: :user_prompt),
      email_content: DataSourceTracker.tag("email body", source: :email),
      nested: {
        doc: DataSourceTracker.tag("document", source: :document)
      }
    }
    
    sources = DataSourceTracker.collect_sources(data)
    
    assert_equal 3, sources.length
    assert sources.any? { |s| s[:source] == :user_prompt }
    assert sources.any? { |s| s[:source] == :email }
    assert sources.any? { |s| s[:source] == :document }
  end

  test "has_untrusted? returns true when untrusted data exists" do
    data = {
      user_input: DataSourceTracker.tag("hello", source: :user_prompt),
      email: DataSourceTracker.tag("suspicious", source: :email)
    }
    
    assert DataSourceTracker.has_untrusted?(data)
  end

  test "has_untrusted? returns false for only trusted data" do
    data = {
      input1: DataSourceTracker.tag("hello", source: :user_prompt),
      input2: DataSourceTracker.tag("world", source: :system)
    }
    
    assert_not DataSourceTracker.has_untrusted?(data)
  end

  test "promote_to_trusted upgrades trust level" do
    tagged = DataSourceTracker.tag("data", source: :extracted)
    assert_equal :derived, tagged[:trust_level]
    
    promoted = DataSourceTracker.promote_to_trusted(tagged)
    assert_equal :trusted, promoted[:trust_level]
    assert_equal :derived, promoted[:original_trust_level]
    assert promoted[:promoted_at].present?
  end

  test "derived trust level when parent sources are untrusted" do
    parent_sources = [{ source: :email, trust_level: :untrusted }]
    tagged = DataSourceTracker.tag("extracted", source: :extracted, parent_sources: parent_sources)
    
    assert_equal :derived, tagged[:trust_level]
  end
end
