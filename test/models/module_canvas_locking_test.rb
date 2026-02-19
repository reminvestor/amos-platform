# frozen_string_literal: true

require "test_helper"

class ModuleCanvasLockingTest < ActiveSupport::TestCase
  def setup
    @entity = entities(:one)
    @user = users(:one)
    @app_module = AppModule.create!(
      entity: @entity,
      created_by: @user,
      name: "Lock Test Module",
      slug: "lock_test_module_#{SecureRandom.hex(4)}",
      status: "active"
    )
    @canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Test Form",
      slug: "test_form",
      canvas_type: "form",
      html_content: "<form>Original HTML</form>",
      js_content: "function init() { return 'original'; }",
      css_content: ".form { color: red; }"
    )
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Lock / Unlock Basics
  # ─────────────────────────────────────────────────────────────────────────────

  test "canvas is unlocked by default" do
    assert_not @canvas.locked?
    assert_equal false, @canvas.is_locked
  end

  test "lock! sets lock fields" do
    @canvas.lock!(user: @user, reason: "User customized this form")

    @canvas.reload
    assert @canvas.locked?
    assert @canvas.locked_at.present?
    assert_equal @user.id, @canvas.locked_by_id
    assert_equal "User customized this form", @canvas.lock_reason
  end

  test "lock! with no user sets system lock" do
    @canvas.lock!

    @canvas.reload
    assert @canvas.locked?
    assert_nil @canvas.locked_by_id
    assert_equal "Locked by system", @canvas.lock_reason
  end

  test "unlock! clears lock fields" do
    @canvas.lock!(user: @user, reason: "Test lock")
    @canvas.unlock!

    @canvas.reload
    assert_not @canvas.locked?
    assert_nil @canvas.locked_at
    assert_nil @canvas.locked_by_id
    assert_nil @canvas.lock_reason
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Lock Enforcement — Content Changes
  # ─────────────────────────────────────────────────────────────────────────────

  test "locked canvas rejects html_content changes" do
    @canvas.lock!(user: @user, reason: "Protected")

    @canvas.html_content = "<form>Changed HTML</form>"
    assert_not @canvas.valid?
    assert @canvas.errors[:base].any? { |e| e.include?("locked") }
  end

  test "locked canvas rejects js_content changes" do
    @canvas.lock!(user: @user, reason: "Protected")

    @canvas.js_content = "function init() { return 'changed'; }"
    assert_not @canvas.valid?
  end

  test "locked canvas rejects css_content changes" do
    @canvas.lock!(user: @user, reason: "Protected")

    @canvas.css_content = ".form { color: blue; }"
    assert_not @canvas.valid?
  end

  test "locked canvas allows non-content changes" do
    @canvas.lock!(user: @user, reason: "Protected")

    @canvas.name = "Renamed Form"
    assert @canvas.valid?
    assert @canvas.save
    assert_equal "Renamed Form", @canvas.reload.name
  end

  test "unlocked canvas allows content changes" do
    @canvas.html_content = "<form>Updated HTML</form>"
    assert @canvas.valid?
    assert @canvas.save
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Scopes
  # ─────────────────────────────────────────────────────────────────────────────

  test "locked scope returns only locked canvases" do
    @canvas.lock!(user: @user)
    unlocked = ModuleCanvas.create!(
      app_module: @app_module, entity: @entity,
      name: "Unlocked", slug: "unlocked_canvas"
    )

    locked_canvases = @app_module.module_canvases.locked
    assert_includes locked_canvases, @canvas
    assert_not_includes locked_canvases, unlocked
  end

  test "unlocked scope returns only unlocked canvases" do
    @canvas.lock!(user: @user)
    unlocked = ModuleCanvas.create!(
      app_module: @app_module, entity: @entity,
      name: "Unlocked", slug: "unlocked_canvas2"
    )

    unlocked_canvases = @app_module.module_canvases.unlocked
    assert_not_includes unlocked_canvases, @canvas
    assert_includes unlocked_canvases, unlocked
  end
end
