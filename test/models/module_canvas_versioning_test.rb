# frozen_string_literal: true

require "test_helper"

class ModuleCanvasVersioningTest < ActiveSupport::TestCase
  def setup
    @entity = entities(:one)
    @user = users(:one)
    @app_module = AppModule.create!(
      entity: @entity,
      created_by: @user,
      name: "Version Test Module",
      slug: "version_test_module_#{SecureRandom.hex(4)}",
      status: "active"
    )
    @canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Versioned Form",
      slug: "versioned_form",
      canvas_type: "form",
      html_content: "<form>V1 HTML</form>",
      js_content: "function v1() {}",
      css_content: ".v1 { color: red; }"
    )
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Version Tracking on Content Changes
  # ─────────────────────────────────────────────────────────────────────────────

  test "saves previous version when html_content changes" do
    @canvas.update!(html_content: "<form>V2 HTML</form>")

    versions = @canvas.parsed_previous_versions
    assert_equal 1, versions.length
    assert_equal "<form>V1 HTML</form>", versions[0]["html_content"]
    assert_equal "function v1() {}", versions[0]["js_content"]
    assert_equal ".v1 { color: red; }", versions[0]["css_content"]
  end

  test "saves previous version when js_content changes" do
    @canvas.update!(js_content: "function v2() {}")

    versions = @canvas.parsed_previous_versions
    assert_equal 1, versions.length
    assert_equal "function v1() {}", versions[0]["js_content"]
  end

  test "saves previous version when css_content changes" do
    @canvas.update!(css_content: ".v2 { color: blue; }")

    versions = @canvas.parsed_previous_versions
    assert_equal 1, versions.length
    assert_equal ".v1 { color: red; }", versions[0]["css_content"]
  end

  test "does NOT save version for non-content changes" do
    @canvas.update!(name: "Renamed Form")

    versions = @canvas.parsed_previous_versions
    assert_equal 0, versions.length
  end

  test "accumulates multiple versions" do
    @canvas.update!(html_content: "<form>V2 HTML</form>")
    @canvas.update!(js_content: "function v3() {}")
    @canvas.update!(css_content: ".v4 { color: green; }")

    versions = @canvas.parsed_previous_versions
    assert_equal 3, versions.length
  end

  test "limits to 20 versions" do
    25.times do |i|
      @canvas.update!(html_content: "<form>Version #{i + 2}</form>")
    end

    versions = @canvas.parsed_previous_versions
    assert_equal 20, versions.length
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Version Restoration
  # ─────────────────────────────────────────────────────────────────────────────

  test "restore_version! restores content from a saved version" do
    original_html = @canvas.html_content
    original_js = @canvas.js_content
    original_css = @canvas.css_content

    @canvas.update!(
      html_content: "<form>V2</form>",
      js_content: "function v2() {}",
      css_content: ".v2 {}"
    )

    result = @canvas.restore_version!(1)
    assert result

    @canvas.reload
    assert_equal original_html, @canvas.html_content
    assert_equal original_js, @canvas.js_content
    assert_equal original_css, @canvas.css_content
  end

  test "restore_version! returns false for nonexistent version" do
    result = @canvas.restore_version!(999)
    assert_equal false, result
  end

  test "restore_version! works on locked canvas" do
    @canvas.update!(html_content: "<form>V2</form>")
    @canvas.lock!(user: @user, reason: "Protected")

    result = @canvas.restore_version!(1)
    assert result

    @canvas.reload
    assert_equal "<form>V1 HTML</form>", @canvas.html_content
    assert @canvas.locked?, "Canvas should remain locked after restore"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Version Summary
  # ─────────────────────────────────────────────────────────────────────────────

  test "version_summary returns size info for each version" do
    @canvas.update!(html_content: "<form>V2 HTML</form>")

    summary = @canvas.version_summary
    assert_equal 1, summary.length
    assert summary[0][:version].present?
    assert summary[0][:saved_at].present?
    assert summary[0][:html_size] > 0
  end

  test "version_summary returns empty for canvas with no previous versions" do
    summary = @canvas.version_summary
    assert_equal [], summary
  end
end
