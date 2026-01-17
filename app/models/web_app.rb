# frozen_string_literal: true

# WebApp represents a full web application: Website + Modules + Authentication
#
# The final stage of website progression:
# LandingPage → Website → WebApp
#
# A WebApp includes:
# - A public-facing website
# - User authentication
# - Access to app modules (CRUD operations)
# - Role-based permissions
#
class WebApp < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :created_by, class_name: 'User'
  belongs_to :application_plan, optional: true
  belongs_to :website, optional: true
  
  has_many :web_app_modules, dependent: :destroy
  has_many :app_modules, through: :web_app_modules
  has_many :web_app_users, dependent: :destroy
  
  # Statuses
  STATUSES = %w[draft active paused archived].freeze
  AUTH_METHODS = %w[email magic_link google github oauth2].freeze
  
  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :entity_id }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :subdomain, uniqueness: true, allow_nil: true
  validates :custom_domain, uniqueness: true, allow_nil: true
  
  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  
  # Callbacks
  before_validation :generate_slug, on: :create
  before_create :set_default_auth_config
  
  # ============================================
  # STATUS
  # ============================================
  
  def active?
    status == 'active'
  end
  
  def activate!
    update!(status: 'active')
  end
  
  def pause!
    update!(status: 'paused')
  end
  
  def archive!
    update!(status: 'archived')
  end
  
  # ============================================
  # URL HELPERS
  # ============================================
  
  def public_url
    if custom_domain.present?
      "https://#{custom_domain}"
    elsif subdomain.present?
      "https://#{subdomain}.app.amoslabs.com"
    else
      "/apps/#{slug}"
    end
  end
  
  def login_url
    "#{public_url}/login"
  end
  
  def dashboard_url
    "#{public_url}/dashboard"
  end
  
  # ============================================
  # AUTHENTICATION
  # ============================================
  
  def auth_methods
    auth_config['methods'] || ['email']
  end
  
  def allows_registration?
    auth_config['allow_registration'] != false
  end
  
  def requires_email_verification?
    auth_config['require_email_verification'] == true
  end
  
  def session_timeout
    auth_config['session_timeout'] || 3600
  end
  
  def authenticate_user(email, password)
    # This would integrate with a proper auth system
    # For now, return the web app user if credentials match
    user = web_app_users.find_by(email: email.downcase)
    return nil unless user&.authenticate(password)
    user
  end
  
  # ============================================
  # ROLES & PERMISSIONS
  # ============================================
  
  def available_roles
    roles.map { |r| r['name'] }
  end
  
  def role_permissions(role_name)
    role = roles.find { |r| r['name'] == role_name }
    role&.dig('permissions') || []
  end
  
  def add_role!(name:, permissions: [])
    new_roles = roles.dup
    new_roles << { 'name' => name, 'permissions' => permissions }
    update!(roles: new_roles)
  end
  
  def user_can?(user, permission)
    user_role = user.respond_to?(:role) ? user.role : 'user'
    permissions = role_permissions(user_role)
    permissions.include?(permission) || permissions.include?('*')
  end
  
  # ============================================
  # MODULES
  # ============================================
  
  def add_module!(app_module, config = {})
    web_app_modules.find_or_create_by!(app_module: app_module) do |wam|
      wam.is_public = config[:is_public] || false
      wam.allow_create = config[:allow_create] || false
      wam.allow_edit = config[:allow_edit] || false
      wam.allow_delete = config[:allow_delete] || false
    end
  end
  
  def public_modules
    web_app_modules.where(is_public: true).includes(:app_module).map(&:app_module)
  end
  
  def authenticated_modules
    web_app_modules.where(is_public: false).includes(:app_module).map(&:app_module)
  end
  
  def module_config_for(app_module)
    web_app_modules.find_by(app_module: app_module)
  end
  
  # ============================================
  # BRANDING
  # ============================================
  
  def theme_color
    primary_color || '#0d6efd'
  end
  
  def logo
    logo_url || website&.favicon_url
  end
  
  # ============================================
  # FEATURES
  # ============================================
  
  def has_feature?(feature)
    features.include?(feature.to_s)
  end
  
  def enable_feature!(feature)
    update!(features: features + [feature.to_s]) unless has_feature?(feature)
  end
  
  def disable_feature!(feature)
    update!(features: features - [feature.to_s])
  end
  
  # ============================================
  # ANALYTICS
  # ============================================
  
  def track_activity!
    update!(last_activity_at: Time.current)
  end
  
  def update_user_count!
    update!(user_count: web_app_users.count)
  end
  
  # ============================================
  # SERIALIZATION
  # ============================================
  
  def to_preview
    {
      id: id,
      name: name,
      slug: slug,
      status: status,
      public_url: public_url,
      module_count: web_app_modules.count,
      user_count: user_count,
      requires_auth: requires_auth,
      features: features
    }
  end
  
  def to_config
    {
      name: name,
      slug: slug,
      public_url: public_url,
      auth: {
        methods: auth_methods,
        allow_registration: allows_registration?,
        require_verification: requires_email_verification?
      },
      roles: roles,
      modules: web_app_modules.includes(:app_module).map do |wam|
        {
          slug: wam.app_module.slug,
          name: wam.app_module.name,
          is_public: wam.is_public,
          permissions: {
            create: wam.allow_create,
            edit: wam.allow_edit,
            delete: wam.allow_delete
          }
        }
      end,
      features: features,
      branding: {
        logo: logo_url,
        primary_color: primary_color
      }
    }
  end
  
  private
  
  def generate_slug
    self.slug ||= name&.parameterize
  end
  
  def set_default_auth_config
    self.auth_config = {
      'methods' => ['email'],
      'allow_registration' => true,
      'require_email_verification' => false,
      'session_timeout' => 3600
    }.merge(auth_config || {})
    
    self.roles = [
      { 'name' => 'admin', 'permissions' => ['*'] },
      { 'name' => 'user', 'permissions' => ['read', 'create'] }
    ] if roles.empty?
  end
end

