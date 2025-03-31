class Contact < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  
  # Many-to-many association with contact groups
  has_and_belongs_to_many :contact_groups
  
  # Validations
  validates :email, presence: true, email: true, uniqueness: { scope: :user_id }
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
  
  # Ensure contact belongs to only one group
  validate :single_group_membership
  
  private
  
  def single_group_membership
    if contact_groups.count > 1
      errors.add(:base, "Contact can only belong to one group at a time")
    end
  end
end
