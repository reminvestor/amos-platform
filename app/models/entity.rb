class Entity < ApplicationRecord
  # Validations
  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[active inactive archived] }
  
  # Relationships with users through join table
  has_many :entity_users, dependent: :destroy
  has_many :users, through: :entity_users
  
  # Direct relationships with main resources
  has_many :contacts, dependent: :destroy
  has_many :contact_groups, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :social_posts, dependent: :destroy
  has_many :social_media_accounts, dependent: :destroy
  has_many :business_profiles, dependent: :destroy
  
  # JSONB settings accessor
  store_accessor :settings, :timezone, :currency, :date_format, :logo_url, :primary_color
  
  # Custom methods
  def owner
    entity_users.find_by(role: 'owner')&.user
  end
  
  def admins
    users.includes(:entity_users).where(entity_users: { role: ['owner', 'admin'] })
  end
  
  def members
    users.includes(:entity_users).where(entity_users: { role: 'member' })
  end
  
  # Slug generation
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  
  private
  
  def generate_slug
    base_slug = name.parameterize
    self.slug = base_slug
    
    # Check for uniqueness
    counter = 1
    while Entity.where(slug: slug).exists?
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end
end
