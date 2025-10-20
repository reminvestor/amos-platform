class Contact < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  # Many-to-many association with contact groups
  has_and_belongs_to_many :contact_groups, -> { distinct }, class_name: "ContactGroup"

  # Email sequence associations
  has_many :sequence_enrollments, dependent: :destroy
  has_many :email_sequences, through: :sequence_enrollments

  # JSONB metadata handling - Rails 8.0 compatible
  # Note: serialize in Rails 8 now uses different configuration style
  attribute :metadata, :json

  # Helper methods for corporation data
  def corporation_id
    metadata&.dig("corporation_id")
  end

  def corporation_name
    metadata&.dig("corporation_name")
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
  scope :leads, -> { where(lead: true) }
  scope :customers, -> { where(lead: false) }

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
    # Group by entity_id
    entity_groups = contact_groups.group_by(&:entity_id)

    # For each entity, ensure there's only one group
    entity_groups.each do |entity_id, groups|
      next unless groups.size > 1

      # Keep only the most recent group for this entity
      latest_group = groups.sort_by(&:updated_at).last
      groups_to_remove = groups - [ latest_group ]

      # Remove all but the latest group
      self.contact_groups.delete(groups_to_remove)
    end
  end
end
