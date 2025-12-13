# TeamChannel
#
# Represents a shared channel in Team Space for entity-wide collaboration.
#
class TeamChannel < ApplicationRecord
  belongs_to :entity

  # Validations
  validates :name, presence: true, uniqueness: { scope: :entity_id }
  validates :channel_type, inclusion: { in: %w[general project integration] }

  # Scopes
  scope :active, -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }
  scope :default_channels, -> { where(is_default: true) }
  scope :by_type, ->(type) { where(channel_type: type) }
  scope :ordered, -> { order(is_default: :desc, name: :asc) }

  # Channel types
  GENERAL = 'general'.freeze
  PROJECT = 'project'.freeze
  INTEGRATION = 'integration'.freeze

  # Archive the channel
  def archive!
    update!(archived: true)
  end

  # Unarchive the channel
  def unarchive!
    update!(archived: false)
  end

  # Get channel icon based on type
  def icon
    case channel_type
    when GENERAL then 'hash'
    when PROJECT then 'folder'
    when INTEGRATION then 'plug'
    else 'message-circle'
    end
  end

  # Class method to create default channels for a new entity
  def self.create_defaults_for(entity)
    create!(
      entity: entity,
      name: 'General',
      description: 'General team discussions and updates',
      channel_type: GENERAL,
      is_default: true
    )
  end

  # Class method to get or create default channel for entity
  def self.default_for(entity)
    find_by(entity: entity, is_default: true) || 
      create_defaults_for(entity)
  end
end
