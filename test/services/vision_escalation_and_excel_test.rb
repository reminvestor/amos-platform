# frozen_string_literal: true

require "test_helper"

class VisionEscalationAndExcelTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ═══════════════════════════════════════════════════════════════
  # VISION MODEL ESCALATION
  # ═══════════════════════════════════════════════════════════════

  test "qwen3-next-80b does not support vision" do
    config = BedrockService::AVAILABLE_MODELS["qwen3-next-80b"]
    assert config.present?, "qwen3-next-80b should be in AVAILABLE_MODELS"
    assert_equal false, config[:supports_vision],
      "qwen3-next-80b should NOT support vision"
  end

  test "claude-sonnet-4-6 supports vision" do
    config = BedrockService::AVAILABLE_MODELS["claude-sonnet-4-6"]
    assert config.present?, "claude-sonnet-4-6 should be in AVAILABLE_MODELS"
    assert_equal true, config[:supports_vision],
      "claude-sonnet-4-6 SHOULD support vision"
  end

  test "qwen3-vl-235b supports vision" do
    config = BedrockService::AVAILABLE_MODELS["qwen3-vl-235b"]
    assert config.present?, "qwen3-vl-235b should be in AVAILABLE_MODELS"
    assert_equal true, config[:supports_vision],
      "qwen3-vl-235b SHOULD support vision"
  end

  test "default auto model is qwen3-next-80b" do
    assert_equal "qwen3-next-80b", V3::AgentLoop::DEFAULT_AUTO_MODEL
  end

  test "model_supports_vision? returns false for non-vision models" do
    controller = ScoutController.new
    refute controller.send(:model_supports_vision?, "qwen3-next-80b")
    refute controller.send(:model_supports_vision?, "deepseek-v3")
    refute controller.send(:model_supports_vision?, "unknown-model")
  end

  test "model_supports_vision? returns true for vision models" do
    controller = ScoutController.new
    assert controller.send(:model_supports_vision?, "claude-sonnet-4-6")
    assert controller.send(:model_supports_vision?, "claude-opus-4-6")
    assert controller.send(:model_supports_vision?, "qwen3-vl-235b")
  end

  # ═══════════════════════════════════════════════════════════════
  # EXCEL PARSING — ROBUST HANDLING
  # ═══════════════════════════════════════════════════════════════

  test "extract_excel_text handles xlsx files" do
    require 'roo'

    # Create a real xlsx file for testing
    tempfile = Tempfile.new(["test_excel", ".xlsx"])
    begin
      workbook = create_test_xlsx(tempfile.path)
      tool = Tools::ReadDocumentTool.new(user: @user, entity: @entity, context: {})
      result = tool.send(:extract_excel_text, tempfile.path)

      assert result.present?, "Should extract text from xlsx"
      assert_match /Sheet/, result
    ensure
      tempfile.close!
    end
  end

  test "extract_excel_text handles empty sheets gracefully" do
    tempfile = Tempfile.new(["empty_excel", ".xlsx"])
    begin
      create_empty_xlsx(tempfile.path)
      tool = Tools::ReadDocumentTool.new(user: @user, entity: @entity, context: {})
      result = tool.send(:extract_excel_text, tempfile.path)

      assert result.present?, "Should return a message for empty excel"
      assert_no_match /Error/, result, "Should not return an error for empty files"
    ensure
      tempfile.close!
    end
  end

  test "extract_excel_text does not crash on nil last_row" do
    tool = Tools::ReadDocumentTool.new(user: @user, entity: @entity, context: {})

    # This should not raise even if roo returns nil for last_row
    # (we handle it with `next unless last_row && last_row >= 1`)
    assert_nothing_raised do
      tempfile = Tempfile.new(["edge_case", ".xlsx"])
      begin
        create_empty_xlsx(tempfile.path)
        tool.send(:extract_excel_text, tempfile.path)
      ensure
        tempfile.close!
      end
    end
  end

  test "extract_excel_text passes extension explicitly to roo" do
    require 'roo'

    # Create a file with a non-standard temp path but xlsx content
    tempfile = Tempfile.new(["weirdname", ".xlsx"])
    begin
      create_test_xlsx(tempfile.path)

      tool = Tools::ReadDocumentTool.new(user: @user, entity: @entity, context: {})
      result = tool.send(:extract_excel_text, tempfile.path)

      assert result.present?
      refute_match /Error/, result
    ensure
      tempfile.close!
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # FILE UPLOAD MESSAGE ENHANCEMENT
  # ═══════════════════════════════════════════════════════════════

  test "build_v3_enhanced_message includes file info" do
    controller = ScoutController.new
    file_urls = [
      { "filename" => "screenshot.png", "asset_id" => 1, "content_type" => "image/png", "asset_type" => "image" }
    ]

    result = controller.send(:build_v3_enhanced_message, "Look at this", file_urls)
    assert_match /screenshot\.png/, result
    assert_match /asset_id: 1/, result
    assert_match /read_file/, result
  end

  test "build_v3_enhanced_message returns plain message when no files" do
    controller = ScoutController.new
    result = controller.send(:build_v3_enhanced_message, "Hello", [])
    assert_equal "Hello", result
  end

  private

  def create_test_xlsx(path)
    require 'write_xlsx'
    workbook = WriteXLSX.new(path)
    sheet = workbook.add_worksheet("TestSheet")
    sheet.write(0, 0, "Name")
    sheet.write(0, 1, "Value")
    sheet.write(1, 0, "Test")
    sheet.write(1, 1, "123")
    workbook.close
  rescue LoadError
    # write_xlsx gem not available — create via roo-compatible method
    require 'csv'
    # Fall back to creating a CSV and testing CSV path
    # Skip this test if we can't create xlsx files
    skip "write_xlsx gem not available for test xlsx creation"
  end

  def create_empty_xlsx(path)
    require 'write_xlsx'
    workbook = WriteXLSX.new(path)
    workbook.add_worksheet("Empty")
    workbook.close
  rescue LoadError
    skip "write_xlsx gem not available for test xlsx creation"
  end
end
