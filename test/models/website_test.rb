# frozen_string_literal: true

require 'test_helper'

class WebsiteTest < ActiveSupport::TestCase
  fixtures :entities, :users, :websites, :website_pages

  # ============================================
  # VALIDATIONS
  # ============================================

  test "requires name" do
    website = Website.new(
      entity: entities(:one),
      created_by: users(:one),
      slug: "test"
    )
    assert_not website.valid?
    assert_includes website.errors[:name], "can't be blank"
  end

  test "requires unique slug per entity" do
    existing = websites(:published_site)
    
    website = Website.new(
      entity: existing.entity,
      created_by: users(:one),
      name: "Duplicate",
      slug: existing.slug
    )
    assert_not website.valid?
    assert_includes website.errors[:slug], "has already been taken"
  end

  test "allows same slug in different entities" do
    website = Website.new(
      entity: entities(:two),  # Different entity
      created_by: users(:two),
      name: "Same Slug",
      slug: websites(:published_site).slug
    )
    assert website.valid?, website.errors.full_messages.join(', ')
  end

  test "validates subdomain format" do
    website = Website.new(
      entity: entities(:one),
      created_by: users(:one),
      name: "Test",
      slug: "test",
      subdomain: "Invalid Subdomain!"
    )
    assert_not website.valid?
    assert website.errors[:subdomain].any?
  end

  test "validates status inclusion" do
    website = Website.new(
      entity: entities(:one),
      created_by: users(:one),
      name: "Test",
      slug: "test",
      status: "invalid"
    )
    assert_not website.valid?
    assert_includes website.errors[:status], "is not included in the list"
  end

  test "validates theme inclusion when present" do
    website = Website.new(
      entity: entities(:one),
      created_by: users(:one),
      name: "Test",
      slug: "test",
      theme: "invalid_theme"
    )
    assert_not website.valid?
    assert_includes website.errors[:theme], "is not included in the list"
  end

  # ============================================
  # STATUS HELPERS
  # ============================================

  test "published? returns correct value" do
    assert websites(:published_site).published?
    assert_not websites(:draft_site).published?
  end

  test "draft? returns correct value" do
    assert websites(:draft_site).draft?
    assert_not websites(:published_site).draft?
  end

  test "publish! transitions to published" do
    website = websites(:draft_site)
    website.publish!
    
    assert website.published?
    assert_not_nil website.published_at
  end

  test "unpublish! transitions to draft" do
    website = websites(:published_site)
    website.unpublish!
    
    assert website.draft?
  end

  test "archive! transitions to archived" do
    website = websites(:draft_site)
    website.archive!
    
    assert_equal 'archived', website.status
  end

  # ============================================
  # PAGE HELPERS
  # ============================================

  test "homepage returns the homepage" do
    website = websites(:published_site)
    homepage = website.homepage
    
    assert_not_nil homepage
    assert homepage.is_homepage?
  end

  test "nav_pages returns ordered navigable pages" do
    website = websites(:published_site)
    nav_pages = website.nav_pages
    
    assert nav_pages.all? { |p| p.show_in_nav? }
    assert_equal nav_pages.pluck(:nav_order).sort, nav_pages.pluck(:nav_order)
  end

  test "page_count returns correct count" do
    website = websites(:published_site)
    assert_equal website.website_pages.count, website.page_count
  end

  test "add_page! creates a new page" do
    website = websites(:draft_site)
    original_count = website.page_count
    
    website.add_page!(name: "New Page", template: "content")
    
    assert_equal original_count + 1, website.page_count
    assert website.website_pages.exists?(name: "New Page")
  end

  # ============================================
  # URL HELPERS
  # ============================================

  test "public_url uses custom_domain when present" do
    website = websites(:site_with_domain)
    assert_equal "https://#{website.custom_domain}", website.public_url
  end

  test "public_url uses subdomain when no custom_domain" do
    website = Website.new(subdomain: "test", slug: "test-site")
    assert_includes website.public_url, "test.amoslabs.com"
  end

  test "public_url falls back to slug path" do
    website = Website.new(slug: "test-site")
    assert_equal "/sites/test-site", website.public_url
  end

  test "preview_url returns correct path" do
    website = websites(:published_site)
    assert_equal "/sites/#{website.slug}/preview", website.preview_url
  end

  # ============================================
  # RENDERING
  # ============================================

  test "theme_styles generates CSS with config colors" do
    website = websites(:published_site)
    styles = website.theme_styles
    
    assert_includes styles, "--primary-color"
    assert_includes styles, website.theme_config['primary_color'] if website.theme_config['primary_color']
  end

  test "to_preview returns expected structure" do
    website = websites(:published_site)
    preview = website.to_preview
    
    assert_equal website.id, preview[:id]
    assert_equal website.name, preview[:name]
    assert_equal website.status, preview[:status]
    assert_equal website.page_count, preview[:page_count]
    assert preview[:public_url].present?
  end

  # ============================================
  # CALLBACKS
  # ============================================

  test "generates slug from name on create" do
    website = Website.create!(
      entity: entities(:one),
      created_by: users(:one),
      name: "My New Website"
    )
    
    assert_equal "my-new-website", website.slug
  end

  test "generates default layout on create" do
    website = Website.create!(
      entity: entities(:one),
      created_by: users(:one),
      name: "Layout Test"
    )
    
    assert_not_nil website.header_html
    assert_not_nil website.footer_html
  end

  # ============================================
  # SCOPES
  # ============================================

  test "published scope returns only published" do
    Website.published.each do |website|
      assert_equal 'published', website.status
    end
  end

  test "draft scope returns only drafts" do
    Website.draft.each do |website|
      assert_equal 'draft', website.status
    end
  end

  test "for_entity scope filters correctly" do
    entity = entities(:one)
    Website.for_entity(entity.id).each do |website|
      assert_equal entity.id, website.entity_id
    end
  end
end

