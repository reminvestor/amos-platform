# frozen_string_literal: true

require 'test_helper'

class WebAppTest < ActiveSupport::TestCase
  fixtures :entities, :users, :websites, :web_apps

  # ============================================
  # VALIDATIONS
  # ============================================

  test "requires name" do
    web_app = WebApp.new(
      entity: entities(:one),
      created_by: users(:one),
      slug: "test"
    )
    assert_not web_app.valid?
    assert_includes web_app.errors[:name], "can't be blank"
  end

  test "requires unique slug per entity" do
    existing = web_apps(:active_portal)
    
    web_app = WebApp.new(
      entity: existing.entity,
      created_by: users(:one),
      name: "Duplicate",
      slug: existing.slug
    )
    assert_not web_app.valid?
    assert_includes web_app.errors[:slug], "has already been taken"
  end

  test "validates status inclusion" do
    web_app = WebApp.new(
      entity: entities(:one),
      created_by: users(:one),
      name: "Test",
      slug: "test",
      status: "invalid"
    )
    assert_not web_app.valid?
    assert_includes web_app.errors[:status], "is not included in the list"
  end

  # ============================================
  # STATUS HELPERS
  # ============================================

  test "active? returns correct value" do
    assert web_apps(:active_portal).active?
    assert_not web_apps(:draft_app).active?
  end

  test "activate! transitions to active" do
    web_app = web_apps(:draft_app)
    web_app.activate!
    
    assert web_app.active?
  end

  test "pause! transitions to paused" do
    web_app = web_apps(:active_portal)
    web_app.pause!
    
    assert_equal 'paused', web_app.status
  end

  test "archive! transitions to archived" do
    web_app = web_apps(:draft_app)
    web_app.archive!
    
    assert_equal 'archived', web_app.status
  end

  # ============================================
  # URL HELPERS
  # ============================================

  test "public_url uses custom_domain when present" do
    web_app = WebApp.new(custom_domain: "app.example.com", slug: "test")
    assert_equal "https://app.example.com", web_app.public_url
  end

  test "public_url uses subdomain when no custom_domain" do
    web_app = web_apps(:public_app)
    assert_includes web_app.public_url, "#{web_app.subdomain}.app.amoslabs.com"
  end

  test "public_url falls back to slug path" do
    web_app = web_apps(:active_portal)
    web_app.subdomain = nil
    web_app.custom_domain = nil
    
    assert_equal "/apps/#{web_app.slug}", web_app.public_url
  end

  test "login_url appends /login" do
    web_app = web_apps(:active_portal)
    assert_includes web_app.login_url, "/login"
  end

  test "dashboard_url appends /dashboard" do
    web_app = web_apps(:active_portal)
    assert_includes web_app.dashboard_url, "/dashboard"
  end

  # ============================================
  # AUTHENTICATION
  # ============================================

  test "auth_methods returns configured methods" do
    web_app = web_apps(:active_portal)
    assert_includes web_app.auth_methods, "email"
    assert_includes web_app.auth_methods, "google"
  end

  test "allows_registration? returns config value" do
    web_app = web_apps(:active_portal)
    assert web_app.allows_registration?
    
    web_app.auth_config['allow_registration'] = false
    assert_not web_app.allows_registration?
  end

  test "requires_email_verification? returns config value" do
    web_app = web_apps(:active_portal)
    assert_not web_app.requires_email_verification?
    
    web_app.auth_config['require_email_verification'] = true
    assert web_app.requires_email_verification?
  end

  test "session_timeout returns configured or default" do
    web_app = web_apps(:active_portal)
    assert_equal 3600, web_app.session_timeout
    
    web_app.auth_config['session_timeout'] = 7200
    assert_equal 7200, web_app.session_timeout
  end

  # ============================================
  # ROLES & PERMISSIONS
  # ============================================

  test "available_roles returns role names" do
    web_app = web_apps(:active_portal)
    roles = web_app.available_roles
    
    assert_includes roles, 'admin'
    assert_includes roles, 'customer'
  end

  test "role_permissions returns permissions for role" do
    web_app = web_apps(:active_portal)
    
    admin_perms = web_app.role_permissions('admin')
    assert_includes admin_perms, '*'
    
    customer_perms = web_app.role_permissions('customer')
    assert_includes customer_perms, 'read'
  end

  test "add_role! adds new role" do
    web_app = web_apps(:active_portal)
    original_count = web_app.roles.count
    
    web_app.add_role!(name: 'moderator', permissions: ['read', 'edit', 'delete'])
    
    assert_equal original_count + 1, web_app.roles.count
    assert_includes web_app.available_roles, 'moderator'
  end

  # ============================================
  # FEATURES
  # ============================================

  test "has_feature? checks feature presence" do
    web_app = web_apps(:active_portal)
    
    assert web_app.has_feature?('user_dashboard')
    assert_not web_app.has_feature?('nonexistent')
  end

  test "enable_feature! adds feature" do
    web_app = web_apps(:draft_app)
    assert_not web_app.has_feature?('export_data')
    
    web_app.enable_feature!('export_data')
    
    assert web_app.has_feature?('export_data')
  end

  test "disable_feature! removes feature" do
    web_app = web_apps(:active_portal)
    assert web_app.has_feature?('notifications')
    
    web_app.disable_feature!('notifications')
    
    assert_not web_app.has_feature?('notifications')
  end

  # ============================================
  # ANALYTICS
  # ============================================

  test "track_activity! updates timestamp" do
    web_app = web_apps(:active_portal)
    web_app.update!(last_activity_at: nil)
    
    web_app.track_activity!
    
    assert_not_nil web_app.last_activity_at
  end

  # ============================================
  # SERIALIZATION
  # ============================================

  test "to_preview returns expected structure" do
    web_app = web_apps(:active_portal)
    preview = web_app.to_preview
    
    assert_equal web_app.id, preview[:id]
    assert_equal web_app.name, preview[:name]
    assert_equal web_app.status, preview[:status]
    assert preview[:public_url].present?
    assert_equal web_app.requires_auth, preview[:requires_auth]
  end

  test "to_config returns comprehensive config" do
    web_app = web_apps(:active_portal)
    config = web_app.to_config
    
    assert_equal web_app.name, config[:name]
    assert config[:auth].present?
    assert config[:roles].present?
    assert config[:features].present?
    assert config[:branding].present?
  end

  # ============================================
  # CALLBACKS
  # ============================================

  test "generates slug from name on create" do
    web_app = WebApp.create!(
      entity: entities(:one),
      created_by: users(:one),
      name: "My New App"
    )
    
    assert_equal "my-new-app", web_app.slug
  end

  test "sets default auth config on create" do
    web_app = WebApp.create!(
      entity: entities(:one),
      created_by: users(:one),
      name: "Default Config Test"
    )
    
    assert web_app.auth_config.present?
    assert web_app.auth_methods.any?
    assert web_app.roles.any?
  end

  # ============================================
  # SCOPES
  # ============================================

  test "active scope returns only active apps" do
    WebApp.active.each do |web_app|
      assert_equal 'active', web_app.status
    end
  end

  test "for_entity scope filters correctly" do
    entity = entities(:one)
    WebApp.for_entity(entity.id).each do |web_app|
      assert_equal entity.id, web_app.entity_id
    end
  end
end

