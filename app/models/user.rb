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
  
  # Entity Associations
  has_many :entity_users, dependent: :destroy
  has_many :entities, through: :entity_users
  
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
  
  # Integration associations
  has_many :integration_logs
  
  # Integration relationships (through entities)
  has_many :connections, through: :entities
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
    role == 'marketer'
  end
  
  def viewer?
    role == 'viewer'
  end
  
  # Entity role methods
  def entity_role(entity)
    entity_users.find_by(entity: entity)&.role
  end
  
  def entity_owner?(entity)
    entity_users.find_by(entity: entity, role: 'owner').present?
  end
  
  def entity_admin?(entity)
    eu = entity_users.find_by(entity: entity)
    eu.present? && (eu.role == 'admin' || eu.role == 'owner')
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
  
  # Get entities where the user has specific roles
  def owned_entities
    entities.includes(:entity_users).where(entity_users: { role: 'owner' })
  end
  
  def administered_entities
    entities.includes(:entity_users).where(entity_users: { role: ['owner', 'admin'] })
  end
  
  before_create :generate_api_key
  
  private
  
  def generate_api_key
    self.api_key = SecureRandom.hex(32)
  end
end
