# frozen_string_literal: true

require "test_helper"

class V3::CanvasPlatformToolsTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)
    @update_tool = V3::Tools::PlatformUpdateTool.new(user: @user, entity: @entity)
    @query_tool = V3::Tools::PlatformQueryTool.new(user: @user, entity: @entity)

    @app_module = AppModule.create!(
      entity: @entity,
      created_by: @user,
      name: "CRM Contacts",
      slug: "crm_contacts_#{SecureRandom.hex(4)}",
      status: "active"
    )
    @canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Contact Form",
      slug: "contact_form",
      canvas_type: "form",
      is_default: true,
      html_content: "<form>Contact Fields</form>",
      js_content: "function contactForm() {}",
      css_content: ".contact-form { padding: 1rem; }"
    )
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM_UPDATE — Canvas Lock
  # ══════════════════════════════════════════════════════════════

  test "lock canvas by ID" do
    result = @update_tool.execute({
      "type" => "canvas",
      "id" => @canvas.id,
      "data" => { "lock" => true, "reason" => "User's custom contact form" }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert result[:is_locked]
    assert_includes result[:message], "LOCKED"

    @canvas.reload
    assert @canvas.locked?
    assert_equal "User's custom contact form", @canvas.lock_reason
  end

  test "lock canvas by module slug" do
    result = @update_tool.execute({
      "type" => "canvas",
      "id" => @app_module.slug,
      "data" => { "lock" => true }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert result[:is_locked]

    @canvas.reload
    assert @canvas.locked?
  end

  test "lock already-locked canvas returns success" do
    @canvas.lock!(user: @user)

    result = @update_tool.execute({
      "type" => "canvas",
      "id" => @canvas.id,
      "data" => { "lock" => true }
    })

    assert result[:success] != false
    assert_includes result[:message], "already locked"
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM_UPDATE — Canvas Unlock
  # ══════════════════════════════════════════════════════════════

  test "unlock canvas" do
    @canvas.lock!(user: @user, reason: "Locked")

    result = @update_tool.execute({
      "type" => "canvas",
      "id" => @canvas.id,
      "data" => { "lock" => false }
    })

    assert result[:success] != false
    assert_equal false, result[:is_locked]
    assert_includes result[:message], "unlocked"

    @canvas.reload
    assert_not @canvas.locked?
  end

  test "unlock already-unlocked canvas returns success" do
    result = @update_tool.execute({
      "type" => "canvas",
      "id" => @canvas.id,
      "data" => { "lock" => false }
    })

    assert result[:success] != false
    assert_includes result[:message], "already unlocked"
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM_UPDATE — Canvas Version Restore
  # ══════════════════════════════════════════════════════════════

  test "restore canvas version" do
    original_html = @canvas.html_content
    @canvas.update!(html_content: "<form>Updated Fields</form>")

    result = @update_tool.execute({
      "type" => "canvas",
      "id" => @canvas.id,
      "data" => { "restore_version" => 1 }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert_equal 1, result[:restored_version]

    @canvas.reload
    assert_equal original_html, @canvas.html_content
  end

  test "restore nonexistent version returns error" do
    result = @update_tool.execute({
      "type" => "canvas",
      "id" => @canvas.id,
      "data" => { "restore_version" => 999 }
    })

    assert_equal false, result[:success]
    assert_includes result[:error], "not found"
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM_UPDATE — Canvas Not Found
  # ══════════════════════════════════════════════════════════════

  test "canvas not found returns error" do
    result = @update_tool.execute({
      "type" => "canvas",
      "id" => 999999,
      "data" => { "lock" => true }
    })

    assert_equal false, result[:success]
    assert_includes result[:error], "not found"
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM_QUERY — Canvas Search
  # ══════════════════════════════════════════════════════════════

  test "query canvases lists all canvases" do
    result = @query_tool.execute({ "type" => "canvases" })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert result[:canvases].is_a?(Array)
    assert result[:count] >= 1
    
    slugs = result[:canvases].map { |c| c[:slug] }
    assert_includes slugs, "contact_form"
  end

  test "query canvases with search filter" do
    result = @query_tool.execute({ "type" => "canvases", "search" => "contact" })

    assert result[:success] != false
    assert result[:canvases].any? { |c| c[:slug].include?("contact") }
  end

  test "query canvas by ID returns details" do
    result = @query_tool.execute({ "type" => "canvases", "id" => @canvas.id })

    assert result[:success] != false
    assert_equal @canvas.id, result[:canvas][:id]
    assert_equal "Contact Form", result[:canvas][:name]
    assert_equal false, result[:canvas][:is_locked]
  end

  test "query canvas by module slug" do
    result = @query_tool.execute({ "type" => "canvases", "id" => @app_module.slug })

    assert result[:success] != false
    assert result[:canvas].present?
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM_QUERY — Canvas Versions
  # ══════════════════════════════════════════════════════════════

  test "query canvas_versions returns version history" do
    @canvas.update!(html_content: "<form>V2</form>")
    @canvas.update!(js_content: "function v3() {}")

    result = @query_tool.execute({ "type" => "canvas_versions", "id" => @canvas.id })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert_equal @canvas.id, result[:canvas_id]
    assert result[:versions].is_a?(Array)
    assert result[:total_versions] >= 3 # v1 (saved), v2 (saved), current
  end

  test "query canvas_versions without id returns error" do
    result = @query_tool.execute({ "type" => "canvas_versions" })

    assert_equal false, result[:success]
    assert_includes result[:error], "required"
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM_QUERY — Locked Canvas Info
  # ══════════════════════════════════════════════════════════════

  test "query canvases shows locked status" do
    @canvas.lock!(user: @user, reason: "Custom form")

    result = @query_tool.execute({ "type" => "canvases" })

    locked_canvas = result[:canvases].find { |c| c[:id] == @canvas.id }
    assert locked_canvas
    assert_equal true, locked_canvas[:is_locked]
    assert_equal "Custom form", locked_canvas[:lock_reason]
  end

  test "query canvases reports locked count" do
    @canvas.lock!(user: @user)

    result = @query_tool.execute({ "type" => "canvases" })
    assert result[:locked_count] >= 1
  end
end
