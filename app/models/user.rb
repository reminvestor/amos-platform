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
  
  # Associations
  has_many :contacts, dependent: :destroy
  has_many :contact_groups, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :social_posts, dependent: :destroy
  has_many :social_media_accounts, dependent: :destroy
  has_one :business_profile, dependent: :destroy
  
  # Methods
  def full_name
    "#{first_name} #{last_name}"
  end
  
  def admin?
    role == 'admin'
  end
  
  def marketer?
    role == 'marketer'
  end
  
  def viewer?
    role == 'viewer'
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
end
