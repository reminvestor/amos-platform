class Contact < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  
  # Many-to-many association with contact groups
  has_and_belongs_to_many :contact_groups, -> { distinct }, class_name: 'ContactGroup'
  
  # JSONB metadata handling - Rails 8.0 compatible
  # Note: serialize in Rails 8 now uses different configuration style
  attribute :metadata, :json

  # Helper methods for corporation data
  def corporation_id
    metadata&.dig('corporation_id')
  end

  def corporation_name
    metadata&.dig('corporation_name')
  end
  
  # Validations
  validates :email, presence: true, email: true
  validates :first_name, presence: true
  validates :last_name, presence: true
  
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
  
  # Callbacks
  before_save :ensure_single_group
  
  private
  
  def single_group_membership
    return unless contact_groups.size > 1
    errors.add(:contact_groups, "can only belong to one group at a time")
  end
  
  def ensure_single_group
    return unless contact_groups.size > 1
    # Keep only the most recently added group
    self.contact_groups = [contact_groups.last]
  end
end
