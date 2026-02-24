class User < ApplicationRecord
  # Include MFA support (TOTP + Email OTP)
  include TwoFactorAuthenticatable

  # Encrypt sensitive fields (Story 0.4)
  # Both must be deterministic so we can query by them (find_by / where)
  encrypts :api_key, deterministic: true
  encrypts :refresh_token, deterministic: true

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable,
         :omniauthable, omniauth_providers: [:google]

  # Constants
  ROLES = %w[admin marketer viewer].freeze

  # Validations
  validates :first_name, :last_name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :password, length: { minimum: 10, message: "must be at least 10 characters long" }, if: :password_required?

  # Password complexity validations (Story 0.3)
  validate :password_complexity, if: :password_required?
  validate :password_not_common, if: :password_required?

  # Set defaults for test environment
  before_validation :set_test_defaults, if: -> { Rails.env.test? }

  # Entity Association - Single entity per user
  belongs_to :entity, optional: true
  has_many :entity_users, dependent: :destroy
  
  # Ensure user is in entity_users when entity is set
  after_save :ensure_entity_membership, if: :saved_change_to_entity_id?

  # Resource Associations
  has_many :contacts, dependent: :destroy
  has_many :contact_groups, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :landing_pages, dependent: :destroy
  has_many :design_plans, dependent: :destroy
  has_many :sent_referrals, class_name: 'UserReferral', foreign_key: 'referrer_id', dependent: :destroy
  has_many :received_referral, class_name: 'UserReferral', foreign_key: 'referred_user_id', dependent: :nullify
  has_many :social_posts, dependent: :destroy
  has_many :social_media_accounts, dependent: :destroy
  has_one :business_profile, dependent: :destroy

  # CRM Associations
  has_many :opportunities, dependent: :nullify
  has_many :activities, dependent: :nullify
  has_many :assigned_contacts, class_name: 'Contact', foreign_key: :assigned_user_id, dependent: :nullify
  has_many :assigned_activities, class_name: 'Activity', foreign_key: :assigned_user_id, dependent: :nullify

  # Scout AI Associations
  has_many :scout_conversations, dependent: :destroy
  has_many :scout_messages, dependent: :destroy

  # Hub (Collaborative Intelligence) Associations
  has_many :hub_participations, class_name: 'HubParticipant', as: :participant, dependent: :destroy
  has_many :hub_threads, through: :hub_participations
  has_many :hub_messages, as: :sender, dependent: :destroy
  has_one :hub_presence, as: :participant, dependent: :destroy
  has_many :started_hub_threads, class_name: 'HubThread', as: :started_by, dependent: :nullify
  has_many :task_sessions, dependent: :destroy
  has_many :device_tokens, dependent: :destroy
  has_many :trusted_devices, dependent: :destroy
  has_many :user_feedbacks, dependent: :destroy
  has_many :user_favorites, dependent: :destroy
  has_many :favorite_agents, through: :user_favorites, source: :favoritable, source_type: 'AgentPlugin'
  has_many :favorite_tools, through: :user_favorites, source: :favoritable, source_type: 'ToolDefinition'
  has_many :favorite_integrations, through: :user_favorites, source: :favoritable, source_type: 'Integration'

  # Amos Spaces Associations
  has_one :space_preference, class_name: 'UserSpacePreference', dependent: :destroy
  has_one :communication_preference, class_name: 'UserCommunicationPreference', dependent: :destroy
  has_many :menu_configurations, class_name: 'UserMenuConfiguration', dependent: :destroy

  # Personal Space - Notes & Reminders
  has_many :notes, class_name: 'UserNote', dependent: :destroy
  has_many :reminders, class_name: 'UserReminder', dependent: :destroy

  # Affiliate Association
  has_one :affiliate, dependent: :destroy

  # Token Economy Associations
  has_many :token_stakes, dependent: :destroy
  has_many :token_stake_transactions, through: :token_stakes
  has_many :token_claims, dependent: :destroy
  has_many :token_deposits, dependent: :destroy

  # External Agent Protocol - agents registered by this user
  has_many :external_agent_registrations, foreign_key: :operator_id, dependent: :destroy
  
  # Documentation contributions
  has_many :doc_pages_created, class_name: 'DocPage', foreign_key: :created_by_id, dependent: :nullify
  has_many :doc_pages_edited, class_name: 'DocPage', foreign_key: :last_edited_by_id, dependent: :nullify
  has_many :doc_page_revisions, dependent: :nullify

  # Skills and review eligibility
  has_many :user_skills, dependent: :destroy
  has_many :reviewer_eligibilities, dependent: :destroy
  has_many :bounty_reviews, foreign_key: :reviewer_id, dependent: :destroy

  # Billing Association
  has_one :user_billing_account, dependent: :destroy

  # Integration associations
  has_many :integration_logs, dependent: :nullify

  # User's own connections (user-scoped integrations like Gmail)
  has_many :connections, dependent: :nullify
  has_many :integrations, through: :connections
  
  # Access to all entity connections (for shared resources)
  has_many :entity_connections, through: :entity, source: :connections

  # Usage/Audit associations - nullify to preserve audit trail
  has_many :ai_usage_logs, dependent: :nullify
  has_many :work_token_transactions, dependent: :nullify
  has_many :work_token_usage_summaries, dependent: :nullify
  has_many :model_quality_logs, dependent: :nullify
  has_many :tool_usage_metrics, dependent: :nullify
  has_many :tts_usage_logs, dependent: :nullify
  has_many :analytics_query_logs, dependent: :nullify
  has_many :integration_action_executions, dependent: :nullify

  # Methods
  def admin?
    # Check if there's an admin user with the same email
    return false if email.blank?
    AdminUser.active.exists?(email: email.downcase)
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def display_name
    name = [first_name, last_name].compact_blank.join(' ')
    name.present? ? name : email&.split('@')&.first || "User ##{id}"
  end

  # Prevent soft-deleted users from signing in via Devise
  def active_for_authentication?
    super && deleted_at.nil?
  end

  def inactive_message
    deleted_at.present? ? :account_deactivated : super
  end

  def marketer?
    role == "marketer"
  end

  def viewer?
    role == "viewer"
  end

  # Amos Spaces methods
  def active_space
    raw_space = space_preference&.active_space || 'operations'
    # Map legacy spaces to new 3-mode architecture
    UserSpacePreference.normalize_space(raw_space)
  end

  def active_space_definition
    SpaceDefinition.find_by(slug: active_space) || SpaceDefinition.default
  end

  def switch_space(space_slug)
    (space_preference || build_space_preference).switch_to(space_slug)
  end
  
  # Does the user's current space show the collaboration sidebar?
  def show_collab_sidebar?
    active_space.in?(['operations', 'design'])
  end

  def communication_preferences
    communication_preference || build_communication_preference
  end

  def menu_config_for_space(space_slug)
    UserMenuConfiguration.for_user_space(self, space_slug)
  end

  # Entity role methods
  def entity_role(entity = nil)
    # If entity is provided, check EntityUser role for that specific entity
    if entity
      entity_user = EntityUser.find_by(user: self, entity: entity)
      return entity_user&.role || "viewer"
    end

    # Otherwise return user's primary role
    role
  end

  def entity_owner?(entity = nil)
    # If entity is provided, check EntityUser role
    if entity
      entity_user = EntityUser.find_by(user: self, entity: entity)
      return entity_user&.role == "owner"
    end

    # Otherwise check user's primary role
    role == "owner"
  end

  def entity_admin?(entity = nil)
    # If entity is provided, check EntityUser role
    if entity
      entity_user = EntityUser.find_by(user: self, entity: entity)
      return [ "owner", "admin" ].include?(entity_user&.role)
    end

    # Otherwise check user's primary role
    [ "owner", "admin" ].include?(role)
  end

  # Ensure user has an entity_user record for their entity
  def ensure_entity_membership
    return unless entity_id.present?
    
    existing = EntityUser.find_by(user: self, entity_id: entity_id)
    return existing if existing
    
    # Determine role - first user of entity is owner, others are members
    is_first_user = EntityUser.where(entity_id: entity_id).count.zero?
    member_role = is_first_user ? 'owner' : 'member'
    
    # Use admin role if user has admin role
    member_role = 'admin' if role == 'admin' && !is_first_user
    
    entity_user = EntityUser.create!(
      user: self,
      entity_id: entity_id,
      role: member_role
    )
    
    Rails.logger.info "👤 Created EntityUser for user #{id} in entity #{entity_id} as #{member_role}"
    entity_user
  end

  # Sync all existing users to entity_users table
  def self.sync_entity_memberships!
    count = 0
    User.where.not(entity_id: nil).find_each do |user|
      unless EntityUser.exists?(user: user, entity_id: user.entity_id)
        user.ensure_entity_membership
        count += 1
      end
    end
    Rails.logger.info "👥 Synced #{count} users to entity_users table"
    count
  end

  # Ensure user has a business profile
  def ensure_business_profile
    if business_profile.present?
      # Backfill entity_id if missing (legacy profiles may not have it)
      if business_profile.entity_id.nil? && entity_id.present?
        business_profile.update_column(:entity_id, entity_id)
      end
      return business_profile
    end

    create_business_profile(
      entity: entity,
      name: "#{full_name}'s Business",
      industry: "Technology",
      description: "A business focused on innovation and growth."
    )
  end

  # Get connected social media accounts
  def connected_social_accounts
    social_media_accounts.connected
  end

  # Check if a platform is connected
  def connected_to?(platform)
    social_media_accounts.connected.by_platform(platform).exists?
  end

  # Get account for a specific platform
  def account_for(platform)
    social_media_accounts.connected.by_platform(platform).first
  end

  # User now belongs to a single entity
  def owned_entity
    entity_owner? ? entity : nil
  end

  def administered_entity
    entity_admin? ? entity : nil
  end

  # Check if user has accepted current terms and privacy policy
  def terms_accepted?
    terms_accepted_at.present? && privacy_accepted_at.present?
  end

  # Accept terms and privacy policy
  def accept_terms!(terms_ver: '1.0', privacy_ver: '1.0')
    update!(
      terms_accepted_at: Time.current,
      terms_version: terms_ver,
      privacy_accepted_at: Time.current,
      privacy_version: privacy_ver
    )
  end

  # OAuth support - find or create user from Google OAuth
  def self.from_omniauth(auth)
    # Find existing user by provider+uid or by email
    user = find_by(provider: auth.provider, uid: auth.uid) ||
           find_by(email: auth.info.email)
    
    if user
      # Update OAuth details if needed
      if user.provider.nil?
        user.update!(
          provider: auth.provider,
          uid: auth.uid,
          avatar_url: auth.info.image
        )
      end
      user
    else
      # Create new user with OAuth
      # Generate a random password that meets complexity requirements since they'll use OAuth
      password = "#{Devise.friendly_token[0, 16]}A1!x"
      
      # Parse name
      first_name = auth.info.first_name || auth.info.name&.split(' ')&.first || 'User'
      last_name = auth.info.last_name || auth.info.name&.split(' ')&.drop(1)&.join(' ') || ''
      last_name = 'User' if last_name.blank?
      
      # Create entity for the user
      entity_name = "#{first_name}'s Organization"
      base_subdomain = entity_name.parameterize.presence || SecureRandom.hex(6)
      subdomain = base_subdomain
      counter = 1
      while Entity.where(subdomain: subdomain).exists?
        subdomain = "#{base_subdomain}-#{counter}"
        counter += 1
      end
      
      entity = Entity.create!(
        name: entity_name,
        subdomain: subdomain,
        status: 'active'
      )
      
      user = create!(
        email: auth.info.email,
        password: password,
        password_confirmation: password,
        first_name: first_name,
        last_name: last_name,
        provider: auth.provider,
        uid: auth.uid,
        avatar_url: auth.info.image,
        entity: entity,
        role: 'admin'
      )
      
      # Note: EntityUser is automatically created by the after_save :ensure_entity_membership callback
      # which runs when entity_id is set. The first user of an entity is made 'owner'.
      
      user
    end
  end

  before_create :generate_api_key
  before_create :set_resource_limits

  # Account Lockout Methods (Security Story 0.1)
  def increment_failed_login!
    update_columns(
      failed_login_attempts: (failed_login_attempts || 0) + 1,
      last_failed_login_at: Time.current
    )
  end

  def reset_failed_login!
    update_columns(failed_login_attempts: 0, last_failed_login_at: nil)
  end

  def account_locked?
    return false unless failed_login_attempts && last_failed_login_at

    # Lock for 30 minutes after 5 failed attempts
    failed_login_attempts >= 5 && last_failed_login_at > 30.minutes.ago
  end

  def unlock_account!
    reset_failed_login!
  end

  # API Key Expiration Methods (Story 0.4)
  def generate_api_key!
    self.api_key = SecureRandom.base58(32)
    self.api_key_expires_at = 90.days.from_now
    self.api_key_last_used_at = Time.current
    save!
  end

  def generate_refresh_token!
    self.refresh_token = SecureRandom.base58(64)
    self.refresh_token_expires_at = 180.days.from_now
    save!
  end

  def api_key_expired?
    api_key_expires_at.nil? || api_key_expires_at < Time.current
  end

  def refresh_token_valid?(token)
    return false if refresh_token.blank? || refresh_token_expires_at.nil?
    return false if refresh_token_expires_at < Time.current

    ActiveSupport::SecurityUtils.secure_compare(refresh_token, token)
  end

  def touch_api_key!
    update_column(:api_key_last_used_at, Time.current)
  end

  private

  # Password complexity validation (Story 0.3)
  def password_complexity
    return if password.blank?

    errors.add(:password, 'must be at least 10 characters long') if password.length < 10
    errors.add(:password, 'must contain at least one lowercase letter') unless password.match?(/[a-z]/)
    errors.add(:password, 'must contain at least one uppercase letter') unless password.match?(/[A-Z]/)
    errors.add(:password, 'must contain at least one digit') unless password.match?(/\d/)
    errors.add(:password, 'must contain at least one special character (!@#$%^&*()_+-=[]{}|;:,.<>?)') unless password.match?(/[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]/)
    errors.add(:password, 'cannot contain whitespace') if password.match?(/\s/)
  end

  # Check password against common passwords list (Story 0.3)
  def password_not_common
    return if password.blank?

    # Load common passwords list (cached in Rails.cache for thread safety)
    common_passwords = Rails.cache.fetch('common_passwords_list', expires_in: 1.hour) do
      file_path = Rails.root.join('lib', 'common_passwords.txt')
      if File.exist?(file_path)
        File.readlines(file_path).map(&:strip).to_set
      else
        Set.new
      end
    end

    if common_passwords.include?(password.downcase)
      errors.add(:password, 'is too common. Please choose a more unique password.')
    end
  end

  def set_resource_limits
    self.agents_limit ||= 1000    # Effectively unlimited - users pay per token
    self.tools_limit ||= 1000
    self.integrations_limit ||= 1000
  end

  def generate_api_key
    self.api_key = SecureRandom.base58(32)
    self.api_key_expires_at = 90.days.from_now
    self.api_key_last_used_at = Time.current
  end

  def set_test_defaults
    self.first_name ||= "Test"
    self.last_name ||= "User"
    self.role ||= "admin"
  end
end
