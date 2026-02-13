# frozen_string_literal: true

require 'test_helper'

class ScoutSharingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  fixtures :entities, :users, :landing_pages, :automation_codes, :websites, :web_apps

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update_column(:entity_id, @entity.id) unless @user.entity_id == @entity.id
    sign_in @user
  end

  # ═══════════════════════════════════════════════════════════════
  # toggle_asset_sharing endpoint
  # ═══════════════════════════════════════════════════════════════

  test "toggle_asset_sharing toggles landing page from private to shared" do
    lp = LandingPage.create!(
      title: "Toggle Test LP", entity: @entity, user: @user,
      shared_with_entity: false
    )

    post scout_toggle_asset_sharing_path, params: {
      asset_type: 'landing_page', asset_id: lp.id
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body['success']
    assert body['shared']
    assert lp.reload.shared_with_entity?
  end

  test "toggle_asset_sharing toggles landing page from shared to private" do
    lp = LandingPage.create!(
      title: "Untoggle Test LP", entity: @entity, user: @user,
      shared_with_entity: true
    )

    post scout_toggle_asset_sharing_path, params: {
      asset_type: 'landing_page', asset_id: lp.id
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body['success']
    assert_not body['shared']
    assert_not lp.reload.shared_with_entity?
  end

  test "toggle_asset_sharing works for automation" do
    auto = AutomationCode.create!(
      name: "Toggle Auto", entity: @entity, created_by: @user,
      trigger_type: 'manual', code: 'def execute(d); end',
      shared_with_entity: false
    )

    post scout_toggle_asset_sharing_path, params: {
      asset_type: 'automation', asset_id: auto.id
    }, as: :json

    assert_response :success
    assert auto.reload.shared_with_entity?
  end

  test "toggle_asset_sharing works for website" do
    site = Website.create!(
      name: "Toggle Site", entity: @entity, created_by: @user,
      shared_with_entity: false
    )

    post scout_toggle_asset_sharing_path, params: {
      asset_type: 'website', asset_id: site.id
    }, as: :json

    assert_response :success
    assert site.reload.shared_with_entity?
  end

  test "toggle_asset_sharing works for web_app" do
    wa = WebApp.create!(
      name: "Toggle App", entity: @entity, created_by: @user,
      shared_with_entity: false
    )

    post scout_toggle_asset_sharing_path, params: {
      asset_type: 'web_app', asset_id: wa.id
    }, as: :json

    assert_response :success
    assert wa.reload.shared_with_entity?
  end

  test "toggle_asset_sharing returns 404 for non-existent asset" do
    post scout_toggle_asset_sharing_path, params: {
      asset_type: 'landing_page', asset_id: 999999
    }, as: :json

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_not body['success']
  end

  test "toggle_asset_sharing returns 404 for asset owned by another user" do
    other_user = users(:two)
    lp = LandingPage.create!(
      title: "Other User LP", entity: @entity, user: other_user,
      shared_with_entity: false
    )

    # Current user (user :one) tries to toggle other user's private LP
    post scout_toggle_asset_sharing_path, params: {
      asset_type: 'landing_page', asset_id: lp.id
    }, as: :json

    assert_response :not_found
    assert_not lp.reload.shared_with_entity?
  end

  test "toggle_asset_sharing rejects invalid asset_type" do
    post scout_toggle_asset_sharing_path, params: {
      asset_type: 'nonexistent', asset_id: 1
    }, as: :json

    assert_response :not_found
  end

  # ═══════════════════════════════════════════════════════════════
  # update_website_page endpoint
  # ═══════════════════════════════════════════════════════════════

  test "update_website_page saves html content" do
    site = Website.create!(
      name: "Editor Site", entity: @entity, created_by: @user
    )
    page = site.add_page!(name: "About")

    post scout_update_website_page_path, params: {
      website_id: site.id,
      page_id: page.id,
      html_content: "<h1>Updated Content</h1><p>New paragraph</p>"
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body['success']
    assert_equal "<h1>Updated Content</h1><p>New paragraph</p>", page.reload.html_content
  end

  test "update_website_page returns 404 for non-existent page" do
    site = Website.create!(
      name: "Missing Page Site", entity: @entity, created_by: @user
    )

    post scout_update_website_page_path, params: {
      website_id: site.id,
      page_id: 999999,
      html_content: "<p>Test</p>"
    }, as: :json

    assert_response :not_found
  end

  test "update_website_page rejects unauthorized user" do
    other_user = users(:two)
    site = Website.create!(
      name: "Not My Site", entity: @entity, created_by: other_user,
      shared_with_entity: false
    )
    page = site.add_page!(name: "Secret Page")

    post scout_update_website_page_path, params: {
      website_id: site.id,
      page_id: page.id,
      html_content: "<p>Hacked!</p>"
    }, as: :json

    assert_response :forbidden
    assert_not_equal "<p>Hacked!</p>", page.reload.html_content
  end

  test "update_website_page allows editing shared website" do
    other_user = users(:two)
    site = Website.create!(
      name: "Shared Site", entity: @entity, created_by: other_user,
      shared_with_entity: true
    )
    page = site.add_page!(name: "Shared Page")

    post scout_update_website_page_path, params: {
      website_id: site.id,
      page_id: page.id,
      html_content: "<h2>Collaborative Edit</h2>"
    }, as: :json

    assert_response :success
    assert_equal "<h2>Collaborative Edit</h2>", page.reload.html_content
  end

  private

  def scout_toggle_asset_sharing_path
    "/scout/toggle_asset_sharing"
  end

  def scout_update_website_page_path
    "/scout/update_website_page"
  end
end
