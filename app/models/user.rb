class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  # Constants
  ROLES = %w[admin marketer viewer].freeze

  # Validations
  validates :first_name, :last_name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :password, length: { minimum: 10, message: "must be at least 10 characters long" }, if: :password_required?

  # Set defaults for test environment
  before_validation :set_test_defaults, if: -> { Rails.env.test? }

  # Entity Association - Single entity per user
  belongs_to :entity, optional: true

  # Resource Associations
  has_many :contacts, dependent: :destroy
  has_many :contact_groups, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :landing_pages, dependent: :destroy
  has_many :social_posts, dependent: :destroy
  has_many :social_media_accounts, dependent: :destroy
  has_one :business_profile, dependent: :destroy

  # Scout AI Associations
  has_many :scout_conversations, dependent: :destroy
  has_many :scout_messages, dependent: :destroy
  has_many :task_sessions, dependent: :destroy

  # Affiliate Association
  has_one :affiliate, dependent: :destroy

  # Billing Association
  has_one :user_billing_account, dependent: :destroy

  # Integration associations
  has_many :integration_logs

  # Integration relationships (through entity)
  has_many :connections, through: :entity
  has_many :integrations, through: :connections

  # Methods
  def admin?
    # Check if there's an admin user with the same email
    return false if email.blank?
    AdminUser.active.exists?(email: email.downcase)
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def marketer?
    role == "marketer"
  end

  def viewer?
    role == "viewer"
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

  # Ensure user has a business profile
  def ensure_business_profile
    return business_profile if business_profile.present?

    create_business_profile(
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

  before_create :generate_api_key
  before_create :set_resource_limits

  private

  def set_resource_limits
    self.agents_limit ||= 5
    self.tools_limit ||= 5
    self.integrations_limit ||= 5
  end

  def generate_api_key
    self.api_key = SecureRandom.hex(32)
  end

  def set_test_defaults
    self.first_name ||= "Test"
    self.last_name ||= "User"
    self.role ||= "admin"
  end
end
