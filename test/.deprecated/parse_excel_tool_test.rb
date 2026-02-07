# frozen_string_literal: true

require "test_helper"

class ParseExcelToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::ParseExcelTool.new(entity: @entity, user: @user)
  end

  test "metadata returns correct structure" do
    metadata = Tools::ParseExcelTool.metadata

    assert_equal "parse_excel", metadata[:name]
    assert_equal "data", metadata[:category]
    assert metadata[:description].include?("Excel")
    assert_includes metadata[:input_schema][:required], "source"
    assert_includes metadata[:input_schema][:required], "file_identifier"
  end

  test "is read only" do
    assert Tools::ParseExcelTool.read_only?
  end

  test "returns error when source is invalid" do
    result = @tool.execute({ source: "invalid", file_identifier: "test.xlsx" })

    assert_not result[:success]
    assert_includes result[:error], "Invalid source"
  end

  test "returns error when file not found" do
    result = @tool.execute({ source: "upload", file_identifier: "nonexistent.xlsx" })

    assert_not result[:success]
    assert_includes result[:error], "Could not find"
  end

  test "returns error when required args missing" do
    result = @tool.execute({})

    assert_not result[:success]
    assert result[:error].present?
  end

  test "handles preview_only parameter" do
    # This tests the parameter handling logic
    args = { source: "upload", file_identifier: "test.xlsx", preview_only: true }
    
    # The actual execution will fail without a real file, but we can test arg parsing
    result = @tool.execute(args)
    
    # Should fail at file fetch, not at arg parsing
    assert_not result[:success]
    assert_includes result[:error], "Could not find"
  end

  test "formats cell values correctly" do
    tool = Tools::ParseExcelTool.new(entity: @entity, user: @user)

    # Test the private method via send
    assert_equal 100, tool.send(:format_cell_value, 100.0)
    assert_equal 100.5, tool.send(:format_cell_value, 100.5)
    assert_nil tool.send(:format_cell_value, nil)
    assert_equal "text", tool.send(:format_cell_value, "text")
  end

  test "normalizes headers correctly" do
    tool = Tools::ParseExcelTool.new(entity: @entity, user: @user)

    assert_equal "column_1", tool.send(:normalize_header, nil, 1)
    assert_equal "column_2", tool.send(:normalize_header, "", 2)
    assert_equal "job_cost", tool.send(:normalize_header, "Job Cost", 1)
    assert_equal "total_amount", tool.send(:normalize_header, "Total Amount!", 1)
  end

  test "calculates numeric summary correctly" do
    tool = Tools::ParseExcelTool.new(entity: @entity, user: @user)

    headers = ["amount"]
    records = [
      { "amount" => 100 },
      { "amount" => 200 },
      { "amount" => 300 }
    ]
    field_analysis = { "amount" => { type: :integer } }

    summary = tool.send(:calculate_numeric_summary, headers, records, field_analysis)

    assert_equal 600, summary["amount"][:sum]
    assert_equal 200, summary["amount"][:average]
    assert_equal 100, summary["amount"][:min]
    assert_equal 300, summary["amount"][:max]
    assert_equal 3, summary["amount"][:count]
  end

  test "analyzes field types correctly" do
    tool = Tools::ParseExcelTool.new(entity: @entity, user: @user)

    headers = ["name", "amount", "active"]
    records = [
      { "name" => "Test", "amount" => 100, "active" => true },
      { "name" => "Test2", "amount" => 200, "active" => false }
    ]

    analysis = tool.send(:analyze_fields, headers, records)

    assert_equal :string, analysis["name"][:type]
    assert_equal :integer, analysis["amount"][:type]
    assert_equal :boolean, analysis["active"][:type]
  end
end
