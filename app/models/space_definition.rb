# SpaceDefinition
#
# Defines the available spaces in the application (Personal, Work, Team).
# These are seeded records that define the core behavior of each space.
#
class SpaceDefinition < ApplicationRecord
  # Validations
  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:display_order) }

  # Space slugs
  PERSONAL = 'personal'.freeze
  WORK = 'work'.freeze
  TEAM = 'team'.freeze
  ALL_SPACES = [PERSONAL, WORK, TEAM].freeze

  # Class methods
  def self.personal
    find_by(slug: PERSONAL)
  end

  def self.work
    find_by(slug: WORK)
  end

  def self.team
    find_by(slug: TEAM)
  end

  def self.default
    work || first
  end

  # Instance methods
  def personal?
    slug == PERSONAL
  end

  def work?
    slug == WORK
  end

  def team?
    slug == TEAM
  end

  # Get tool loadout for this space
  def tool_loadout
    default_tool_loadout || []
  end

  # Get menu items for this space
  def menu_items
    default_menu_items || []
  end
end
