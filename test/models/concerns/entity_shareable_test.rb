# frozen_string_literal: true

require 'test_helper'

class EntityShareableTest < ActiveSupport::TestCase
  fixtures :entities, :users, :landing_pages, :automation_codes, :websites, :web_apps

  setup do
    @entity = entities(:one)
    @user_one = users(:one)             # entity :one, admin
    @user_two = users(:two)             # entity :one, marketer (same entity)
    @other_entity_user = users(:another_user)  # entity :another_entity (different entity)
  end

  # ═══════════════════════════════════════════════════════════════
  # LANDING PAGE (uses user_id as owner_foreign_key)
  # ═══════════════════════════════════════════════════════════════

  test "LandingPage includes EntityShareable" do
    assert LandingPage.respond_to?(:visible_to_user)
    assert LandingPage.respond_to?(:shared)
    assert LandingPage.respond_to?(:not_shared)
  end

  test "LandingPage owner_foreign_key is user_id" do
    assert_equal :user_id, LandingPage.owner_foreign_key
  end

  test "landing page visible_to_user shows own private pages" do
    lp = LandingPage.create!(
      title: "My Private Page", entity: @entity, user: @user_one,
      shared_with_entity: false
    )
    
    visible = LandingPage.visible_to_user(@user_one)
    assert_includes visible, lp

    # Different user in same entity should NOT see private page
    visible_for_two = LandingPage.visible_to_user(@user_two)
    assert_not_includes visible_for_two, lp
  end

  test "landing page visible_to_user shows entity-shared pages from teammates" do
    lp = LandingPage.create!(
      title: "Shared Page", entity: @entity, user: @user_one,
      shared_with_entity: true
    )

    # User two in same entity should see shared page
    visible = LandingPage.visible_to_user(@user_two)
    assert_includes visible, lp

    # Owner should also see it
    visible_owner = LandingPage.visible_to_user(@user_one)
    assert_includes visible_owner, lp
  end

  test "landing page visible_to_user excludes other entity shared pages" do
    lp = LandingPage.create!(
      title: "Entity One Shared", entity: @entity, user: @user_one,
      shared_with_entity: true
    )

    # User from different entity should NOT see it even if shared
    visible = LandingPage.visible_to_user(@other_entity_user)
    assert_not_includes visible, lp
  end

  test "landing page share_with_entity! sets flag" do
    lp = LandingPage.create!(
      title: "Share Test", entity: @entity, user: @user_one,
      shared_with_entity: false
    )

    assert_not lp.shared?
    assert lp.private_asset?

    lp.share_with_entity!
    assert lp.shared?
    assert_not lp.private_asset?
  end

  test "landing page make_private! clears flag" do
    lp = LandingPage.create!(
      title: "Private Test", entity: @entity, user: @user_one,
      shared_with_entity: true
    )

    assert lp.shared?
    lp.make_private!
    assert_not lp.shared?
    assert lp.private_asset?
  end

  test "landing page visible_to_user? checks correctly" do
    lp = LandingPage.create!(
      title: "Visibility Check", entity: @entity, user: @user_one,
      shared_with_entity: false
    )

    assert lp.visible_to_user?(@user_one)       # Owner
    assert_not lp.visible_to_user?(@user_two)     # Same entity, not shared

    lp.share_with_entity!
    assert lp.visible_to_user?(@user_two)         # Now shared with entity
  end

  test "landing page visible_to_user returns none for nil user" do
    result = LandingPage.visible_to_user(nil)
    assert_empty result
  end

  # ═══════════════════════════════════════════════════════════════
  # AUTOMATION CODE (uses created_by_id as owner_foreign_key)
  # ═══════════════════════════════════════════════════════════════

  test "AutomationCode includes EntityShareable" do
    assert AutomationCode.respond_to?(:visible_to_user)
  end

  test "AutomationCode owner_foreign_key is created_by_id" do
    assert_equal :created_by_id, AutomationCode.owner_foreign_key
  end

  test "automation visible_to_user shows own and shared" do
    auto = AutomationCode.create!(
      name: "My Auto", entity: @entity, created_by: @user_one,
      trigger_type: 'manual', code: 'def execute(d); end',
      shared_with_entity: false
    )

    assert_includes AutomationCode.visible_to_user(@user_one), auto
    assert_not_includes AutomationCode.visible_to_user(@user_two), auto

    auto.share_with_entity!
    assert_includes AutomationCode.visible_to_user(@user_two), auto
  end

  # ═══════════════════════════════════════════════════════════════
  # WEBSITE (uses created_by_id as owner_foreign_key)
  # ═══════════════════════════════════════════════════════════════

  test "Website includes EntityShareable" do
    assert Website.respond_to?(:visible_to_user)
  end

  test "website visible_to_user scopes correctly" do
    site = Website.create!(
      name: "My Site", entity: @entity, created_by: @user_one,
      shared_with_entity: false
    )

    assert_includes Website.visible_to_user(@user_one), site
    assert_not_includes Website.visible_to_user(@user_two), site

    site.share_with_entity!
    assert_includes Website.visible_to_user(@user_two), site
  end

  # ═══════════════════════════════════════════════════════════════
  # WEB APP (uses created_by_id as owner_foreign_key)
  # ═══════════════════════════════════════════════════════════════

  test "WebApp includes EntityShareable" do
    assert WebApp.respond_to?(:visible_to_user)
  end

  test "web_app visible_to_user scopes correctly" do
    wa = WebApp.create!(
      name: "My App", entity: @entity, created_by: @user_one,
      shared_with_entity: false
    )

    assert_includes WebApp.visible_to_user(@user_one), wa
    assert_not_includes WebApp.visible_to_user(@user_two), wa

    wa.share_with_entity!
    assert_includes WebApp.visible_to_user(@user_two), wa
  end

  # ═══════════════════════════════════════════════════════════════
  # SHARED / NOT_SHARED SCOPES
  # ═══════════════════════════════════════════════════════════════

  test "shared scope returns only shared records" do
    LandingPage.create!(title: "Shared", entity: @entity, user: @user_one, shared_with_entity: true)
    LandingPage.create!(title: "Private", entity: @entity, user: @user_one, shared_with_entity: false)

    LandingPage.shared.each do |lp|
      assert lp.shared_with_entity?, "Expected all records from .shared to have shared_with_entity=true"
    end
  end

  test "not_shared scope returns only private records" do
    LandingPage.create!(title: "Shared2", entity: @entity, user: @user_one, shared_with_entity: true)
    LandingPage.create!(title: "Private2", entity: @entity, user: @user_one, shared_with_entity: false)

    LandingPage.not_shared.each do |lp|
      assert_not lp.shared_with_entity?, "Expected all records from .not_shared to have shared_with_entity=false"
    end
  end
end
