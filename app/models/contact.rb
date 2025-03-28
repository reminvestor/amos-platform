class Contact < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  
  # Many-to-many association with contact groups
  has_and_belongs_to_many :contact_groups
  
  # Validations
  validates :email, presence: true, uniqueness: { scope: [:user_id, :entity_id] }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, presence: true
  
  # Status options
  STATUSES = %w[active inactive unsubscribed].freeze
  validates :status, inclusion: { in: STATUSES }, allow_nil: true
  
  # Scopes
  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) if entity_id.present? }
  scope :global, -> { where(entity_id: nil) }
  
  # Methods
  def full_name
    "#{first_name} #{last_name}"
  end
end
