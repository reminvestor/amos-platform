# UserSpacePreference
#
# Tracks which space a user is currently in and their per-space settings.
#
class UserSpacePreference < ApplicationRecord
  belongs_to :user

  # Validations
  validates :user_id, uniqueness: true
  validates :active_space, inclusion: { in: SpaceDefinition::ALL_SPACES }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  # Get the active space definition
  def active_space_definition
    SpaceDefinition.find_by(slug: active_space)
  end

  # Switch to a different space
  def switch_to(space_slug)
    return false unless SpaceDefinition::ALL_SPACES.include?(space_slug.to_s)
    return false unless space_enabled?(space_slug)
    
    update(active_space: space_slug.to_s)
  end

  # Check if a space is enabled for this user
  def space_enabled?(space_slug)
    enabled_spaces.include?(space_slug.to_s)
  end

  # Enable a space
  def enable_space(space_slug)
    return false unless SpaceDefinition::ALL_SPACES.include?(space_slug.to_s)
    
    self.enabled_spaces = (enabled_spaces + [space_slug.to_s]).uniq
    save
  end

  # Disable a space
  def disable_space(space_slug)
    return false if space_slug.to_s == 'work' # Work space cannot be disabled
    
    self.enabled_spaces = enabled_spaces - [space_slug.to_s]
    # If disabling current space, switch to work
    self.active_space = 'work' if active_space == space_slug.to_s
    save
  end

  # Get settings for the current space
  def current_settings
    send("#{active_space}_settings") || {}
  end

  # Update settings for a specific space
  def update_space_settings(space_slug, settings)
    return false unless SpaceDefinition::ALL_SPACES.include?(space_slug.to_s)
    
    update("#{space_slug}_settings" => settings)
  end

  # Class method to get or create preferences for a user
  def self.for_user(user)
    find_or_create_by(user: user)
  end

  private

  def set_defaults
    self.active_space ||= 'work'
    self.enabled_spaces ||= SpaceDefinition::ALL_SPACES
    self.personal_settings ||= {}
    self.work_settings ||= {}
    self.team_settings ||= {}
  end
end
