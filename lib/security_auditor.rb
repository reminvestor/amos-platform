# frozen_string_literal: true

# SecurityAuditor - Comprehensive security audit tool for AMOS platform
#
# Performs static analysis to detect:
# - Entity isolation violations (multi-tenant security)
# - Admin area protection gaps
# - Role-based access control issues
# - API security vulnerabilities
# - Authentication bypass risks
#
# Usage:
#   auditor = SecurityAuditor.new
#   results = auditor.run_full_audit
#   auditor.print_report(results)
#
class SecurityAuditor
  SEVERITY_CRITICAL = 'CRITICAL'
  SEVERITY_HIGH = 'HIGH'
  SEVERITY_MEDIUM = 'MEDIUM'
  SEVERITY_LOW = 'LOW'

  # Controllers that are intentionally public (no auth required)
  PUBLIC_CONTROLLERS = %w[
    HomeController
    LandingPagesController
    HealthController
    Devise::SessionsController
    Devise::RegistrationsController
    Devise::PasswordsController
  ].freeze

  # Admin controllers that should have strict protection
  ADMIN_NAMESPACE = 'Admin::'

  # Models that are system-wide and don't need entity scoping
  SYSTEM_MODELS = %w[
    Entity
    User
    AdminUser
    Integration
    SystemSetting
    SystemDocument
    AiUsageLog
  ].freeze

  def initialize(verbose: false)
    @verbose = verbose
    @issues = []
    @stats = {
      controllers_scanned: 0,
      models_scanned: 0,
      routes_analyzed: 0
    }
  end

  # Run complete security audit across all categories
  def run_full_audit
    puts "🔒 Starting AMOS Security Audit..."
    puts "━" * 60

    @issues = []

    audit_entity_isolation
    audit_admin_protection
    audit_role_based_access
    audit_api_security
    audit_authentication_bypass

    puts "\n✅ Audit complete. Found #{@issues.size} issues."

    {
      issues: @issues,
      stats: @stats,
      summary: generate_summary
    }
  end

  # Run specific audit category
  def run_category_audit(category)
    @issues = []

    case category
    when 'entity-isolation'
      audit_entity_isolation
    when 'admin-protection'
      audit_admin_protection
    when 'role-checks'
      audit_role_based_access
    when 'api-security'
      audit_api_security
    when 'auth-bypass'
      audit_authentication_bypass
    else
      raise "Unknown audit category: #{category}"
    end

    {
      issues: @issues,
      stats: @stats,
      summary: generate_summary
    }
  end

  # Print detailed security report
  def print_report(results)
    puts "\n"
    puts "=" * 60
    puts "=== AMOS SECURITY AUDIT REPORT ==="
    puts "=" * 60
    puts "Run Date: #{Time.now.utc}"
    puts ""

    # Group issues by severity
    critical = results[:issues].select { |i| i[:severity] == SEVERITY_CRITICAL }
    high = results[:issues].select { |i| i[:severity] == SEVERITY_HIGH }
    medium = results[:issues].select { |i| i[:severity] == SEVERITY_MEDIUM }
    low = results[:issues].select { |i| i[:severity] == SEVERITY_LOW }

    # Print critical issues
    if critical.any?
      puts "🚨 CRITICAL ISSUES (#{critical.size}):"
      puts "━" * 60
      critical.each { |issue| print_issue(issue) }
      puts ""
    end

    # Print high issues
    if high.any?
      puts "⚠️  HIGH ISSUES (#{high.size}):"
      puts "━" * 60
      high.each { |issue| print_issue(issue) }
      puts ""
    end

    # Print medium issues
    if medium.any?
      puts "ℹ️  MEDIUM ISSUES (#{medium.size}):"
      puts "━" * 60
      medium.each { |issue| print_issue(issue) }
      puts ""
    end

    # Print low issues
    if low.any?
      puts "💡 LOW ISSUES (#{low.size}):"
      puts "━" * 60
      low.each { |issue| print_issue(issue) }
      puts ""
    end

    # Print summary
    puts "SUMMARY:"
    puts "━" * 60
    puts "Total Issues: #{results[:issues].size}"
    puts "  Critical: #{critical.size}"
    puts "  High: #{high.size}"
    puts "  Medium: #{medium.size}"
    puts "  Low: #{low.size}"
    puts ""
    puts "Controllers Scanned: #{results[:stats][:controllers_scanned]}"
    puts "Models Scanned: #{results[:stats][:models_scanned]}"
    puts "Routes Analyzed: #{results[:stats][:routes_analyzed]}"
    puts ""

    # Print recommendations
    if critical.any?
      puts "⚠️  ACTION REQUIRED: Fix CRITICAL issues immediately!"
    elsif high.any?
      puts "⚠️  ACTION RECOMMENDED: Fix HIGH issues within 24 hours"
    elsif medium.any?
      puts "✅ Good security posture. Address MEDIUM issues as time permits."
    else
      puts "✅ Excellent! No critical security issues found."
    end

    puts "=" * 60
  end

  private

  def print_issue(issue)
    puts "[#{issue[:severity]}] #{issue[:title]}"
    puts "  Location: #{issue[:location]}" if issue[:location]
    puts "  Risk: #{issue[:risk]}"
    puts "  Fix: #{issue[:fix]}"
    puts "  Impact: #{issue[:impact]}" if issue[:impact]
    puts ""
  end

  def add_issue(title:, severity:, risk:, fix:, location: nil, impact: nil, category: nil)
    @issues << {
      title: title,
      severity: severity,
      risk: risk,
      fix: fix,
      location: location,
      impact: impact,
      category: category
    }
  end

  # === AUDIT CATEGORY: Entity Isolation ===
  def audit_entity_isolation
    log_section "Auditing Entity Isolation (Multi-Tenant Security)"

    # Check controllers for EntityScoped concern
    controller_files = Dir.glob(Rails.root.join('app', 'controllers', '**', '*_controller.rb'))
    @stats[:controllers_scanned] = controller_files.size

    controller_files.each do |file|
      next if file.include?('admin/') # Admin controllers handled separately
      next if file.include?('application_controller')

      controller_name = File.basename(file, '.rb').camelize
      content = File.read(file)

      # Skip public controllers
      next if PUBLIC_CONTROLLERS.any? { |pc| file.include?(pc.underscore) }

      # Check for EntityScoped concern or manual entity filtering
      unless content.include?('EntityScoped') ||
             content.include?('current_entity') ||
             content.include?('before_action :set_entity')
        add_issue(
          title: "Missing Entity Scoping in #{controller_name}",
          severity: SEVERITY_CRITICAL,
          risk: "Users can potentially access other tenants' data",
          fix: "Add 'include EntityScoped' concern or implement manual entity filtering",
          location: file,
          impact: "Cross-tenant data breach possible",
          category: :entity_isolation
        )
      end
    end

    # Check models for entity association
    model_files = Dir.glob(Rails.root.join('app', 'models', '*.rb'))
    @stats[:models_scanned] = model_files.size

    model_files.each do |file|
      model_name = File.basename(file, '.rb').camelize
      next if SYSTEM_MODELS.include?(model_name)
      next if model_name.include?('ApplicationRecord')

      content = File.read(file)

      # Check for belongs_to :entity
      unless content.include?('belongs_to :entity')
        add_issue(
          title: "Model #{model_name} Missing Entity Association",
          severity: SEVERITY_HIGH,
          risk: "Model data not scoped to entities, potential data leakage",
          fix: "Add 'belongs_to :entity' to #{model_name} model",
          location: file,
          category: :entity_isolation
        )
      end
    end

    log_verbose "✓ Entity isolation audit complete"
  end

  # === AUDIT CATEGORY: Admin Protection ===
  def audit_admin_protection
    log_section "Auditing Admin Area Protection"

    # Check all Admin::* controllers
    admin_controller_files = Dir.glob(Rails.root.join('app', 'controllers', 'admin', '*_controller.rb'))

    admin_controller_files.each do |file|
      next if file.include?('base_controller') # BaseController is the security layer

      controller_name = File.basename(file, '.rb').camelize
      content = File.read(file)

      # Check inheritance from Admin::BaseController
      unless content.match?(/class\s+Admin::\w+\s+<\s+Admin::BaseController/)
        add_issue(
          title: "Admin Controller Not Inheriting from BaseController",
          severity: SEVERITY_CRITICAL,
          risk: "Admin controller bypasses authentication and authorization",
          fix: "Change class definition to inherit from Admin::BaseController",
          location: file,
          impact: "Unauthenticated access to admin functionality",
          category: :admin_protection
        )
      end
    end

    # Check Admin::BaseController for authenticate_admin!
    base_controller_path = Rails.root.join('app', 'controllers', 'admin', 'base_controller.rb')
    if File.exist?(base_controller_path)
      content = File.read(base_controller_path)

      unless content.include?('authenticate_admin!')
        add_issue(
          title: "Admin::BaseController Missing Authentication",
          severity: SEVERITY_CRITICAL,
          risk: "All admin controllers are unprotected",
          fix: "Add 'before_action :authenticate_admin!' to Admin::BaseController",
          location: base_controller_path.to_s,
          impact: "Complete admin area compromise",
          category: :admin_protection
        )
      end

      # Check for auto-escalation vulnerability
      if content.include?('AdminUser.find_or_create_by') && content.include?('super_admin')
        add_issue(
          title: "Admin Auto-Escalation Vulnerability",
          severity: SEVERITY_CRITICAL,
          risk: "Regular users with admin role automatically become super_admin",
          fix: "Remove auto-creation logic. Manually assign AdminUser records with appropriate roles",
          location: "#{base_controller_path}:12",
          impact: "Privilege escalation from admin to super_admin",
          category: :admin_protection
        )
      end
    end

    log_verbose "✓ Admin protection audit complete"
  end

  # === AUDIT CATEGORY: Role-Based Access Control ===
  def audit_role_based_access
    log_section "Auditing Role-Based Access Control"

    # Check User model for role enumeration
    user_model_path = Rails.root.join('app', 'models', 'user.rb')
    if File.exist?(user_model_path)
      content = File.read(user_model_path)

      unless content.include?('enum') && (content.include?('role') || content.include?('roles'))
        add_issue(
          title: "User Model Missing Role Enumeration",
          severity: SEVERITY_HIGH,
          risk: "No structured role system for authorization",
          fix: "Add 'enum role: { viewer: 0, marketer: 1, admin: 2 }' to User model",
          location: user_model_path.to_s,
          category: :role_access
        )
      end
    end

    # Check EntityUser for role enforcement
    entity_user_path = Rails.root.join('app', 'models', 'entity_user.rb')
    if File.exist?(entity_user_path)
      content = File.read(entity_user_path)

      unless content.include?('enum') && content.include?('role')
        add_issue(
          title: "EntityUser Missing Role System",
          severity: SEVERITY_HIGH,
          risk: "No tenant-level role enforcement",
          fix: "Add 'enum role: { member: 0, admin: 1, owner: 2 }' to EntityUser model",
          location: entity_user_path.to_s,
          category: :role_access
        )
      end
    end

    # Check controllers for authorization before destructive actions
    controller_files = Dir.glob(Rails.root.join('app', 'controllers', '**', '*_controller.rb'))

    controller_files.each do |file|
      content = File.read(file)

      # Check for destroy/delete actions without authorization
      if content.match?(/def\s+(destroy|delete)\s*$/)
        unless content.include?('authorize') ||
               content.include?('can?') ||
               content.include?('policy') ||
               content.include?('check_permission')
          add_issue(
            title: "Destroy Action Without Authorization Check",
            severity: SEVERITY_MEDIUM,
            risk: "Users might delete records they shouldn't access",
            fix: "Add authorization check before destroy action (Pundit policy or custom check)",
            location: file,
            category: :role_access
          )
        end
      end
    end

    log_verbose "✓ Role-based access audit complete"
  end

  # === AUDIT CATEGORY: API Security ===
  def audit_api_security
    log_section "Auditing API Security"

    # Check User model for plaintext API key storage
    user_model_path = Rails.root.join('app', 'models', 'user.rb')
    if File.exist?(user_model_path)
      content = File.read(user_model_path)

      if content.include?('api_key')
        # Check if API keys are hashed
        unless content.include?('bcrypt') ||
               content.include?('has_secure_token') ||
               content.include?('Digest::SHA')
          add_issue(
            title: "API Keys Stored in Plaintext",
            severity: SEVERITY_CRITICAL,
            risk: "Database breach exposes all API tokens",
            fix: "Hash API keys using bcrypt or SHA256 before storage. Store only hash, compare with secure_compare",
            location: "#{user_model_path}:45",
            impact: "All API integrations compromised if database leaked",
            category: :api_security
          )
        end
      end
    end

    # Check for OAuth token encryption
    connection_model_path = Rails.root.join('app', 'models', 'connection.rb')
    if File.exist?(connection_model_path)
      content = File.read(connection_model_path)

      if content.include?('access_token') || content.include?('refresh_token')
        unless content.include?('encrypts') || content.include?('attr_encrypted')
          add_issue(
            title: "OAuth Tokens Not Encrypted at Rest",
            severity: SEVERITY_HIGH,
            risk: "OAuth tokens stored in plaintext in database",
            fix: "Use ActiveRecord::Encryption or attr_encrypted gem for token fields",
            location: connection_model_path.to_s,
            category: :api_security
          )
        end
      end
    end

    # Check for secure token comparison
    if File.exist?(user_model_path)
      content = File.read(user_model_path)

      if content.include?('api_key ==') || content.include?('token ==')
        add_issue(
          title: "Insecure Token Comparison (Timing Attack)",
          severity: SEVERITY_MEDIUM,
          risk: "Timing attacks can leak token information",
          fix: "Use ActiveSupport::SecurityUtils.secure_compare for token comparison",
          location: user_model_path.to_s,
          category: :api_security
        )
      end
    end

    log_verbose "✓ API security audit complete"
  end

  # === AUDIT CATEGORY: Authentication Bypass ===
  def audit_authentication_bypass
    log_section "Auditing Authentication Requirements"

    # Check ApplicationController for authenticate_user!
    app_controller_path = Rails.root.join('app', 'controllers', 'application_controller.rb')
    if File.exist?(app_controller_path)
      content = File.read(app_controller_path)

      unless content.include?('before_action :authenticate_user!')
        add_issue(
          title: "ApplicationController Missing Global Authentication",
          severity: SEVERITY_HIGH,
          risk: "Controllers might forget to require authentication",
          fix: "Add 'before_action :authenticate_user!' to ApplicationController, then selectively skip for public actions",
          location: app_controller_path.to_s,
          impact: "Inconsistent authentication enforcement",
          category: :auth_bypass
        )
      end
    end

    # Check Devise configuration
    devise_config_path = Rails.root.join('config', 'initializers', 'devise.rb')
    if File.exist?(devise_config_path)
      content = File.read(devise_config_path)

      # Check for account lockout
      unless content.include?('config.lock_strategy')
        add_issue(
          title: "Devise Account Lockout Not Configured",
          severity: SEVERITY_MEDIUM,
          risk: "Brute force attacks on user accounts",
          fix: "Enable Devise lockable module and configure lock_strategy",
          location: devise_config_path.to_s,
          category: :auth_bypass
        )
      end

      # Check password requirements
      unless content.include?('config.password_length')
        add_issue(
          title: "Weak Password Requirements",
          severity: SEVERITY_MEDIUM,
          risk: "Users can set easily cracked passwords",
          fix: "Configure minimum password length (12+ characters recommended)",
          location: devise_config_path.to_s,
          category: :auth_bypass
        )
      end
    end

    # Analyze routes for unprotected paths
    load_routes

    log_verbose "✓ Authentication bypass audit complete"
  end

  def load_routes
    begin
      # Count routes (basic check)
      routes = Rails.application.routes.routes
      @stats[:routes_analyzed] = routes.size

      log_verbose "Analyzed #{routes.size} routes"
    rescue => e
      log_verbose "Could not analyze routes: #{e.message}"
    end
  end

  def generate_summary
    critical_count = @issues.count { |i| i[:severity] == SEVERITY_CRITICAL }
    high_count = @issues.count { |i| i[:severity] == SEVERITY_HIGH }
    medium_count = @issues.count { |i| i[:severity] == SEVERITY_MEDIUM }
    low_count = @issues.count { |i| i[:severity] == SEVERITY_LOW }

    {
      total: @issues.size,
      critical: critical_count,
      high: high_count,
      medium: medium_count,
      low: low_count
    }
  end

  def log_section(message)
    puts "\n#{message}..." if @verbose
  end

  def log_verbose(message)
    puts "  #{message}" if @verbose
  end
end
