# SpaceDefinition
#
# Defines the available spaces/modes in the application.
#
# THREE MODE ARCHITECTURE:
# - Personal: Private thinking space, just you and Amos, no sidebar
# - Operations: Business HQ with collaboration sidebar (agents, team, channels)
# - Design: Creation studio with collaboration sidebar (design agents, projects)
#
# DEPRECATED: Work and Team are now merged into Operations
#
class SpaceDefinition < ApplicationRecord
  # Validations
  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:display_order) }

  # Space slugs - New 3-mode architecture
  PERSONAL = 'personal'.freeze
  OPERATIONS = 'operations'.freeze
  DESIGN = 'design'.freeze
  
  # Legacy slugs (deprecated, mapped to operations)
  WORK = 'work'.freeze
  TEAM = 'team'.freeze
  
  # All valid spaces (new + legacy for backwards compatibility)
  ALL_SPACES = [PERSONAL, OPERATIONS, DESIGN, WORK, TEAM].freeze
  
  # Primary spaces (the 3-mode architecture)
  PRIMARY_SPACES = [PERSONAL, OPERATIONS, DESIGN].freeze

  # Class methods
  def self.personal
    find_by(slug: PERSONAL)
  end

  def self.operations
    find_by(slug: OPERATIONS)
  end

  def self.design
    find_by(slug: DESIGN)
  end

  # Legacy - redirect to operations
  def self.work
    operations || find_by(slug: WORK)
  end

  def self.team
    operations || find_by(slug: TEAM)
  end

  def self.default
    operations || first
  end

  # Instance methods
  def personal?
    slug == PERSONAL
  end

  def operations?
    slug == OPERATIONS
  end

  def design?
    slug == DESIGN
  end

  # Legacy helpers - treat work/team as operations
  def work?
    slug.in?([WORK, OPERATIONS])
  end

  def team?
    slug.in?([TEAM, OPERATIONS])
  end

  # Does this mode show the collaboration sidebar?
  def show_collab_sidebar?
    slug.in?([OPERATIONS, DESIGN])
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
